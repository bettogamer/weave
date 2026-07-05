# Integrating Weave into a component library

> Audience: authors of component libraries (Craft first) that embed Weave so their
> components accept **signals as props** natively (ADR-0006). This is the reference
> for that work; the full API surface lives in `API-v0.md`.

## 1. The model in one paragraph

Weave is embedded the way Ace3 libraries are: your library vendors a **tagged build**
of Weave under `libs/Weave/` and loads it before its own files. From then on, any
component prop can accept *either* a plain value ("set it once") *or* a Weave
signal/computed ("keep it in sync forever"). Your components never need to know which
one they got — one small helper handles both.

## 2. Embedding

1. In the Weave repo, run `scripts/build-embed.ps1`. It refuses to package unless the
   full test suite and luacheck are green, and produces `dist/Weave-vX.Y.Z/Weave/`.
2. Copy that inner `Weave/` folder to `<YourLib>/libs/Weave/`.
3. Load it first. In your `.toc` (or an `embeds.xml`), **before** your own files:

   ```
   libs\LibStub\LibStub.lua
   libs\Weave\Weave.xml
   ```

   If you already ship LibStub, keep only one entry — loading LibStub twice is safe
   by design, and so is Weave: `LibStub("Weave-1.0")` resolves multiple embedded
   copies to the newest one; older copies switch themselves off.
4. Resolve it where you need it: `local Weave = LibStub("Weave-1.0")`.
5. **The vendored copy is read-only.** Record the embedded version (from
   `Weave._VERSION`) in your docs. Found a bug or missing feature? File it against
   the Weave repo and re-vendor the next tagged build — never patch `libs/`.
6. Only embed **tagged releases** (`v*`), never a snapshot of `dev`.

## 3. Weave in 60 seconds

```lua
local W = LibStub("Weave-1.0")
local hp  = W.signal(100)                                  -- a spreadsheet cell
local pct = W.computed(function() return hp() / 100 end)   -- a formula over cells
W.effect(function() print(pct()) end)                      -- runs now + on changes
hp:set(80)                                                 -- everything updates
```

Reading a signal *inside* a computed/effect subscribes automatically. `s:peek()`
reads without subscribing. `W.batch(fn)` groups writes. `W.scope()` owns effects
so they can be disposed together — that last one is the component lifecycle tool.

## 4. The component patterns

### 4.1 Accept a signal OR a literal for any prop

The one helper every component needs (this is exactly how `Weave.new` decides):

```lua
local function isCallable(v)
  if type(v) == "function" then return true end
  local mt = getmetatable(v)
  return type(mt) == "table" and mt.__call ~= nil
end

-- Applies `v` through applyFn once (literal) or reactively forever (signal).
local function applyOrBind(self, v, applyFn)
  if isCallable(v) then
    return Weave.effect(function() applyFn(self, v()) end)
  end
  applyFn(self, v)
end
```

Usage in a component constructor:

```lua
applyOrBind(self, props.text, function(self, text) self.label:SetText(text) end)
```

If the prop maps 1:1 to a native frame prop, `Weave.bind(self.frame, "value", v)`
does the same and reuses Weave's props registry.

### 4.2 One scope per component instance

WoW has no unmount — disposal is explicit. Give every component instance a scope,
create all its effects/binds inside it, and dispose it when the instance is
released or recycled into a pool:

```lua
function Component:Init(props)
  self._scope = Weave.scope()
  self._scope:run(function()
    applyOrBind(self, props.text, applyText)
    applyOrBind(self, props.disabled, applyDisabled)
  end)
end

function Component:Release()
  self._scope:dispose() -- every effect/bind dies; bound frames hide for reuse
end
```

Without this, a recycled component keeps reacting to its old signals — the classic
"ghost updates" bug.

### 4.3 Two-way controls (Slider, Checkbox)

Interactive controls both *display* a value and *produce* one. Wire both directions
to the same signal; the loop does not oscillate because a signal's equality cut
drops same-value writes:

