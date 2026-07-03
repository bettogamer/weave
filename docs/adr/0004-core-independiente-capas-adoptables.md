# ADR-0004: Core independiente + capas adoptables (wow, craft) — no framework monolítico

| | |
|---|---|
| Estado | **Aceptada** |
| Fecha | 2026-07-02 |
| Alcance | arquitectura de módulos y distribución |

## Contexto

Scorpio (el framework "moderno" existente) es monolítico: para usar cualquier pieza tragas
PLoop entero, y su adopción es mínima pese a su potencia. La web moderna fue en dirección
opuesta: piezas componibles (signals + componentes + linter) adoptables por separado. Weave
además tiene un consumidor natural (Craft) que NO debe volverse dependencia obligatoria:
Craft es dueño de sus componentes; Weave no debe exigir Craft ni Craft exigir Weave.

## Alternativas consideradas

| Alternativa | Pros | Contras |
|-------------|------|---------|
| A. Framework integrado (señales+componentes+eventos en uno) | experiencia "todo resuelto" | lección Scorpio: nadie adopta monolitos; acopla los ciclos de release de Craft y Weave |
| B. Core puro + capas opcionales | cada pieza se adopta sola; core testeable headless; releases independientes | integración Craft requiere diseño de contrato (props bindables) |

## Decisión

> **Elegimos B. Tres módulos, un solo repo, un solo build vendoreable:**
>
> ```
> Weave/
> ├── core/     signal, computed, effect, batch, scope   ← Lua puro, CERO API de WoW
> ├── wow/      fromEvent, bind, props, onUpdate, chokepoint ← única capa que toca frames
> └── craft/    props bindables de componentes Craft     ← OPCIONAL; no-op si Craft no está
> ```
>
> LibStub `"Weave-1.0"` con registro versionado (patrón `Craft.register`, lección de la
> colisión LibStub de craft/CLAUDE.md bug #1). La capa `craft/` detecta
> `LibStub("Craft-1.0", true)` en runtime; si falta, no registra nada.

## Consecuencias

- (+) `core/` corre en busted sin mock de WoW — TDD real, primera lib de addons con suite completa.
- (+) Un addon puede usar Weave sin Craft (frames nativos) y viceversa.
- (−) La frontera core/wow debe vigilarse (regla MUST en AGENTS.md: `core/` no llama nada
  de la API de WoW, ni `CreateFrame` ni `GetTime`).
- Cambios que Craft necesite para ser "bindable" van por el proceso FR de Craft (regla global).

## Validación / reversión

Acertada si `busted tests/core/` pasa sin ningún mock, y si la demo funciona con frames
nativos puros (sin Craft instalado).
