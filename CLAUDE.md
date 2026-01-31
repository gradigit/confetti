# Confetti - Project Instructions

## Commands

```bash
swift build                              # Debug build
swift build -c release                   # Release build
swift test                               # Run tests (requires Xcode)
.build/release/confetti                  # Run confetti
.build/release/benchmark        # Run benchmarks (requires display)
cp .build/release/confetti ~/.local/bin/ # Install locally
```

## Key Files

| File | Purpose |
|------|---------|
| `Sources/ConfettiKit/ConfettiConfig.swift` | Particle config, shape enum, emission styles, and presets |
| `Sources/ConfettiKit/ConfettiEmitter.swift` | Core emitter + texture caching |
| `Sources/ConfettiKit/ConfettiController.swift` | Orchestrates multi-screen confetti display |
| `Sources/ConfettiKit/ConfettiWindow.swift` | Transparent click-through overlay window (internal) |
| `Sources/confetti/main.swift` | CLI entry point with arg parsing |
| `Sources/confetti/ConfigFile.swift` | JSON config file loading/saving |
| `Sources/benchmark/main.swift` | Performance benchmark suite |

## Architecture

- **ConfettiKit** library: Reusable Swift package for confetti animations
- **confetti** executable: CLI with presets, physics flags, and config file support
- **benchmark** executable: Performance measurement (needs display context)
- Particle system uses `CAEmitterLayer` + `CAEmitterCell` (hardware-accelerated)
- Two emission styles: `.cannons` (corner cannons for confetti) and `.curtain` (top-edge line emitter for snow)
- Textures are cached statically on first access (`static let` for thread-safe lazy init)
- Windows use `CATransaction.flush()` to ensure visibility before emitting

## Code Style

- Swift 5.9, macOS 12+
- No external dependencies
- MARK comments for section organization
- Public API has doc comments

## Known Issues

- Benchmark executable crashes without display context (exit code 139)
- XCTest requires full Xcode, not just Command Line Tools
- `cachedImages` static init uses `NSImage(size:flipped:)` block-based drawing which needs graphics context
