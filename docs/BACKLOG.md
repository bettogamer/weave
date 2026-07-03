# Backlog de ideas — Weave

> Ideas capturadas para NO diseñarlas ahora. Nada de aquí bloquea M0–M6. Cuando una madure,
> pasa por el proceso: ADR si es decisión de fondo, o directo al roadmap si es menor.
> Regla: las mejores ideas nuevas saldrán de USAR Weave (lección Craft: FR-010 nació de
> Sentry usándolo, no de imaginar).

## Planificado (ya decidido en ADR-0005)

- **v1 — `Weave.each`**: listas reactivas con frame pooling combat-safe (barras/iconos
  dinámicos — el patrón WeakAuras/MRT).
- **v2 — DevTools `/weave`**: inspector in-game del grafo de señales (hecho con Craft).
- **v2 — utilidades de tiempo**: `throttle`/`debounce`/`delay` sobre el ticker compartido.

## Ideas futuras (sin compromiso)

- **Craft reactivo por dentro (idea del owner, 2026-07-02)**: el sistema de temas de Craft
  (`Theme.register`/`_applyTheme`) es reactividad manual — con Weave serían señales + scopes
  (adiós unregister manual, double-free, re-entrancia). Y los componentes nuevos de Craft
  podrían declararse con `Weave.new` internamente. **Camino**: usar Weave en Craft_Browser
  primero (dogfooding), y con esa experiencia abrir un **RFC en `craft/docs/requests/`**
  (decisión del repo Craft, con su ADR — invierte la dirección de dependencia, no se toma a
  la ligera). Momento natural: componentes nuevos o un "Craft 2.0".
- **Animaciones reactivas** (v3+): springs/tweens estilo Fusion — "anima suave hacia el
  valor de esta señal". Requiere `ui/` maduro y presupuesto de rendimiento propio.
- **Kit de testing para consumidores**: empaquetar los mocks/harness de Weave para que un
  dev teste SU addon headless con busted. Sale casi gratis de M0; empaquetar en M6.
- **Reglas Weave para taintlint**: que taintlint conozca `fallback`/chokepoint y avise
  cuando una señal alimentada por API secretable no declara fallback (FR a taintlint).
