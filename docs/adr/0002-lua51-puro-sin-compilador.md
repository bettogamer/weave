# ADR-0002: Lua 5.1 puro — sin compilador, transpiler ni toolchain

| | |
|---|---|
| Estado | **Aceptada** |
| Fecha | 2026-07-02 |
| Alcance | todo el proyecto |

## Contexto

Los intentos previos de UI moderna en WoW (react-wow-addon, tsCoolDown) exigían
TypeScript-to-Lua + JSX + bundler. Todos quedaron en POC abandonado: el dev de addons
promedio edita `.lua`, copia a `AddOns/` y hace `/reload` — cualquier paso de build extra
mata la adopción. Craft ya rechazó TSTL por las mismas razones (craft ADR-0007). El objetivo
declarado de Weave es que **los devs nuevos lo usen**.

## Alternativas consideradas

| Alternativa | Pros | Contras |
|-------------|------|---------|
| A. TSTL + JSX | tipos, tooling web familiar | toolchain pesado; debugging a través de código generado; precedentes muertos |
| B. Lua 5.1 puro, API idiomática | cero fricción: copiar y usar; debuggeable in-game; embebible estilo lib | sin tipos estáticos; la ergonomía depende 100% del diseño de API |
| C. Lua + anotaciones LuaLS opcionales | B + autocompletado en editores | ninguno real — las anotaciones son comentarios |

## Decisión

> **Elegimos B+C: Lua 5.1 puro con anotaciones LuaLS (`---@class`, `---@param`) en la API
> pública.** Cero dependencias de build; las anotaciones dan autocompletado gratis a quien
> use VS Code/LuaLS sin imponer nada a quien no.

## Consecuencias

- (+) Instalar = copiar `Weave/` a `Libs/` (vendoring estándar de AddonTemplate).
- (+) Los errores apuntan a nuestras líneas reales, no a código generado.
- (−) Sin type-checking real: compensar con validación de argumentos en los constructores
  (mensajes de error claros) y suite busted.

## Validación / reversión

Acertada si un dev instala y corre el ejemplo del README sin instalar NADA más que la lib.
