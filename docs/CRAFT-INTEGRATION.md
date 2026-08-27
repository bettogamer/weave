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

The one helper every component needs (this is exactly how `Weave.new` decides).
Ask Weave whether a value is reactive — do NOT re-implement the check by poking at
a signal's metatable, or you couple Craft to Weave's internal shape:

```lua
-- Applies `v` through applyFn once (literal) or reactively forever (signal).
local function applyOrBind(self, v, applyFn)
  if Weave.isReactive(v) then -- signal, computed or function → bind
    return Weave.effect(function() applyFn(self, v()) end)
  end
  applyFn(self, v)            -- scalar/table → apply once
end
```

`applyOrBind` and `disposeAll` stay in Craft (component contract + `Destroy()`
lifecycle); only the reactivity predicates come from Weave.

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

-- widget → signal (input); only when the prop actually IS a writable signal
if Weave.isWritable(props.value) then
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

### 4.6 Animations: `Weave.tween` (v0.4+)

`Weave.tween(target, opts)` returns a **read-only reactive** whose value *slides*
toward `target()` over time instead of snapping. Bind it to any prop like a signal;
it seeds at the current value, re-targets from wherever it is, degrades on secret,
is combat-safe (it only mutates), and costs nothing at rest (one shared driver frame
that hides itself when no animation is running). `target` may be a **number** or an
**array of numbers** (interpolated per element — `{r,g,b}`, `{x,y}`).

The one addition beyond a plain tween is **`t:animating()`** — a reactive boolean, true
while an animation is in flight. It exists to coordinate the **exit** of a modal/collapse
declaratively (no callbacks): keep the frame shown while opening OR while the closing
animation still runs, so it hides *after* the fade, not before.

```lua
-- A modal/collapse: ONE boolean drives fade (alpha) + expand (height).
local open   = self.props.open              -- a signal (or a literal for static)
local alpha  = W.tween(W.computed(function() return open() and 1 or 0 end),
  { duration = 0.15 })
local height = W.tween(W.computed(function() return open() and FULL_H or HEADER_H end),
  { duration = 0.15, easing = W.easing.outQuad })
-- stays shown through the closing fade, then hides (frees clicks) — this is :animating()
local shown  = W.computed(function() return open() or alpha:animating() end)

W.bind(self.frame, "alpha",  alpha)
W.bind(self.frame, "height", height)
W.bind(self.frame, "shown",  shown)

-- color as an array tween (e.g. a bar going red→green): lerped channel by channel
local barColor = W.tween(W.computed(function()
  return danger() and { 0.85, 0.2, 0.2 } or { 0.2, 0.8, 0.3 }
end), { duration = 0.2 })
W.bind(self.bar, "statusBarColor", barColor)
```

- `opts.duration` (default `0.3`), `opts.easing` (default `outQuad`; also `linear`,
  `inQuad`, `inOutQuad`, or any `(t)→t`), `opts.fallback` (value exposed if the target
  degrades to a secret). `Weave.spring` is reserved as a future sibling (ADR-0008).
