# Confetti 🎉

Confetti cannon for macOS. Fires from the corners of every connected display at once, drops snow from the top edge, or buries your screen in an interactive blizzard where snow piles up and you sweep it away with your mouse. Run multiple AI sessions and the blizzard escalates, adding a new color of snow for each one.

Inspired by [Raycast's confetti](https://raycast.com), which only fires on one display, needs Raycast installed, and is closed source. This is standalone, multi-monitor, and MIT licensed.

![macOS](https://img.shields.io/badge/macOS-12.0%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9%2B-orange)
![License](https://img.shields.io/badge/License-MIT-green)

https://github.com/user-attachments/assets/ab8bb451-376f-4753-b5f8-29f6e2e51c18

**New in 1.2.0** -- the blizzard preset. Snow piles up, you sweep it away. Runs as a singleton when triggered by Claude Code hooks, so multiple sessions layer different colors of snow instead of fighting over the screen.

https://github.com/gradigit/confetti/raw/main/assets/BlizzardPreview.mp4

## Features

- Multi-monitor: fires on every connected display at once
- Blizzard mode: snow piles up at the bottom, you can sweep it away with your cursor
- GPU-rendered via Core Animation (blizzard uses SpriteKit for physics)
- Colors, shapes, and physics are all configurable
- Works as a Swift package or standalone CLI
- Zero dependencies

## Quick start with an AI agent

If you use Claude Code, Gemini CLI, Copilot, or any AI coding agent — just paste the repo link and ask it to set up confetti for you. It'll install the binary and walk you through choosing presets for task completion, permission requests, and other triggers.

> **[AI agent instructions](#ai-agent-instructions)** — the agent reads this section and runs a setup wizard.

## Installation

### Homebrew

```bash
brew install gradigit/tap/confetti
```

### Download

Grab the universal binary from [GitHub Releases](https://github.com/gradigit/confetti/releases/latest):

```bash
curl -sL https://github.com/gradigit/confetti/releases/latest/download/confetti-1.2.0.tar.gz | tar xz
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
    .package(url: "https://github.com/gradigit/confetti.git", from: "1.2.0")
]
```

## Usage

### Command line

```bash
# Fire confetti on all screens
confetti

# Use a preset
confetti -p intense

# Interactive blizzard — snow piles up, sweep it away with your mouse
confetti -p blizzard

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
| `--window-level` | Window level: `normal`, `floating`, `statusBar` | statusBar |
| `--stop-on-modify` | Watch a file; stop when it changes | - |
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
| `default` | Confetti cannons from both corners |
| `subtle` | Fewer particles, slower, understated |
| `intense` | More particles, faster, bigger |
| `snow` | Falling snow from the top edge |
| `blizzard` | Snow that piles up, sweep it away with your mouse |
| `fireworks` | Fast burst, heavy gravity |

```bash
# List presets with their values
confetti --presets
```

### Blizzard preset (experimental)

The other presets use Core Animation (`CAEmitterLayer`) for fire-and-forget GPU particles. Blizzard uses SpriteKit instead, which gives it per-particle physics, collision detection, and a scene graph. Heavier, but that's what makes the interactive stuff possible:

- Snow accumulates into a pile at the bottom of the screen using a height map
- You can sweep the pile away by moving your mouse cursor through it
- A repulsion field around the cursor pushes falling snowflakes aside
- Wind drift via a noise field gives organic movement
- The pile has a glow edge and gradient fill

Blizzard ends automatically when any column of the pile reaches 25% screen height, or when you sweep away enough snow (8% of max pile area). Both trigger a 2-second melt animation where the pile shrinks and fades. You can also set a hard timeout with `--duration`.

Physics flags (`--gravity`, `--velocity`, etc.) are ignored for blizzard — it uses its own tuned SpriteKit physics internally. A warning is printed if you pass them.

```bash
confetti -p blizzard        # Runs until pile fills or you sweep it away
confetti -p blizzard -d 20  # Hard timeout at 20 seconds, then melts
```

#### Multi-session escalation

Only one blizzard process runs at a time. If a second Claude Code session triggers a permission request while one is already snowing, it joins the existing blizzard instead of spawning another.

Each session gets its own snow layer with a different color and shape:

| Session | Color | Shape | Wind |
|---------|-------|-------|------|
| 1 | Ice blue | Circle | Vertical |
| 2 | Lavender | Hexagon | Left drift |
| 3 | Mint | Star | Right drift |
| 4 | Rose | Diamond | Gusty |

Colors cycle after 4. When you approve or deny a permission (the transcript file changes), that session's snow fades out. Last session gone = full melt, process exits.

Coordination uses a PID file at `/tmp/confetti-blizzard.pid` and `DistributedNotificationCenter`. SIGTERM triggers a graceful melt, not an instant kill.

```bash
# First launch claims ownership, starts blizzard
confetti -p blizzard --stop-on-modify /path/to/transcript.jsonl &

# Second launch detects running blizzard, posts escalation, exits immediately
confetti -p blizzard --stop-on-modify /path/to/other-transcript.jsonl
```

#### Window level

By default blizzard renders above all windows. You can change this:

```bash
confetti -p blizzard --window-level normal    # Behind active windows
confetti -p blizzard --window-level floating   # Above normal, below menus
confetti -p blizzard --window-level statusBar  # Above everything (default)
```

#### Experimental status

The core scenarios work (single session, multi-session escalation/de-escalation, SIGTERM, stale PID recovery, file watching). Still rough around the edges though.

TODOs:
- Multi-session demo video (the current promo video only shows single-session)
- Pastel colors are subtle on dark backgrounds — may need brightness tuning
- No automated visual tests (current tests check process lifecycle, not pixels)

#### Swift API

```swift
let config = ConfettiConfig.preset(named: "blizzard")!
let controller = ConfettiController(config: config)

// Called once all screens finish their melt animation
controller.onBlizzardComplete = {
    controller.cleanup()
}

controller.fire()

// Optionally stop early — triggers melt, then onBlizzardComplete
controller.stopSnowing()

// Multi-session: add/remove visual layers
controller.escalateBlizzard(sessionID: "session-1")
controller.deescalateBlizzard(sessionID: "session-1")
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

Priority: defaults < config file < preset < CLI flags

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

// Interactive blizzard with programmatic stop
let blizzardConfig = ConfettiConfig.preset(named: "blizzard")!
let blizzardController = ConfettiController(config: blizzardConfig)
blizzardController.onBlizzardComplete = {
    blizzardController.cleanup()
}
blizzardController.fire()

// Stop the blizzard early (triggers melt animation, then onBlizzardComplete)
blizzardController.stopSnowing()
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
    emissionStyle: .cannons // .cannons (corners), .curtain (top edge), or .blizzard (interactive snow)
)
```

## Use cases

### AI coding agent hook

Confetti every time Claude Code (or any AI agent) finishes a task. See [Claude Code integration](#claude-code-integration) below.

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

Confetti when a long-running terminal command finishes. Add to `.zshrc`:

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
            "command": "~/.claude/hooks/blizzard-hook.sh"
          }
        ]
      }
    ]
  }
}
```

`Stop` fires the default cannons when Claude finishes a task. `PermissionRequest` starts a blizzard while you review. Snow piles up; sweep it with your mouse.

#### Blizzard hook script

The hook above calls a wrapper script. It pulls the transcript path from the hook JSON and passes it to `--stop-on-modify`, so the blizzard melts on its own when you approve or deny.

Create `~/.claude/hooks/blizzard-hook.sh`:

```bash
#!/bin/bash
TRANSCRIPT_PATH=$(jq -r '.transcript_path // empty')
printf '\a'
afplay /System/Library/Sounds/Funk.aiff &
if [ -n "$TRANSCRIPT_PATH" ]; then
    ~/.local/bin/confetti -p blizzard --stop-on-modify "$TRANSCRIPT_PATH" &
else
    ~/.local/bin/confetti -p blizzard -d 30 &
fi
```

```bash
chmod +x ~/.claude/hooks/blizzard-hook.sh
```

If you have multiple Claude Code sessions running, each permission request adds a new colored snow layer to the same blizzard instead of spawning a second process. See [multi-session escalation](#multi-session-escalation).

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

Any CLI flags work in the script:

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

> For AI coding agents (Claude Code, Gemini CLI, Copilot, etc.). Install confetti, then walk the user through setup as a wizard.

### Step 1: Install

```bash
# Homebrew (preferred)
brew install gradigit/tap/confetti

# Or direct download
curl -sL https://github.com/gradigit/confetti/releases/latest/download/confetti-1.2.0.tar.gz | tar xz
mkdir -p ~/.local/bin && mv confetti ~/.local/bin/
```

Verify: `confetti --version` should print `confetti 1.2.0`.

### Step 2: Setup wizard

Ask the user these three questions to configure their setup. Apply answers to `~/.claude/settings.json` (Claude Code) or the equivalent hook system for other agents.

**Q1: "Which confetti effect do you want when I finish a task?"**

| Option | Description |
|--------|-------------|
| `default` (recommended) | Confetti cannons from both corners |
| `subtle` | Fewer particles, understated |
| `intense` | More particles, bigger burst |
| `fireworks` | Fast explosive burst with heavy gravity |
| `snow` | Gentle falling snow |
| `blizzard` | Interactive snow that piles up (heavier on GPU) |
| None | No effect |

Apply to the **Stop** hook.

**Q2: "Which effect do you want when I ask for your permission?"**

| Option | Description |
|--------|-------------|
| `snow` (recommended) | Gentle ambient snow while you review |
| `blizzard` | Snow piles up while you review, sweep it with your mouse. Recommended if you don't mind a slightly heavier effect. |
| `subtle` | Understated confetti |
| None | No effect |

Apply to the **PermissionRequest** hook.

**Q3: "Want confetti in any other situations?"**

Suggest these options and let the user pick any combination:

- **Long-running commands** (recommended) — confetti when a terminal command takes over 30 seconds. Add to `.zshrc`:

  ```bash
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

- **Git push** — add `alias gpush='git push && confetti'` to `.zshrc`
- **Builds** — add `alias cbuild='swift build && confetti'` to `.zshrc`

### Hook format (Claude Code)

Hook command format: `(~/.local/bin/confetti -p <preset> &) 2>/dev/null` (omit `-p` for default).

Hooks go in `~/.claude/settings.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [{ "type": "command", "command": "(~/.local/bin/confetti &) 2>/dev/null" }]
      }
    ],
    "PermissionRequest": [
      {
        "hooks": [{ "type": "command", "command": "(~/.local/bin/confetti -p snow &) 2>/dev/null" }]
      }
    ]
  }
}
```

Replace preset names based on the user's answers above. Available hook events: `Stop` (task finished), `PermissionRequest` (needs input), `SessionStart`, `PreCompact`, `SessionEnd`.

### Step 3: Test

Run `confetti` to verify installation. It exits on its own after the particles fade.

## Architecture

```
┌──────────────────────────────────────────────────────────────┐
│                    ConfettiController                         │
│  - Manages windows and emitters across screens               │
│  - Routes to CA or SpriteKit based on emission style         │
└────────────────┬─────────────────────┬───────────────────────┘
                 │                     │
    ┌────────────▼────────────┐  ┌─────▼───────────────────┐
    │  Confetti Path (CA)     │  │  Blizzard Path (SK)      │
    │                         │  │                          │
    │  ConfettiWindow         │  │  BlizzardWindow          │
    │  ConfettiEmitter        │  │  BlizzardScene           │
    │  CAEmitterLayer         │  │  BlizzardSessionLayer(s) │
    │                         │  │  HeightMap               │
    └─────────────────────────┘  │  SKView + physics        │
                                 └──────────┬───────────────┘
                                            │
                              ┌─────────────▼──────────────┐
                              │  BlizzardCoordinator (CLI)  │
                              │  - PID file singleton       │
                              │  - DNC escalation IPC       │
                              │  - TranscriptWatcher(s)     │
                              └─────────────────────────────┘
```

## Performance

Most presets use Core Animation: CPU does setup, GPU handles rendering. Blizzard is the exception since it needs SpriteKit for per-particle physics and pile interaction. Heavier, but still 60 FPS.

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

First fire() call takes ~83 ms (window creation + initial `CATransaction` flush). After that, ~2.5 ms. One dropped frame out of 944, during window creation on the first run. Runs 2-5 had zero drops at 60 FPS.

### Preset overview

| Preset | Cells | Emitters | Particles | Lifetime | Style |
|---|---|---|---|---|---|
| default | 24 | 2 | 288 | 4.5s | cannons |
| subtle | 24 | 2 | 108 | 3.5s | cannons |
| intense | 24 | 2 | 576 | 5.0s | cannons |
| snow | 2 | 1 | 1 | 7.0s | curtain |
| blizzard | - | - | ~8/sec | until done | blizzard (SpriteKit) |
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
│   │   ├── ConfettiController.swift
│   │   ├── BlizzardScene.swift
│   │   ├── BlizzardWindow.swift
│   │   ├── BlizzardSessionStyle.swift
│   │   └── HeightMap.swift
│   ├── confetti/         # CLI executable
│   │   ├── main.swift
│   │   ├── ConfigFile.swift
│   │   ├── BlizzardCoordinator.swift
│   │   └── TranscriptWatcher.swift
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
- Built with Core Animation's `CAEmitterLayer` and SpriteKit
- [NSHipster's CAEmitterLayer writeup](https://nshipster.com/caemitterlayer/) was a useful reference
