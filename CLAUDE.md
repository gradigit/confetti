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
| `Sources/ConfettiKit/ConfettiConfig.swift` | Particle config, shape enum, emission styles, WindowLevel, and presets |
| `Sources/ConfettiKit/ConfettiEmitter.swift` | Core emitter + texture caching |
| `Sources/ConfettiKit/ConfettiController.swift` | Orchestrates multi-screen confetti display, escalate/deescalate API |
| `Sources/ConfettiKit/ConfettiWindow.swift` | Transparent click-through overlay window (internal) |
| `Sources/ConfettiKit/BlizzardScene.swift` | SpriteKit snow scene with multi-session layers, pile accumulation, wind, mouse interaction |
| `Sources/ConfettiKit/BlizzardWindow.swift` | Transparent overlay window hosting the SpriteKit blizzard scene |
| `Sources/ConfettiKit/BlizzardSessionStyle.swift` | Per-session visual params (tint, shape, wind), palette, session layer class, textures |
| `Sources/ConfettiKit/HeightMap.swift` | Snow pile height data, deposit/sweep logic, path generation, color deposit tracking |
| `Sources/confetti/main.swift` | CLI entry point with arg parsing |
| `Sources/confetti/ConfigFile.swift` | JSON config file loading/saving |
| `Sources/confetti/BlizzardCoordinator.swift` | Singleton IPC: PID file ownership, DNC escalation, session lifecycle, SIGTERM |
| `Sources/confetti/TranscriptWatcher.swift` | GCD file system watcher for transcript modification detection |
| `Sources/benchmark/main.swift` | Performance benchmark suite |

## Distribution

- **Homebrew tap**: `gradigit/homebrew-tap` with formula at `Formula/confetti.rb`
- **GitHub Release**: v1.2.0 with universal binary (arm64 + x86_64) tarball
- **Release workflow**: `.github/workflows/release.yml` triggers on `v*` tags, builds universal binary, publishes release
- Install command: `brew install gradigit/tap/confetti`

## Promo Video

- Source: `my-video/` (Remotion project, not committed to repo)
- Final render: `assets/ConfettiPromo.mp4` (committed)
- Blizzard preview: `assets/BlizzardPreview.mp4` (committed, screen recording of single-session blizzard)
- Promo video embedded in README via GitHub user-attachments URL; blizzard preview referenced via raw repo URL
- **Important**: The promo video shows `$ brew install gradigit/tap/confetti` in the closing scene and preset names/descriptions throughout. If the install command, tap name, preset names, or any visible text in the video changes, the video must be re-rendered and re-uploaded, or removed from the README. The video source is in `my-video/` locally.
- **TODO**: Blizzard preview video only shows single-session. Needs re-recording to show multi-session escalation with colored snow layers.

## Architecture

- **ConfettiKit** library: Reusable Swift package for confetti animations
- **confetti** executable: CLI with presets, physics flags, and config file support
- **benchmark** executable: Performance measurement (needs display context)
- Particle system uses `CAEmitterLayer` + `CAEmitterCell` (hardware-accelerated)
- Three emission styles: `.cannons` (corner cannons for confetti), `.curtain` (top-edge line emitter for snow), `.blizzard` (SpriteKit interactive snow)
- Blizzard preset uses SpriteKit (`BlizzardScene` + `BlizzardWindow`) — a completely separate rendering path from CAEmitterLayer
- Textures are cached statically on first access (`static let` for thread-safe lazy init)
- Windows use `CATransaction.flush()` to ensure visibility before emitting
- Window level is configurable via `--window-level` (normal/floating/statusBar), defaults to `.statusBar`
- Blizzard uses `BlizzardCoordinator` for singleton pattern — PID file at `/tmp/confetti-blizzard.pid`, `DistributedNotificationCenter` for escalation
- Multi-session blizzard: each session gets a distinct pastel color, snowflake shape, wind pattern, and fall speed via `BlizzardSessionLayer`
- `--stop-on-modify` watches a file with `DispatchSource.makeFileSystemObjectSource` — fires when file grows beyond initial size
- Four pastel session slots (ice blue, lavender, mint, rose) cycle for 5+ sessions

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
| `InteractiveConfettiSK/` | Pure SpriteKit | Standalone SpriteKit confetti with physics, accumulation, mouse repulsion |
| `SnowAccumulation/` | SpriteKit (no ConfettiKit) | Physics-based snow landing + pile accumulation + mouse sweep + confetti mode |
| `SnowAccumulationCA/` | Pure Core Animation (no SpriteKit) | CAEmitterLayer snow + CAShapeLayer pile, time-based growth |

**SnowAccumulation** (SpriteKit): Individual `SKSpriteNode` snowflakes with `SKPhysicsBody` — enables per-particle landing detection, pile growth where snow actually falls, mouse cursor repulsion field + pile sweeping. Uses `SKFieldNode.noiseField` for organic wind drift. Supports `--mode confetti` for SpriteKit confetti (WIP, needs manual physics tuning). Window level `.floating` so active windows appear above the overlay.

**SnowAccumulationCA** (Core Animation): `CAEmitterLayer` for GPU-managed snow particles, `CAGradientLayer` + `CAShapeLayer` mask for pile. Time-based pile growth with 8-second delay matching snow fall time. Adjusts particle lifetime as pile rises. Near-zero CPU cost but no per-particle interactivity.

