import Foundation
import ConfettiKit

// MARK: - Config File Data

/// JSON-serializable representation of confetti configuration.
/// All fields are optional — missing fields inherit from the base config.
struct ConfigFileData: Codable {
    var birthRate: Float?
    var lifetime: Float?
    var velocity: Double?
    var velocityRange: Double?
    var emissionRange: Double?
    var gravity: Double?
    var spin: Double?
    var spinRange: Double?
    var scale: Double?
    var scaleRange: Double?
    var scaleSpeed: Double?
    var alphaSpeed: Float?
    var emissionStyle: String?
    var preset: String?
}

// MARK: - Config File Operations

enum ConfigFile {

    static let defaultPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.config/confetti/config.json"
    }()

    /// Loads config data from a JSON file, returns nil if file doesn't exist or is invalid
    static func load(from path: String = defaultPath) -> ConfigFileData? {
        guard FileManager.default.fileExists(atPath: path),
              let data = FileManager.default.contents(atPath: path) else {
            return nil
        }

        do {
            return try JSONDecoder().decode(ConfigFileData.self, from: data)
        } catch {
            fputs("Warning: invalid config file at \(path): \(error.localizedDescription)\n", stderr)
            return nil
        }
    }

    /// Saves a ConfettiConfig to a JSON file
    static func save(_ config: ConfettiConfig, to path: String = defaultPath) {
        let styleString: String?
        switch config.emissionStyle {
        case .cannons: styleString = nil  // omit default
        case .curtain: styleString = "curtain"
        }

        let data = ConfigFileData(
            birthRate: config.birthRate,
            lifetime: config.lifetime,
            velocity: Double(config.velocity),
            velocityRange: Double(config.velocityRange),
            emissionRange: Double(config.emissionRange),
            gravity: Double(config.gravity),
            spin: Double(config.spin),
            spinRange: Double(config.spinRange),
            scale: Double(config.scale),
            scaleRange: Double(config.scaleRange),
            scaleSpeed: Double(config.scaleSpeed),
            alphaSpeed: config.alphaSpeed,
            emissionStyle: styleString
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        do {
            let json = try encoder.encode(data)

            // Create directory if needed
            let dir = (path as NSString).deletingLastPathComponent
            try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)

            try json.write(to: URL(fileURLWithPath: path))
            print("Config saved to \(path)")
        } catch {
            fputs("Error: could not save config to \(path): \(error.localizedDescription)\n", stderr)
        }
    }

    /// Applies partial config file data over a base ConfettiConfig
    static func apply(_ fileData: ConfigFileData, over base: ConfettiConfig) -> ConfettiConfig {
        let style: EmissionStyle
        switch fileData.emissionStyle?.lowercased() {
        case "curtain": style = .curtain
        case "cannons": style = .cannons
        default: style = base.emissionStyle
        }

        return ConfettiConfig(
            birthRate: fileData.birthRate ?? base.birthRate,
            lifetime: fileData.lifetime ?? base.lifetime,
            velocity: fileData.velocity.map { CGFloat($0) } ?? base.velocity,
            velocityRange: fileData.velocityRange.map { CGFloat($0) } ?? base.velocityRange,
            emissionRange: fileData.emissionRange.map { CGFloat($0) } ?? base.emissionRange,
            gravity: fileData.gravity.map { CGFloat($0) } ?? base.gravity,
            spin: fileData.spin.map { CGFloat($0) } ?? base.spin,
            spinRange: fileData.spinRange.map { CGFloat($0) } ?? base.spinRange,
            scale: fileData.scale.map { CGFloat($0) } ?? base.scale,
            scaleRange: fileData.scaleRange.map { CGFloat($0) } ?? base.scaleRange,
            scaleSpeed: fileData.scaleSpeed.map { CGFloat($0) } ?? base.scaleSpeed,
            alphaSpeed: fileData.alphaSpeed ?? base.alphaSpeed,
            colors: base.colors,
            shapes: base.shapes,
            emissionStyle: style
        )
    }
}
