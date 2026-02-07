# Confetti - Project Instructions

## Commands

```bash
swift build                              # Debug build
swift build -c release                   # Release build
swift test                               # Run tests (requires Xcode)
.build/release/confetti                  # Run confetti
.build/release/benchmark                 # Run benchmarks (requires display)
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

## Distribution

- **Homebrew tap**: `gradigit/homebrew-tap` with formula at `Formula/confetti.rb`
- **GitHub Release**: v1.0.0 with universal binary (arm64 + x86_64) tarball
- **Release workflow**: `.github/workflows/release.yml` triggers on `v*` tags, builds universal binary, publishes release
- Install command: `brew install gradigit/tap/confetti`

## Promo Video

- Source: `my-video/` (Remotion project, not committed to repo)
- Final render: `assets/ConfettiPromo.mp4` (committed)
- Embedded in README via GitHub user-attachments URL
- **Important**: The video shows `$ brew install gradigit/tap/confetti` in the closing scene and preset names/descriptions throughout. If the install command, tap name, preset names, or any visible text in the video changes, the video must be re-rendered and re-uploaded, or removed from the README. The video source is in `my-video/` locally.

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

## Prototypes

Standalone Swift packages in `Prototypes/` for experimental features:

| Prototype | Approach | Key Feature |
|-----------|----------|-------------|
| `InteractiveConfetti/` | SpriteKit + ConfettiKit | Mouse-following repulsion field pushes confetti |
| `SnowAccumulation/` | SpriteKit (no ConfettiKit) | Physics-based snow landing + pile accumulation + mouse sweep |
| `SnowAccumulationCA/` | Pure Core Animation (no SpriteKit) | CAEmitterLayer snow + CAShapeLayer pile, time-based growth |

**SnowAccumulation** (SpriteKit): Individual `SKSpriteNode` snowflakes with `SKPhysicsBody` — enables per-particle landing detection, pile growth where snow actually falls, mouse cursor repulsion field + pile sweeping. Uses `SKFieldNode.noiseField` for organic wind drift.

**SnowAccumulationCA** (Core Animation): `CAEmitterLayer` for GPU-managed snow particles, `CAGradientLayer` + `CAShapeLayer` mask for pile. Time-based pile growth with 8-second delay matching snow fall time. Adjusts particle lifetime as pile rises. Near-zero CPU cost but no per-particle interactivity.

Build/run: `cd Prototypes/<name> && swift build && swift run`

## architect/ Directory

Pre-planning artifacts for the snow accumulation feature. The prototypes in `Prototypes/SnowAccumulation*` are the implemented result.

- `prompt.md` — the original specification
- `transcript.md` — Q&A log from the planning process
- `plan.md` — the execution plan (implemented via prototypes)
- `STATE.md` — planning skill state. Ignore.

## Known Issues

- Benchmark executable crashes without display context (exit code 139)
- XCTest requires full Xcode, not just Command Line Tools
- `cachedImages` static init uses `NSImage(size:flipped:)` block-based drawing which needs graphics context
- `SKView.preferredFramesPerSecond = 0` can tank performance on ProMotion displays (transparent overlay at 120Hz kills window server compositing). Use explicit 60 instead.
- Swift range expressions with negative bounds (e.g., `-50...-30`) cause ambiguous operator errors — add spaces: `-50 ... -30`
- `CAEmitterLayer` cell properties can't be modified directly after setup — use `setValue(_:forKeyPath: "emitterCells.<name>.<property>")` on the emitter layer
- HeightMap range calculations with off-screen coordinates can produce inverted ranges (`start > end`) — always guard before `start...end`
