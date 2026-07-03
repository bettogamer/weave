-- tests/run.lua — mini-runner de tests, Lua puro (5.1–5.4), cero dependencias.
-- Uso: lua tests/run.lua tests/core/*_spec.lua
-- API estilo busted: describe / it / asserts. En CI se puede migrar a busted sin tocar los specs.

local passed, failures = 0, {}
local path = {}

function describe(name, fn)
  path[#path + 1] = name
  local ok, err = pcall(fn)
  if not ok then
    failures[#failures + 1] = { name = table.concat(path, " › "), err = "(describe) " .. tostring(err) }
  end
  path[#path] = nil
end

function it(name, fn)
  local full = table.concat(path, " › ") .. " › " .. name
  local ok, err = xpcall(fn, debug.traceback)
  if ok then
    passed = passed + 1
    io.write(".")
  else
    failures[#failures + 1] = { name = full, err = err }
    io.write("F")
  end
end

function assert_eq(got, expected, msg)
  if got ~= expected then
    error(("%s\n  esperado: %s\n  obtenido: %s"):format(msg or "valores distintos",
      tostring(expected), tostring(got)), 2)
  end
end

function assert_true(v, msg)  assert_eq(not not v, true,  msg) end
function assert_false(v, msg) assert_eq(not not v, false, msg) end

function assert_error(fn, pattern, msg)
  local ok, err = pcall(fn)
  if ok then error((msg or "se esperaba un error") .. " (no hubo error)", 2) end
  if pattern and not tostring(err):find(pattern) then
    error(("%s\n  el error no contiene %q:\n  %s"):format(msg or "error inesperado", pattern, tostring(err)), 2)
  end
end

-- ejecutar los specs pasados como argumentos
local specs = { ... }
if #specs == 0 then print("uso: lua tests/run.lua <spec.lua> [...]") os.exit(2) end
for _, spec in ipairs(specs) do
  local chunk = assert(loadfile(spec))
  chunk()
end

print(("\n%d ok, %d fallos"):format(passed, #failures))
for _, f in ipairs(failures) do
  print(("\nFALLO: %s\n%s"):format(f.name, f.err))
end
os.exit(#failures == 0 and 0 or 1)
