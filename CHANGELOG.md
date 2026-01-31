# Changelog

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

[1.0.0]: https://github.com/gradigit/confetti/releases/tag/v1.0.0