```lua
-- signal → widget (display)
applyOrBind(self, props.value, function(self, v) self.slider:SetValue(v) end)

-- widget → signal (input); only when the prop actually IS a signal
if isCallable(props.value) and props.value.set then
  self.slider:SetScript("OnValueChanged", function(_, v)
    props.value:set(v) -- equality cut: no feedback loop
  end)
end
```

### 4.4 Persistent settings for free

`Weave.store` fields are signals, so a component wired as above is automatically
persistent when the consumer passes one:

```lua
local db = W.store("MyAddonDB", { volume = 0.5 }, { addon = addonName })
MySlider:Init({ value = db.volume }) -- moves live AND survives logout
```

Nothing extra to implement in the component.

### 4.5 Reactive collections: `Weave.each` (v0.2+)

Until v0.1 the `options`/`items` list of a component had to stay literal-only
(rebuild-all on `SetOptions`). `Weave.each` removes that limit: give it a signal
holding an array plus a **row recipe**, and it creates one frame per element,
**recycling** frames when the list changes — never destroying, and never creating
in combat (if the pool runs out mid-fight it shows what it can, warns once, and
catches up on leaving combat).

```lua
-- e.g. a Select's option list: options is now signal-or-literal like any prop
W.each(optionsSource, function(item, index)
  -- runs ONCE per pooled row; item/index are read-only signals
  return W.new("Button", {
    size = { 160, 20 },
    text = W.computed(function() return item() and item().label or "" end),
    [W.on] = { OnMouseDown = function() self:_selectIndex(index()) end },
  })
end, {
  key    = function(opt) return opt.value end, -- stable identity across reorders
  parent = self.dropdown,                      -- or place it inside [W.children]
  warm   = 8,                                  -- pre-bake rows for in-combat growth
})
```

- Rows stack vertically by default (`spacing` opt); pass `layout = false` when the
  component positions rows itself (drag lists, grids).
- `key` is what preserves per-row state (highlight, focus) when the list reorders —
  without it, identity is positional.
- The visible rows are listed on the container as `container._eachRows` (list
  order), handy for hit-testing and debugging.

## 5. Taint rules (WoW 12.0+ secret values)

Weave is taint-aware end to end; components inherit that if they follow two rules:

1. **Never operate on a value that may be secret** (no arithmetic, comparison, or
   concatenation on combat-API results). Pass it through to sinks that accept
   secrets (`SetValue`, `SetMinMaxValues`, ...). For derived text/colors, check
   `sig:isSecret()` and degrade (`"??"`, neutral color).
2. **Trust the chokepoint.** If component code inside an effect still blows up on a
   secret, Weave degrades that effect with one soft chat warning instead of the red
   error popup, and it revives when values turn normal. Real (non-secret) errors
   propagate untouched — don't wrap everything in pcall.

Also: a store field silently refuses to persist a secret (warning + skip), so
settings written from combat code can't poison the SavedVariables.

## 6. Reference examples

```lua
-- Label: one-way text
applyOrBind(self, props.text, function(self, t) self.fs:SetText(t) end)

-- Checkbox: two-way checked
applyOrBind(self, props.checked, function(self, on) self.button:SetChecked(on) end)
if isCallable(props.checked) and props.checked.set then
  self.button:SetScript("OnClick", function(btn)
    props.checked:set(btn:GetChecked())
  end)
end

-- Generic disabled (works for any component with Enable/Disable)
applyOrBind(self, props.disabled, function(self, off)
  if off then self.frame:Disable() else self.frame:Enable() end
end)
```

## 7. Upgrading the embedded copy

- Re-vendor only tagged builds; read the release notes for surface changes.
- `Weave._VERSION` (semver) and `Weave._MINOR` (LibStub revision) identify the copy
  at runtime — useful in bug reports.
- After re-vendoring, run your own suite: your components are Weave's consumers now.