Build/run: `cd Prototypes/<name> && swift build && swift run` (or `swift build && .build/debug/<name> --mode confetti` for mode flags)

## architect/ Directory

Pre-planning artifacts for the snow accumulation feature. The prototypes in `Prototypes/SnowAccumulation*` are the implemented result.

- `prompt.md` — the original specification
- `transcript.md` — Q&A log from the planning process
- `plan.md` — the execution plan (implemented via prototypes)
- `STATE.md` — planning skill state. Ignore.

## Architecture Decisions

- **Keep CAEmitterLayer for confetti**: The existing confetti presets (default, subtle, intense, fireworks) are perfectly tuned on CAEmitterLayer and don't need per-particle interaction. Don't port them to SpriteKit.
- **SpriteKit only for interactive snow** (`blizzard` preset): Uses SpriteKit for snow accumulation, pile sweep, and mouse repulsion. Heavier than CAEmitterLayer snow but provides interactivity.
- **Separate preset, not hidden toggle**: Users explicitly opt into the heavier SpriteKit snow via `confetti -p blizzard`, keeping the lightweight `snow` preset as-is on CAEmitterLayer.
- **Window level `.statusBar`** for blizzard overlays so snow appears on top of everything except system notifications.
- **Blizzard end conditions**: Any column hits 25% screen height (auto-stop), user sweeps 8% of max pile area (auto-stop, scales with screen size), or programmatic `stopSnowing()` call. All trigger melt animation: pile heights decay + alpha fades over 2s, airborne flakes fade simultaneously → `onBlizzardComplete` callback.
- **Blizzard physics tuning**: Gravity -0.25 (not -0.13 from prototype) and linearDamping 0.15 (not 0.3) give ~4s fall time. Spawn rate 8.3/sec (interval 0.12s). Original prototype values were too floaty for visible accumulation in reasonable time.
- **Blizzard ignores physics CLI flags**: `--gravity`, `--velocity`, `--birth-rate`, `--lifetime`, `--spin`, `--scale`, `--intensity` are all ignored for blizzard (SpriteKit uses hardcoded physics). A warning is printed to stderr if the user passes them.
- **Singleton blizzard via BlizzardCoordinator**: First `confetti -p blizzard --stop-on-modify <path>` claims PID file at `/tmp/confetti-blizzard.pid`. Subsequent launches post `DistributedNotificationCenter` escalation and exit immediately. Owner adds session layers with distinct visuals.
- **Multi-session visual distinction**: 4 pastel palette slots (ice blue #BFE0FF, lavender #D6C7FF, mint #BFFFDF, rose #FFCCDA) with different snowflake shapes (circle, hexagon, star, diamond), wind patterns, fall speeds, and rotation styles. Field bitmask isolation ensures each session's wind only affects its own particles.
- **Session removal vs scene completion**: `removeSessionLayer` fades one session's flakes without triggering melt. `stopSnowing` triggers full scene shutdown with melt animation. Last session removal auto-triggers `stopSnowing`.
- **TranscriptWatcher**: Records initial file size, fires at most once when file grows. Prevents false triggers from the hook's own transcript entry still being flushed.
- **SIGTERM graceful shutdown**: Uses `DispatchSource.makeSignalSource` (not `signal()`) for Cocoa-safe signal handling. Triggers melt animation before exit.

## Known Issues

- Benchmark executable crashes without display context (exit code 139)
- XCTest requires full Xcode, not just Command Line Tools
- `cachedImages` static init uses `NSImage(size:flipped:)` block-based drawing which needs graphics context
- `SKView.preferredFramesPerSecond = 0` can tank performance on ProMotion displays (transparent overlay at 120Hz kills window server compositing). Use explicit 60 instead.
- Swift range expressions with negative bounds (e.g., `-50...-30`) cause ambiguous operator errors — add spaces: `-50 ... -30`
- `CAEmitterLayer` cell properties can't be modified directly after setup — use `setValue(_:forKeyPath: "emitterCells.<name>.<property>")` on the emitter layer
- HeightMap range calculations with off-screen coordinates can produce inverted ranges (`start > end`) — always guard before `start...end`
- SpriteKit physics values (gravity, velocity) are NOT the same scale as CAEmitterLayer — CA values like velocity=1500 and yAcceleration=-750 are way too extreme for SpriteKit and make particles invisible (off-screen in a single frame). SpriteKit confetti needs manual tuning; values around velocity=350, gravity=-5 are a starting point
- `NSColor.white.getRed()` deadlocks during `skView.presentScene()` — color space conversion from calibratedWhite to RGB conflicts with SpriteKit's internal locks. Fix: use raw RGB values during scene setup (`didMove(to:)`), only call NSColor methods after scene is live. Don't auto-create session layers in `didMove(to:)` — let the coordinator add them after `fire()` returns.
- macOS GUI apps (NSApplication) can't create windows from background shell processes — must be run from a foreground terminal
- The installed binary at `~/.local/bin/confetti` is separate from the debug build at `.build/debug/confetti` — after code changes, run `swift build -c release && cp .build/release/confetti ~/.local/bin/` to update the installed copy
