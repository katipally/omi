import XCTest

@testable import Omi_Computer

/// The push-to-talk earcons that bracket a turn.
@MainActor
final class PTTCueTests: XCTestCase {
  private var played: [(name: String, volume: Float)] = []

  /// Records cues for the duration of `body`, restoring the user's setting.
  private func capturingCues(soundsEnabled: Bool, _ body: () -> Void) {
    let originalSoundsEnabled = ShortcutSettings.shared.pttSoundsEnabled
    defer {
      PTTCue.playHandler = nil
      ShortcutSettings.shared.pttSoundsEnabled = originalSoundsEnabled
    }
    played = []
    ShortcutSettings.shared.pttSoundsEnabled = soundsEnabled
    PTTCue.playHandler = { name, volume in self.played.append((name, volume)) }
    body()
  }

  func testStartAndEndUseDistinctCues() {
    capturingCues(soundsEnabled: true) {
      PTTCue.start()
      PTTCue.end()
    }

    XCTAssertEqual(played.count, 2)
    XCTAssertNotEqual(played[0].name, played[1].name)
    // The closing cue is quieter: it lands while the answer is being read.
    XCTAssertLessThan(played[1].volume, played[0].volume)
  }

  func testBothCuesRespectTheSoundsSetting() {
    // Regression guard: the end cue is new, so it must honour the same opt-out
    // the start cue always did rather than becoming an unmutable sound.
    capturingCues(soundsEnabled: false) {
      PTTCue.start()
      PTTCue.end()
    }

    XCTAssertTrue(played.isEmpty)
  }
}
