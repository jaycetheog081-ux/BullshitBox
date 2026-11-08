import Foundation

/// Safe starting point for documenting MobileGestalt research.
/// This intentionally does not call private APIs or modify system preferences.
enum MobileGestaltInspector {
    static let state = "Inspection backend not connected"

    static let notes = [
        "A sandbox extension is path-scoped; it is not root access.",
        "Reading a target does not prove that writes are permitted.",
        "Capability spoofing does not add unsupported hardware features.",
        "Keep experiments backed up and reversible."
    ]
}
