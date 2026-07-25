import AppKit

/// Soft start / end earcons for a push-to-talk turn. Centralizes the start
/// sound that was inlined in each start path and adds the symmetric end cue, so
/// a turn is audibly bracketed rather than only announcing itself. Gated by the
/// same `pttSoundsEnabled` setting the start cue always used.
@MainActor
enum PTTCue {
  /// Overridable in tests so a cue can be observed without playing audio.
  static var playHandler: ((String, Float) -> Void)?

  /// Turn started (hold or locked).
  static func start() {
    play("Funk", volume: 0.3)
  }

  /// Turn finished with a delivered answer.
  static func end() {
    play("Pop", volume: 0.22)
  }

  private static func play(_ name: String, volume: Float) {
    guard ShortcutSettings.shared.pttSoundsEnabled else { return }
    if let playHandler {
      playHandler(name, volume)
      return
    }
    let sound = NSSound(named: name)
    sound?.volume = volume
    sound?.play()
  }
}
