# Confetti 🎉

Confetti animation for macOS. A small dopamine hit for your development workflow. Fires from the corners of every connected display at once, or drops gentle snow from the top edge. Inspired by [Raycast's confetti](https://raycast.com), but that one only fires on a single display, requires Raycast to be installed, and is closed source. This is standalone, multi-monitor, and MIT licensed.

![macOS](https://img.shields.io/badge/macOS-12.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)
![License](https://img.shields.io/badge/License-MIT-green)

https://github.com/user-attachments/assets/ab8bb451-376f-4753-b5f8-29f6e2e51c18

## Features

- Hardware-accelerated via Core Animation
- Works across all connected displays
- Configurable colors, shapes, and physics
- Usable as a Swift package or standalone CLI
- No dependencies

## Installation

### Homebrew

```bash
brew install gradigit/tap/confetti
```

### Download

Grab the universal binary from [GitHub Releases](https://github.com/gradigit/confetti/releases/latest):

```bash
curl -sL https://github.com/gradigit/confetti/releases/latest/download/confetti-1.0.0.tar.gz | tar xz
mkdir -p ~/.local/bin
mv confetti ~/.local/bin/
```

Make sure `~/.local/bin` is in your `PATH`.

### Build from source

```bash
git clone https://github.com/gradigit/confetti.git
cd confetti
swift build -c release
cp .build/release/confetti ~/.local/bin/
```

### Swift package manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/gradigit/confetti.git", from: "1.0.0")
]
```

## Usage

### Command line

```bash
# Fire confetti on all screens
confetti

# Use a preset
confetti -p intense

# Custom physics
confetti --velocity 2000 --gravity -500

# Combine preset with overrides
confetti -p subtle --spin 20

# Fire confetti for 5 seconds
confetti -d 5

# Save your settings to a config file
confetti -p intense --save-config

# Show help
confetti --help
```

### Options

| Option | Description | Default |
|--------|-------------|---------|
| `-d, --duration` | Duration before exit (seconds) | auto |
| `-i, --intensity` | Particle intensity (0.0-1.0) | 1.0 |
| `-s, --screen` | Screen index (0 = primary) | all |
| `-p, --preset` | Use a preset (see below) | default |
| `-v, --version` | Show version | - |
| `-h, --help` | Show help | - |

### Physics flags

| Flag | Description | Default |
|------|-------------|---------|
| `--birth-rate` | Particles per second per cell | 40 |
| `--velocity` | Initial velocity | 1500 |
| `--gravity` | Y acceleration (negative = down) | -750 |
| `--spin` | Rotation speed | 12.0 |
| `--scale` | Particle size | 0.8 |
| `--lifetime` | Particle lifetime (seconds) | 4.5 |

### Presets

| Preset | Description |
|--------|-------------|
| `default` | Balanced celebration confetti |
| `subtle` | Gentle, understated — fewer particles, slower |
| `intense` | High-energy — more particles, faster, bigger |
| `snow` | Gentle falling snow from the top edge |
| `fireworks` | Fast explosive burst with heavy gravity |

```bash
# List presets with their values
confetti --presets
```

### Config file

Save your preferred settings to `~/.config/confetti/config.json`:

```bash
# Save current settings (including preset + overrides)
confetti -p intense --spin 20 --save-config

# Use a custom config file path
confetti --config ~/my-confetti.json
```

The config file is JSON with all fields optional:

```json
{
  "birthRate": 60,
  "emissionStyle": "curtain",
  "gravity": -900,
  "lifetime": 5.0,
  "scale": 1.0,
  "spin": 16.0,
  "velocity": 2000
}
```

**Priority:** defaults < config file < preset < CLI flags

### Swift library

```swift
import ConfettiKit

// Simple usage
let controller = ConfettiController()
controller.fire()

// Custom configuration
let config = ConfettiConfig(
    birthRate: 40,
    velocity: 1300,
    colors: [.systemRed, .systemBlue, .systemGreen],
    shapes: [.rectangle, .circle]
)

let controller = ConfettiController(
    config: config,
    emissionDuration: 0.2,
    intensity: 0.8
)
controller.fire(on: [NSScreen.main!])

// Cleanup when done
controller.cleanup()
```

### Configuration options

```swift
ConfettiConfig(
    birthRate: 40,        // Particles per second per cell
    lifetime: 4.5,        // Particle lifetime in seconds
    velocity: 1500,       // Initial velocity
    velocityRange: 450,   // Velocity variation
    emissionRange: .pi * 0.4,  // Spread angle (~72°)
    gravity: -750,        // Y acceleration (negative = down)
    spin: 12.0,           // Rotation speed
    spinRange: 20.0,      // Rotation variation
    scale: 0.8,           // Particle size
    scaleRange: 0.2,      // Size variation
    scaleSpeed: -0.1,      // Scale change over time
    alphaSpeed: -0.15,    // Fade out speed
    colors: [...],        // Array of NSColor
    shapes: [...],        // Array of ConfettiShape
    emissionStyle: .cannons // .cannons (corners) or .curtain (top edge)
)
```

## Use cases

### AI coding agent hook

Fire confetti every time Claude Code (or any AI agent) finishes a task. See [Claude Code integration](#claude-code-integration) below.

### Shell function

Wrap the binary so it always runs in the background. Add to `.zshrc`:

```bash
confetti() { (~/.local/bin/confetti "$@" &) 2>/dev/null }
```

Now `confetti`, `confetti -p snow`, etc. all return instantly.

### Shell aliases

Add to your `.zshrc` or `.bashrc`:

```bash
alias gpush='git push && confetti'
alias cbuild='swift build && confetti'
alias ctest='swift test && confetti'
alias deploy='./deploy.sh && confetti -d 5'
```

### Long command notification

Fire confetti when a long-running terminal command finishes. Add to `.zshrc`:

```bash
# Notify with confetti after commands that take longer than 30 seconds
autoload -Uz add-zsh-hook

__confetti_preexec() { __cmd_start=$EPOCHSECONDS }
__confetti_precmd() {
  if [[ -n $__cmd_start ]] && (( EPOCHSECONDS - __cmd_start >= 30 )); then
    (~/.local/bin/confetti &) 2>/dev/null
  fi
  unset __cmd_start
}

add-zsh-hook preexec __confetti_preexec
add-zsh-hook precmd __confetti_precmd
```

### Keyboard shortcut (Raycast/Alfred)

Create a Raycast script or Alfred workflow:

```bash
#!/bin/bash
~/.local/bin/confetti
```

### Swift library

Use confetti in your own macOS app:

```swift
import ConfettiKit

func taskCompleted() {
    let controller = ConfettiController()
    controller.fire()

    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
        controller.cleanup()
    }
}
```

## Claude Code integration

### Hooks

Use different presets for different events. Add to `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "(~/.local/bin/confetti &) 2>/dev/null"
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "(~/.local/bin/confetti -p snow &) 2>/dev/null"
          }
        ]
      }
    ]
  }
}
```

`Stop` fires the default cannons when Claude finishes a task. `PermissionRequest` fires gentle snow when Claude needs your input.

### Skill

Create a skill at `~/.claude/skills/confetti.md`:

```markdown
---
name: confetti
description: Fire celebratory confetti animation
triggers:
  - celebrate
  - confetti
  - party
