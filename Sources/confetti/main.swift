import AppKit
import ConfettiKit

// MARK: - CLI Configuration

struct CLIConfig {
    var duration: Double?  // nil = auto (wait for particles to finish)
    var intensity: Float = 1.0
    var screenIndex: Int?
    var preset: String?
    var configPath: String?
    var saveConfig = false

    // Physics overrides (nil = use base config value)
    var birthRate: Float?
    var lifetime: Float?
    var velocity: Double?
    var gravity: Double?
    var spin: Double?
    var scale: Double?

    static func parse(_ args: [String]) -> CLIConfig {
        var config = CLIConfig()
        var i = 1
        while i < args.count {
            switch args[i] {
            case "-d", "--duration":
                if i + 1 < args.count, let d = Double(args[i + 1]), d > 0 {
                    config.duration = d
                    i += 1
                } else {
                    fputs("Error: --duration requires a positive number\n", stderr)
                    exit(1)
                }
            case "-i", "--intensity":
                if i + 1 < args.count, let val = Float(args[i + 1]), val >= 0, val <= 1 {
                    config.intensity = val
                    i += 1
                } else {
                    fputs("Error: --intensity requires a number between 0.0 and 1.0\n", stderr)
                    exit(1)
                }
            case "-s", "--screen":
                if i + 1 < args.count, let s = Int(args[i + 1]), s >= 0 {
                    config.screenIndex = s
                    i += 1
                } else {
                    fputs("Error: --screen requires a non-negative integer\n", stderr)
                    exit(1)
                }
            case "-p", "--preset":
                if i + 1 < args.count {
                    let name = args[i + 1]
                    guard ConfettiConfig.preset(named: name) != nil else {
                        fputs("Error: unknown preset '\(name)'. Available: \(ConfettiConfig.presetNames.joined(separator: ", "))\n", stderr)
                        exit(1)
                    }
                    config.preset = name
                    i += 1
                } else {
                    fputs("Error: --preset requires a name (\(ConfettiConfig.presetNames.joined(separator: ", ")))\n", stderr)
                    exit(1)
                }
            case "--birth-rate":
                if i + 1 < args.count, let val = Float(args[i + 1]), val > 0 {
                    config.birthRate = val
                    i += 1
                } else {
                    fputs("Error: --birth-rate requires a positive number\n", stderr)
                    exit(1)
                }
            case "--velocity":
                if i + 1 < args.count, let val = Double(args[i + 1]) {
                    config.velocity = val
                    i += 1
                } else {
                    fputs("Error: --velocity requires a number\n", stderr)
                    exit(1)
                }
            case "--gravity":
                if i + 1 < args.count, let val = Double(args[i + 1]) {
                    config.gravity = val
                    i += 1
                } else {
                    fputs("Error: --gravity requires a number (negative = down)\n", stderr)
                    exit(1)
                }
            case "--spin":
                if i + 1 < args.count, let val = Double(args[i + 1]) {
                    config.spin = val
                    i += 1
                } else {
                    fputs("Error: --spin requires a number\n", stderr)
                    exit(1)
                }
            case "--scale":
                if i + 1 < args.count, let val = Double(args[i + 1]), val > 0 {
                    config.scale = val
                    i += 1
                } else {
                    fputs("Error: --scale requires a positive number\n", stderr)
                    exit(1)
                }
            case "--lifetime":
                if i + 1 < args.count, let val = Float(args[i + 1]), val > 0 {
                    config.lifetime = val
                    i += 1
                } else {
                    fputs("Error: --lifetime requires a positive number\n", stderr)
                    exit(1)
                }
            case "--config":
                if i + 1 < args.count {
                    config.configPath = args[i + 1]
                    i += 1
                } else {
                    fputs("Error: --config requires a file path\n", stderr)
                    exit(1)
                }
            case "--save-config":
                config.saveConfig = true
            case "--presets":
                print("Available presets:")
                for name in ConfettiConfig.presetNames {
                    let c = ConfettiConfig.preset(named: name)!
                    print("  \(name.padding(toLength: 12, withPad: " ", startingAt: 0)) birth-rate=\(c.birthRate) velocity=\(c.velocity) gravity=\(c.gravity) spin=\(c.spin) scale=\(c.scale)")
                }
                exit(0)
            case "-h", "--help":
                printHelp()
                exit(0)
            case "-v", "--version":
                print("confetti 1.0.0")
                exit(0)
            default:
                fputs("Unknown option: \(args[i])\n", stderr)
                printHelp()
                exit(1)
            }
            i += 1
        }
        return config
    }

