# Weave — Claude Code

> Leer **`AGENTS.md`** — fuente de verdad única. Estado actual: **DISEÑO** (no hay código;
> el siguiente hito es M0 = `core/` + busted). Las instrucciones globales de
> `~/.claude/CLAUDE.md` (taint/secret values, vendoring) aplican y tienen prioridad.

## Comandos rápidos (desde M0)

```bash
luac -p <archivo>                      # sintaxis, tras cada edición
luacheck Weave/ --config .luacheckrc   # lint — cero warnings
busted tests/                          # core/ DEBE pasar sin mock de WoW
```

## Git — reglas para Claude Code en este repo

- **Identidad local del repo**: `Betto <betto.gamer@icloud.com>` (configurada con
  `git config user.name/user.email` locales, no globales).
- **NUNCA colocar trailers de co-autoría de IA** en los commits: nada de
  `Co-Authored-By: Claude ...` ni atribuciones de herramientas ("Generated with...").
  Mensajes limpios, como si los hubiera escrito el owner. (Regla heredada de taintlint.)
- Mensajes: **Conventional Commits en español** (`feat:`, `fix:`, `docs:`, `test:`,
  `chore:`…), descriptivos y concretos. Al publicarse el repo (nivel L), evaluar cambiar a
  inglés como taintlint (su público es internacional).
- **`main` SIEMPRE verde** (tests + lint pasando en cada commit que llegue a main). Trabajo
  en `dev` o ramas cortas `feat/*`/`fix/*` que mergean a dev.
- **Releases = tags semver `v*`** sobre main.
- **MUST NOT `git push`** — lo hace el owner a mano. Commit/branch solo si el usuario lo pide.

## Convenciones (recordatorio operativo)

- **Comentarios in-code SIEMPRE en inglés** (código e identificadores también). En español:
  docs/, ADRs y las descripciones `it("...")` de los tests.

## Notas específicas de Claude Code

- Antes de escribir código de `core/`: los tests se escriben contra `docs/API-v0.md`
  (fixtures/spec primero, como taintlint).
- La frontera core/wow es sagrada: si un test de `core/` necesita un mock de WoW, el diseño
  está mal — parar y revisar, no mockear.
- Fusion es referencia de diseño, no de código: es Luau (tiene `table.freeze`, tipos,
  `task.defer`); nada de asumir que sus técnicas compilan en Lua 5.1.
