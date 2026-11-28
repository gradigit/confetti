# Changelog

## [1.3.2] - 2026-11-28

### Fixed
- Confetti looks like paper again. 1.3.1 kept 1.3.0's drag and fade but lost the per-piece flip:
  pieces held one fixed tilt and spun flat, with the same colour on both sides and one shared sway.
  Each piece now plays a flip strip (full width, edge-on, darker back) through the emitter's
  sprite-sheet frames, starting at a random point, in three flip speeds that each sway at their own
  rhythm. Spin is back to 1.3.0's speed. Still entirely in `CAEmitterLayer`: same particle count,
  no per-frame app work, ~7 MB more memory for the flip strips.

## [1.3.1] - 2026-11-27

### Fixed
- Frame drops with several displays attached. 1.3.0 animated one Core Animation layer per
  particle; with three screens (two QHD) the system compositor fell ~12 fps behind the 1.2.0
  emitter. Confetti now runs in `CAEmitterLayer` again, keeping the drag, sway, fade and 3D
  tumbling through the emitter's private behaviors (`drag`, `wave`, `valueOverLife`, plane
  particles with per-particle mass). Falls back to the plain 1.2.0 emitter if those are missing.
- Launch CPU back to 1.2.0 levels (~60 ms per burst; 1.3.0 was 70–140 ms).

## [1.3.0] - 2026-11-20

### Changed
- Confetti presets (default, subtle, intense, fireworks) use a new burst engine instead of
  `CAEmitterLayer`: velocity-proportional air drag, sideways sway, and a 3D flip with a darker
  back face. The burst is simulated once at launch (~4 ms) and committed to Core Animation as
  keyframe animations, so the app does no per-frame work.
- Lower GPU use than 1.2.0 (11% vs 16% system-wide during a default burst on an M4 MacBook Air)
  and the overlay exits ~0.3 s sooner. About 30 ms more CPU at launch.
- Existing physics flags and config-file fields keep working; they're mapped onto the new physics,
  calibrated so the defaults keep the same overall look. `scaleSpeed` and `alphaSpeed` now apply to
  `snow` only.

### Added
- `ConfettiController.onComplete` and `duration`: completion fires when the last particle is gone.

### Fixed
- Overlays stayed up a few hundred ms after the animation ended: `asyncAfter` on an idle app fires
  ~5% late. Exit, `--duration` and the snow emission stop now use precise timers.
- Particle size depended on the main display's scale (2× design size on Retina). Burst images are
  drawn at the target display's pixel scale.

## [1.0.0] - 2026-01-31

### Added
- Initial release
- ConfettiKit library with configurable particle system
- CLI executable with screen selection, duration, and intensity options
- Physics flags: --birth-rate, --velocity, --gravity, --spin, --scale, --lifetime
- Presets: default, subtle, intense, snow, fireworks
- Config file support (~/.config/confetti/config.json) with --save-config
- Multi-monitor support
- Hardware-accelerated rendering via CAEmitterLayer
- Texture caching with CGContext fallback for headless environments
- 8 colors, 3 shapes (rectangle, triangle, circle)
- Input validation and error messages for CLI arguments
- Main thread preconditions on public API
- Cancellable emission timer to prevent cleanup races
- Emission styles: `.cannons` (corner cannons) and `.curtain` (top-edge line emitter)
- Snow preset uses curtain emission with gravity-driven fall and gentle lateral sway

[1.0.0]: https://github.com/gradigit/confetti/releases/tag/v1.0.0