- **WoW render caveat — do NOT animate a frame's height to exactly 0.** A frame whose
  rendered area collapses to 0 (`SetHeight(0)`) and then grows again does not repaint on
  the 2nd+ cycle (WoW holds the right values — `GetHeight` proves it — but skips the
  redraw). So a collapse should animate height to a **non-zero header height**, never 0;
  full invisibility is the **alpha fade** (children inherit the parent's alpha). `Hide`/
  `Show` (via the `shown` bind above) is fine. Verified in-game 12.0.7; not a Weave bug.
- **`t:snap(value)` (v0.9+) — teleport, then keep going.** It sets the value at once and
  re-aims at the current target: if there is road left it restarts from there; if `value`
  already IS the target there is nothing to travel, so it just disarms. That single call
  covers both idioms:
  ```lua
  local alpha = W.tween(visible, { duration = 0.25 })
  alpha:snap(0.45)        -- FADE-IN: content enters at half light and rises on its own
  alpha:snap(visible())   -- JUMP TO THE END: no animation at all
  ```
  Use the first form whenever content is *replaced* under a filter/tab change — before
  `snap` this needed a ping-pong through the source signal (down, then back up), which
  takes twice as long and shows one full-brightness frame first. A tween never rests at a
  value that is not its target, so `animating()` turns on only if road actually remains.
- Create the tweens inside the component's scope (§4.2) so they dispose with the instance.

### 4.7 Virtualized grids: `Weave.virtual` (v0.6+)

`Weave.each` bakes one frame per entry — perfect for small dynamic lists (auras, a
DragList). For a bag/inventory grid of **thousands** of entries, use its sibling
`Weave.virtual`, which keeps a **fixed pool** of ~N visible cells (sized to the
viewport) and re-glazes them as you scroll: the pool never grows with the list.

```lua
-- Craft owns the scrollbar; Weave owns the windowing. They share ONE signal.
local scroll = W.signal(0) -- position in px; your Craft scrollbar moves it

local grid = W.virtual(self.props.items, {
  parent    = self.viewport,     -- the container IS the viewport (virtual clips it)
  viewport  = { 240, 400 },
  rowHeight = 40,
  columns   = 6,                 -- 1 = single-column list
  scroll    = scroll,            -- virtual only READS it
  render    = function(item, index)
    return W.new("Button", { size = { 38, 38 } }) -- runs ONCE per pooled cell
  end,
})

-- Wire your Craft scrollbar to the shared signal + the exposed content height:
W.effect(function() craftScrollbar:SetContentHeight(grid:contentHeight()) end) -- reactive: sizes the thumb
craftScrollbar.onChange = function(px) scroll:set(px) end                      -- scrollbar → signal
```

- Weave never references Craft: the scrollbar feeds `scroll` (position **in**), and
  `grid:contentHeight()` is a **reactive read** the scrollbar binds to (total height
  **out**). Same signal-or-literal / `applyOrBind` spirit as §4.1, one level in.
- Omit `opts.scroll` and `virtual` creates its own signal and wires the mouse wheel —
  good for a standalone panel without a Craft scrollbar.
- **Do NOT nest it in a native `ScrollFrame`** that scrolls a giant child: that would
  materialize thousands of frames — the exact thing virtualization avoids. The scroll
  is a *position*, not a scrolled child.
- The chrome (header, scrollbar) must be a **sibling** of the viewport, not a child:
  `virtual` sets `SetClipsChildren(true)` on the container, so children outside the
  viewport bounds get clipped.
- **Keep your scroll signal in range.** When the list shrinks below the current scroll
  (e.g. collapsing the last group while scrolled to the bottom), `virtual` clamps its
  *painting*, but the scroll signal is **yours** — it only reads it. Re-clamp it:
  ```lua
  W.effect(function()
    local maxS = math.max(0, grid:contentHeight() - viewportHeight) -- tracked
    if scroll:peek() > maxS then scroll:set(maxS) end               -- peek: no loop
  end)
  ```
- Keying is positional (the window case). `render` + `rowHeight` is the homogeneous mode;
  for **interleaved group headers** (v0.7+) swap them for `opts.typeOf(entry)` +
  `opts.types = { [name] = { render, height, grid? } }`. Types with `grid = true` flow in
  the N columns; types without it are **full-width** and break the flow. There is a pool
  **per type** (a cell baked as a header can never recycle as an item). **Collapse is
  yours**: the stream is a computed over your own `collapsed` signal — `virtual` is a
  window over whatever flat stream it gets and does not know what a group is.
- **Resizable windows — `grid:Resize{ width?, height?, columns? }` (v0.9+).** The viewport
  stopped being a construction constant, so a window with a resize grip no longer has to
  tear the grid down (or ask for a `/reload`). Sugar: `SetViewport(w, h)`,
  `SetViewportHeight(h)`, `SetColumns(n)`. Call it on every frame of the drag:
  ```lua
  window.onResize = function(w, h)
    grid:Resize({ width = w, height = h, columns = math.floor(w / CELL) })
  end
  ```
  Idempotent when nothing changed. **Shrinking is free** — the spare cells stay hidden in
  the pool and are reused when it grows back, so dragging does not churn frames. **In
  combat** the geometry still applies at once; only *creating* the extra cells a taller
  viewport wants is deferred to `PLAYER_REGEN_ENABLED` (it warns once and shows fewer rows
  meanwhile), exactly like `Weave.each`. Remember to re-clamp your scroll signal, same as
  when a group collapses.
- **Indented sub-sections — `opts.indentOf(entry) → px` (v0.9+).** For a band of cells that
  hangs off the header above it (a category split by slot). It is **per row**, not per
  type, so ONE `render` serves every level — no `item` / `itemIndented` twins:
  ```lua
  indentOf = function(e) return (e.depth or 0) * 16 end,
  ```
  Cells **keep their size** and the band simply fits fewer columns
  (`floor((usableW - indent) / colWidth)`, min 1) — if the cells shrank instead, the indent
  would read as "these items are smaller". A change of indent breaks the open row, and
  full-width rows are inset and narrowed too, so a sub-header hangs aligned with its own
  items. Heterogeneous mode only; default 0.
- Create it inside the component's scope (§4.2) so it disposes with the instance.

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
if Weave.isWritable(props.checked) then
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