---

# Confetti Skill

Fire confetti to celebrate!

## Usage

When the user says "celebrate", "confetti", or "party", run:

\`\`\`bash
~/.local/bin/confetti
\`\`\`
```

### Scripts

```bash
#!/bin/bash
# celebrate.sh - A script to run after successful operations

if [ $? -eq 0 ]; then
    ~/.local/bin/confetti -d 2 &
fi
```

## Automation

### Apple shortcuts

Create a Shortcut with the "Run Shell Script" action:

```bash
~/.local/bin/confetti
```

Use any CLI flags in the script — presets, physics overrides, duration:

```bash
~/.local/bin/confetti -p intense -d 3
```

### AppleScript

```applescript
do shell script "~/.local/bin/confetti &"
```

With a preset:

```applescript
do shell script "~/.local/bin/confetti -p snow &"
```

### Automator

Add a "Run Shell Script" action to any workflow:

```bash
~/.local/bin/confetti
```

## AI agent instructions

> For AI coding agents (Claude Code, Gemini CLI, Copilot, etc.). Install confetti and set it up for the user.

### Install

```bash
# Option 1: Homebrew (preferred)
brew install gradigit/tap/confetti

# Option 2: Direct download
curl -sL https://github.com/gradigit/confetti/releases/latest/download/confetti-1.0.0.tar.gz | tar xz
mkdir -p ~/.local/bin && mv confetti ~/.local/bin/
```

### Verify

```bash
confetti --version
# Expected: confetti 1.0.0
```

### Set up Claude Code hooks

