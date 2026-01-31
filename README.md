# Confetti 🎉

A lightweight, high-performance confetti animation for macOS. Fire colorful confetti from the corners of your screen, or gentle snow from the top edge, to celebrate achievements, completed tasks, or any special moment.

![macOS](https://img.shields.io/badge/macOS-12.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

- 🚀 **Fast** - Hardware-accelerated Core Animation with optimized rendering
- 🖥️ **Multi-monitor** - Works across all connected displays
- 🎨 **Customizable** - Configurable colors, shapes, physics, and more
- 📦 **Library + CLI** - Use as a Swift package or standalone command
- 🪶 **Lightweight** - No dependencies, minimal footprint

## Installation

### Homebrew

```bash
brew install gradigit/tap/confetti
```

### Build from source

```bash
git clone https://github.com/gradigit/confetti.git
cd confetti
swift build -c release
cp .build/release/confetti /usr/local/bin/
```

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/gradigit/confetti.git", from: "1.0.0")
]
```

## Usage

### Command Line

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

### Physics Flags

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

### Config File

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

### Swift Library

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

### Configuration Options

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

## Use Cases

### 1. Celebrate Task Completion

Add confetti to your productivity app when users complete tasks:

```swift
func taskCompleted() {
    let controller = ConfettiController()
    controller.fire()

    // Auto-cleanup after animation
    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
        controller.cleanup()
    }
}
```

### 2. Achievement Unlocked

Fire confetti when users unlock achievements:

```swift
func achievementUnlocked(_ achievement: Achievement) {
    // More intense confetti for bigger achievements
    let intensity: Float = achievement.isRare ? 1.0 : 0.6

    let controller = ConfettiController(intensity: intensity)
    controller.fire()
}
```

### 3. Build Success Notification

Celebrate successful builds in your development workflow:

```bash
# In your build script
swift build && confetti
```

### 4. Shell Aliases

Add to your `.zshrc` or `.bashrc`:

```bash
# Celebrate git push
alias gpush='git push && confetti'

# Celebrate successful tests
alias test='swift test && confetti'

# Celebrate deployment
alias deploy='./deploy.sh && confetti -d 5'
```

### 5. Keyboard Shortcut (Raycast/Alfred)

Create a Raycast script or Alfred workflow:

```bash
#!/bin/bash
~/.local/bin/confetti
```

## Claude Code Integration

### Using as a Hook

Add confetti to celebrate completed tasks in Claude Code. Create or edit `~/.claude/settings.json`:

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
    ]
  }
}
```

### Using as a Skill

Create a Claude Code skill at `~/.claude/skills/confetti.md`:

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

### Programmatic Usage in Scripts

```bash
#!/bin/bash
# celebrate.sh - A script to run after successful operations

if [ $? -eq 0 ]; then
    ~/.local/bin/confetti -d 2 &
fi
```

## Automation

### Apple Shortcuts

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

Confetti is optimized for smooth 60fps animation:

- **Texture caching** - Particle images created once at startup (1,048 bytes total)
- **Async rendering** - `drawsAsynchronously = true`
- **Optimal batching** - `renderMode = .oldestFirst`
- **Minimal allocations** - Reuses configurations

### Benchmark Results

Run `swift build -c release --product benchmark && .build/release/benchmark` to reproduce.

Results on Apple M1 Pro (10 cores, 24 GB):

| Operation | Median | p95 | Min | Stddev |
|---|---|---|---|---|
| Full fire cycle (1 screen) | 23.28 ms | 28.96 ms | 20.24 ms | 2.58 ms |
| Emitter creation (9 cells) | 13.09 us | 16.03 us | 12.47 us | 1.23 us |
| Emitter creation (4 cells) | 6.32 us | 7.66 us | 6.14 us | 360.9 ns |
| Controller init | 38.2 ns | 40.7 ns | 37.9 ns | 0.7 ns |
| Config creation | 37.7 ns | 38.9 ns | 36.6 ns | 0.5 ns |
| Particle count estimate | 8.5 ns | 9.2 ns | 8.1 ns | 0.4 ns |
| Cell count | 7.0 ns | 7.3 ns | 6.9 ns | 0.1 ns |

### Visual Benchmark (5 runs)

| Metric | Value |
|---|---|
| fire() latency (median) | 2.56 ms |
| fire() latency (cold start) | 83.27 ms |
| Average FPS | 60.0 +/- 0.1 |
| 1% low FPS | 60.0 |
| Min FPS (worst run) | 30.0 |
| Dropped frames | 1 / 944 (0.1%) |

The cold-start fire() creates transparent windows and flushes the first `CATransaction`. Subsequent calls are ~2.5 ms. The single dropped frame occurs on the first run during window creation; runs 2-5 hold a perfect 60 FPS with zero drops.

### Preset Overview

| Preset | Cells | Emitters | Particles | Lifetime | Style |
|---|---|---|---|---|---|
| default | 24 | 2 | 288 | 4.5s | cannons |
| subtle | 24 | 2 | 108 | 3.5s | cannons |
| intense | 24 | 2 | 576 | 5.0s | cannons |
| snow | 2 | 1 | 1 | 7.0s | curtain |
| fireworks | 24 | 2 | 720 | 3.0s | cannons |

*Particles = birthRate x cells x emitters x 0.15s emission duration.*

### Texture Memory

| Shape | Size | Bytes |
|---|---|---|
| rectangle | 14x7 | 392 |
| triangle | 10x10 | 400 |
| circle | 8x8 | 256 |
| **Total** | | **1,048** |

*Textures are created once and reused across all emitters.*

### Runtime

- ~288 particles per burst (default preset)
- ~12MB peak memory
- <10% CPU during animation
- Solid 60 FPS with <0.2% dropped frames

## Development

### Building

```bash
swift build              # Debug build
swift build -c release   # Release build
```

### Testing

```bash
swift test               # Run all tests (requires Xcode)
```

### Project Structure

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

Contributions are welcome! Please feel free to submit a Pull Request.

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
- Thanks to [NSHipster](https://nshipster.com/caemitterlayer/) for CAEmitterLayer documentation
