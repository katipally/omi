import AppKit

/// Soft start / end earcons for a push-to-talk turn. Centralizes the start cue
/// that was inlined in each start path and adds the symmetric end cue, so the
/// pair can never drift apart. Both are gated by the same `pttSoundsEnabled`
/// setting the start cue always used.
@MainActor
enum PTTCue {
  /// Turn started (hold or locked).
  static func start() {
    play("Funk", volume: 0.3)
  }

  /// Turn finished with a delivered answer. Deliberately not played on cancel,
  /// barge-in, or error — a cue there would read as "done" when nothing landed.
  static func end() {
    play("Pop", volume: 0.22)
  }

  private static func play(_ name: String, volume: Float) {
    guard ShortcutSettings.shared.pttSoundsEnabled else { return }
    let sound = NSSound(named: name)
    sound?.volume = volume
    sound?.play()
  }
}