Add hooks to `~/.claude/settings.json`. Cannons on task completion, snow when waiting for input:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "(~/.local/bin/confetti &) 2>/dev/null"
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "(~/.local/bin/confetti -p snow &) 2>/dev/null"
          }
        ]
      }
    ]
  }
}
```

### Test

Run `confetti` to verify the animation appears on screen. It exits automatically after the particles fade.

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    ConfettiController                    │
│  - Manages windows and emitters across screens          │
│  - Coordinates emission timing                          │
└─────────────────────────┬───────────────────────────────┘
                          │
          ┌───────────────┴───────────────┐
          │                               │
┌─────────▼─────────┐         ┌──────────▼──────────┐
│  ConfettiWindow   │         │  ConfettiEmitter    │
│  - Transparent    │         │  - Creates layers   │
│  - Click-through  │         │  - Caches textures  │
│  - Multi-monitor  │         │  - Configures cells │
└───────────────────┘         └─────────────────────┘
                                        │
                              ┌─────────▼─────────┐
                              │   CAEmitterLayer   │
                              │   CAEmitterCell    │
                              │  (Core Animation)  │
                              └───────────────────┘
```

## Performance

Rendering is handled entirely by Core Animation on the GPU. The CPU side is just setup.

- Particle textures are created once at startup (1,048 bytes total)
- Emitter layers use `drawsAsynchronously` and `renderMode = .oldestFirst`

### Benchmark results

Run `swift build -c release --product benchmark && .build/release/benchmark` to reproduce.

MacBook Air 13" with Apple M4 (10 cores, 24 GB):

| Operation | Median | p95 | Min | Stddev |
|---|---|---|---|---|
| Full fire cycle (1 screen) | 23.28 ms | 28.96 ms | 20.24 ms | 2.58 ms |
| Emitter creation (9 cells) | 13.09 us | 16.03 us | 12.47 us | 1.23 us |
| Emitter creation (4 cells) | 6.32 us | 7.66 us | 6.14 us | 360.9 ns |
| Controller init | 38.2 ns | 40.7 ns | 37.9 ns | 0.7 ns |
| Config creation | 37.7 ns | 38.9 ns | 36.6 ns | 0.5 ns |
| Particle count estimate | 8.5 ns | 9.2 ns | 8.1 ns | 0.4 ns |
| Cell count | 7.0 ns | 7.3 ns | 6.9 ns | 0.1 ns |

### Visual benchmark (5 runs)

| Metric | Value |
|---|---|
| fire() latency (median) | 2.56 ms |
| fire() latency (cold start) | 83.27 ms |
| Average FPS | 60.0 +/- 0.1 |
| 1% low FPS | 60.0 |
| Min FPS (worst run) | 30.0 |
| Dropped frames | 1 / 944 (0.1%) |

The first fire() call takes ~83 ms because it creates transparent windows and flushes the initial `CATransaction`. After that, ~2.5 ms. One dropped frame out of 944, during window creation on the first run. Runs 2-5 had zero drops at 60 FPS.

### Preset overview

| Preset | Cells | Emitters | Particles | Lifetime | Style |
|---|---|---|---|---|---|
| default | 24 | 2 | 288 | 4.5s | cannons |
| subtle | 24 | 2 | 108 | 3.5s | cannons |
| intense | 24 | 2 | 576 | 5.0s | cannons |
| snow | 2 | 1 | 1 | 7.0s | curtain |
| fireworks | 24 | 2 | 720 | 3.0s | cannons |

*Particles = birthRate x cells x emitters x 0.15s emission duration.*

### Texture memory

| Shape | Size | Bytes |
|---|---|---|
| rectangle | 14x7 | 392 |
| triangle | 10x10 | 400 |
| circle | 8x8 | 256 |
| **Total** | | **1,048** |

*Textures are created once and reused across all emitters.*

### Runtime

- ~288 particles per burst (default preset)
- ~12 MB peak memory
- Under 10% CPU during animation
- 60 FPS with under 0.2% dropped frames

## Development

### Build

```bash
swift build              # Debug build
swift build -c release   # Release build
```

### Test

```bash
swift test               # Run all tests (requires Xcode)
```

### Project structure

```
confetti/
├── Package.swift
├── Sources/
│   ├── ConfettiKit/      # Reusable library
│   │   ├── ConfettiConfig.swift
│   │   ├── ConfettiEmitter.swift
│   │   ├── ConfettiWindow.swift
│   │   └── ConfettiController.swift
│   ├── confetti/         # CLI executable
│   │   ├── main.swift
│   │   └── ConfigFile.swift
│   └── benchmark/        # Performance benchmarks
│       └── main.swift
└── Tests/
    └── ConfettiKitTests/
        ├── ConfettiConfigTests.swift
        ├── ConfettiEmitterTests.swift
        ├── ConfettiControllerTests.swift
        └── PerformanceTests.swift
```

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

- Inspired by [Raycast's confetti](https://raycast.com)
- Built with Core Animation's `CAEmitterLayer`
- [NSHipster's CAEmitterLayer writeup](https://nshipster.com/caemitterlayer/) was a useful reference