    static func printHelp() {
        print("""
        confetti - Multi-monitor confetti cannon

        Usage: confetti [options]

        Options:
          -d, --duration <seconds>   Duration before exit (default: auto)
          -i, --intensity <0.0-1.0>  Particle intensity (default: 1.0)
          -s, --screen <index>       Screen index (default: all screens)
          -p, --preset <name>        Use a preset configuration
          -v, --version              Show version
          -h, --help                 Show this help

        Physics:
          --birth-rate <float>       Particles per second per cell (default: 40)
          --velocity <float>         Initial velocity (default: 1500)
          --gravity <float>          Y acceleration, negative = down (default: -750)
          --spin <float>             Rotation speed (default: 12.0)
          --scale <float>            Particle size (default: 0.8)
          --lifetime <float>         Particle lifetime in seconds (default: 4.5)

        Configuration:
          --config <path>            Config file path (default: ~/.config/confetti/config.json)
          --save-config              Save current settings to config file
          --presets                   List available presets

        Presets: \(ConfettiConfig.presetNames.joined(separator: ", "))

        Priority: defaults < config file < preset < CLI flags

        Examples:
          confetti                        Fire confetti on all screens
          confetti -p intense             Use intense preset
          confetti --velocity 2000        Custom velocity
          confetti -p subtle --spin 20    Preset with override
          confetti --save-config          Save defaults to config file
        """)
    }
}

// MARK: - Config Resolution

/// Resolves the final ConfettiConfig from defaults, config file, preset, and CLI flags
func resolveConfig(cli: CLIConfig) -> ConfettiConfig {
    // 1. Start with defaults
    var config = ConfettiConfig.default

    // 2. Apply config file (if exists)
    let configPath = cli.configPath ?? ConfigFile.defaultPath
    if let fileData = ConfigFile.load(from: configPath) {
        // If config file specifies a preset, use it as the base
        if let presetName = fileData.preset, let preset = ConfettiConfig.preset(named: presetName) {
            config = preset
        }
        config = ConfigFile.apply(fileData, over: config)
    }

    // 3. Apply preset (overrides config file)
    if let presetName = cli.preset, let preset = ConfettiConfig.preset(named: presetName) {
        config = preset
    }

    // 4. Apply individual CLI flags (override everything)
    let hasCLIOverrides = cli.birthRate != nil || cli.lifetime != nil || cli.velocity != nil
        || cli.gravity != nil || cli.spin != nil || cli.scale != nil

    if hasCLIOverrides {
        config = ConfettiConfig(
            birthRate: cli.birthRate ?? config.birthRate,
            lifetime: cli.lifetime ?? config.lifetime,
            velocity: cli.velocity.map { CGFloat($0) } ?? config.velocity,
            velocityRange: config.velocityRange,
            emissionRange: config.emissionRange,
            gravity: cli.gravity.map { CGFloat($0) } ?? config.gravity,
            spin: cli.spin.map { CGFloat($0) } ?? config.spin,
            spinRange: config.spinRange,
            scale: cli.scale.map { CGFloat($0) } ?? config.scale,
            scaleRange: config.scaleRange,
            scaleSpeed: config.scaleSpeed,
            alphaSpeed: config.alphaSpeed,
            colors: config.colors,
            shapes: config.shapes
        )
    }

    return config
}

// MARK: - App Delegate

class AppDelegate: NSObject, NSApplicationDelegate {
    var controller: ConfettiController?
    var cliConfig = CLIConfig()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        cliConfig = CLIConfig.parse(CommandLine.arguments)

        let config = resolveConfig(cli: cliConfig)

        // Handle --save-config
        if cliConfig.saveConfig {
            let path = cliConfig.configPath ?? ConfigFile.defaultPath
            ConfigFile.save(config, to: path)
            NSApp.terminate(nil)
            return
        }

        guard !NSScreen.screens.isEmpty else {
            fputs("Error: no screens available\n", stderr)
            NSApp.terminate(nil)
            return
        }

        let screens: [NSScreen]
        if let index = cliConfig.screenIndex {
            guard index < NSScreen.screens.count else {
                fputs("Error: screen index \(index) out of range (0-\(NSScreen.screens.count - 1))\n", stderr)
                NSApp.terminate(nil)
                return
            }
            screens = [NSScreen.screens[index]]
        } else {
            screens = NSScreen.screens
        }

        guard !screens.isEmpty else {
            NSApp.terminate(nil)
            return
        }

        let emissionDuration = 0.15

        controller = ConfettiController(
            config: config,
            angles: .default,
            emissionDuration: emissionDuration,
            intensity: cliConfig.intensity
        )
        controller?.fire(on: screens)

        // Exit after specified duration, or wait for all particles to finish
        let autoDuration = emissionDuration + Double(config.lifetime)
        let exitDuration = cliConfig.duration ?? autoDuration
        DispatchQueue.main.asyncAfter(deadline: .now() + exitDuration) { [weak self] in
            self?.controller?.cleanup()
            NSApp.terminate(nil)
        }
    }
}

// MARK: - Main

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
