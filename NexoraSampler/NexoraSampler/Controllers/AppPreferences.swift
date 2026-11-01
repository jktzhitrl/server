import Foundation

/// Benutzereinstellungen (UserDefaults). In den Einstellungen per `@AppStorage` gebunden.
enum PrefKey {
    static let outputDeviceUID = "audio.outputDeviceUID"
    static let bufferSize = "audio.bufferSize"
    static let velocityFromPosition = "pads.velocityFromPosition"
    static let keyboardVelocity = "pads.keyboardVelocity"
    static let selectPadOnHit = "pads.selectOnHit"
    static let copyImportsToLibrary = "library.copyImports"
    static let previewVolume = "library.previewVolume"
    static let autoPreview = "library.autoPreview"
    static let lastProjectPath = "project.lastPath"
    static let midiEnabled = "midi.enabled"
}

enum AppPreferences {
    static func registerDefaults() {
        UserDefaults.standard.register(defaults: [
            PrefKey.bufferSize: 256,
            PrefKey.velocityFromPosition: true,
            PrefKey.keyboardVelocity: 0.85,
            PrefKey.selectPadOnHit: true,
            PrefKey.copyImportsToLibrary: true,
            PrefKey.previewVolume: 0.8,
            PrefKey.autoPreview: true,
            PrefKey.midiEnabled: true
        ])
    }

    static var bufferSize: UInt32 { UInt32(max(32, UserDefaults.standard.integer(forKey: PrefKey.bufferSize))) }
    static var velocityFromPosition: Bool { UserDefaults.standard.bool(forKey: PrefKey.velocityFromPosition) }
    static var keyboardVelocity: Float { Float(UserDefaults.standard.double(forKey: PrefKey.keyboardVelocity)) }
    static var selectPadOnHit: Bool { UserDefaults.standard.bool(forKey: PrefKey.selectPadOnHit) }
    static var copyImportsToLibrary: Bool { UserDefaults.standard.bool(forKey: PrefKey.copyImportsToLibrary) }
    static var previewVolume: Float { Float(UserDefaults.standard.double(forKey: PrefKey.previewVolume)) }
    static var autoPreview: Bool { UserDefaults.standard.bool(forKey: PrefKey.autoPreview) }
    static var midiEnabled: Bool { UserDefaults.standard.bool(forKey: PrefKey.midiEnabled) }
    static var outputDeviceUID: String? { UserDefaults.standard.string(forKey: PrefKey.outputDeviceUID) }
}
