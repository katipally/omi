import XCTest

@testable import Omi_Computer

/// Which phase the notch orb shows across a voice turn. One orb morphs in
/// place, so picking the wrong phase is what makes it snap instead of morph.
final class NotchVoiceOrbModeTests: XCTestCase {
  func testIdleTurnLeavesTheLobeToTheAgentPills() {
    XCTAssertNil(NotchVoiceOrb.Mode.current(listening: false, speaking: false, thinking: false))
  }

  func testEachPhaseMapsToItsOwnMode() {
    XCTAssertEqual(
      NotchVoiceOrb.Mode.current(listening: true, speaking: false, thinking: false), .listening)
    XCTAssertEqual(
      NotchVoiceOrb.Mode.current(listening: false, speaking: true, thinking: false), .speaking)
    XCTAssertEqual(
      NotchVoiceOrb.Mode.current(listening: false, speaking: false, thinking: true), .thinking)
  }

  func testLiveMicInputOutranksPlaybackAndThinking() {
    // A new hold starting while the previous reply is still speaking must show
    // the user's own level, not the tail of Omi's voice.
    XCTAssertEqual(
      NotchVoiceOrb.Mode.current(listening: true, speaking: true, thinking: true), .listening)
  }

  func testPlaybackOutranksTheSilentThinkingStretch() {
    // Once audio is actually playing the bars must follow it, even while the
    // turn still reports as in-flight.
    XCTAssertEqual(
      NotchVoiceOrb.Mode.current(listening: false, speaking: true, thinking: true), .speaking)
  }
}
