import XCTest

@testable import Omi_Computer

/// The Listening chip used to derive "on" from the transcription toggle alone.
/// In the shipped default ("Only during meetings") the capture gate stops the
/// microphone whenever no call is detected, so the chip rendered a solid green
/// "Listening" while no audio was being recorded, and its tooltip claimed
/// "In meeting", including while Listening was switched off entirely.
///
/// These cover the contract that replaced it: the chip's state is derived from
/// the same `isAwaitingMeeting` flag the gate sets when it stops the mic, and
/// every mode is reachable without a pointer.
final class CaptureListeningModeTests: XCTestCase {

  private let modes: [AssistantSettings.SystemAudioCaptureMode] = [.always, .onlyDuringMeetings, .never]

  // MARK: The chip cannot claim to be recording while capture is gated off

  func testChipReadsActiveOnlyWhenAudioIsActuallyFlowing() {
    for isTranscribing in [true, false] {
      for isAwaitingMeeting in [true, false] {
        for hasServiceError in [true, false] {
          let chip = CaptureListeningLogic.listeningChipState(
            isTranscribing: isTranscribing,
            isAwaitingMeeting: isAwaitingMeeting,
            hasServiceError: hasServiceError
          )
          let audioIsFlowing = isTranscribing && !isAwaitingMeeting && !hasServiceError

          XCTAssertEqual(
            chip == .capturing, audioIsFlowing,
            "chip \(chip) for transcribing=\(isTranscribing) awaiting=\(isAwaitingMeeting) error=\(hasServiceError)"
          )
          XCTAssertEqual(
            chip.statusState.isActive, audioIsFlowing,
            "the shared status enum paints .active green, so it must never be active while capture is gated off"
          )
        }
      }
    }
  }

  func testWaitingForAMeetingIsItsOwnStateNotOnAndNotOff() {
    let standby = CaptureListeningLogic.listeningChipState(
      isTranscribing: true, isAwaitingMeeting: true, hasServiceError: false)
    let capturing = CaptureListeningLogic.listeningChipState(
      isTranscribing: true, isAwaitingMeeting: false, hasServiceError: false)
    let off = CaptureListeningLogic.listeningChipState(
      isTranscribing: false, isAwaitingMeeting: false, hasServiceError: false)

    XCTAssertEqual(standby, .standby)
    XCTAssertFalse(standby.statusState.isActive)
    XCTAssertFalse(standby.statusState.isBlocked)

    // Distinct to look at, or the fourth state is invisible to the user.
    XCTAssertNotEqual(standby.systemImage, capturing.systemImage)
    XCTAssertNotEqual(standby.systemImage, off.systemImage)
    XCTAssertNotEqual(standby.statusText, capturing.statusText)
    XCTAssertNotEqual(standby.statusText, off.statusText)
  }

  func testServiceErrorOutranksTheToggle() {
    for isTranscribing in [true, false] {
      XCTAssertEqual(
        CaptureListeningLogic.listeningChipState(
          isTranscribing: isTranscribing, isAwaitingMeeting: false, hasServiceError: true),
        .blocked
      )
    }
  }

  // MARK: Titles

  func testTitleNeverClaimsInMeetingWhileListeningIsOff() {
    for mode in modes {
      for isAwaitingMeeting in [true, false] {
        let title = CaptureListeningLogic.listeningModeTitle(
          mode: mode, isTranscribing: false, isAwaitingMeeting: isAwaitingMeeting)

        XCTAssertNotEqual(title, "In meeting", "mode \(mode) claims a meeting while Listening is off")
        XCTAssertEqual(
          title, CaptureListeningLogic.listeningModeName(mode),
          "with nothing being captured the title can only name the mode")
      }
    }
  }

  func testTitleSeparatesWaitingForAMeetingFromBeingInOne() {
    XCTAssertEqual(
      CaptureListeningLogic.listeningModeTitle(
        mode: .onlyDuringMeetings, isTranscribing: true, isAwaitingMeeting: true),
      "Waiting for a meeting"
    )
    XCTAssertEqual(
      CaptureListeningLogic.listeningModeTitle(
        mode: .onlyDuringMeetings, isTranscribing: true, isAwaitingMeeting: false),
      "In meeting"
    )
    XCTAssertEqual(
      CaptureListeningLogic.listeningModeTitle(mode: .always, isTranscribing: true, isAwaitingMeeting: false),
      "Always"
    )
    XCTAssertEqual(
      CaptureListeningLogic.listeningModeTitle(mode: .never, isTranscribing: true, isAwaitingMeeting: false),
      "Mic only"
    )
  }

  func testBadgeNamesEveryModeExceptTheAlwaysOnOne() {
    // Always-on needs no badge; every other mode means the mic is conditional,
    // which has to be legible without hovering.
    XCTAssertNil(
      CaptureListeningLogic.listeningModeBadge(
        mode: .always, isTranscribing: true, isAwaitingMeeting: false))

    for isTranscribing in [true, false] {
      XCTAssertNotNil(
        CaptureListeningLogic.listeningModeBadge(
          mode: .onlyDuringMeetings, isTranscribing: isTranscribing, isAwaitingMeeting: true))
      XCTAssertNotNil(
        CaptureListeningLogic.listeningModeBadge(
          mode: .never, isTranscribing: isTranscribing, isAwaitingMeeting: false))
    }

    XCTAssertEqual(
      CaptureListeningLogic.listeningModeBadge(
        mode: .onlyDuringMeetings, isTranscribing: true, isAwaitingMeeting: false),
      "In meeting"
    )
    XCTAssertEqual(
      CaptureListeningLogic.listeningModeBadge(
        mode: .onlyDuringMeetings, isTranscribing: true, isAwaitingMeeting: true),
      "Meetings only",
      "a chip that says 'In meeting' while waiting for one is the bug this replaced"
    )
  }

  // MARK: Every mode is reachable

  func testPickerOffersAllThreeModesAndMarksExactlyTheCurrentOne() {
    for current in modes {
      let options = CaptureListeningLogic.listeningModeOptions(current: current)

      XCTAssertEqual(options.map(\.mode), modes, "the picker must offer every mode, in a stable order")
      XCTAssertEqual(options.filter(\.isCurrent).map(\.mode), [current])
      XCTAssertEqual(Set(options.map(\.title)).count, options.count, "each row needs a distinct label")
      XCTAssertFalse(options.contains { $0.detail.isEmpty }, "each row explains what the mode does to the mic")
    }
  }

  func testCyclingReachesEveryModeAndWraps() {
    var visited: [AssistantSettings.SystemAudioCaptureMode] = [.always]
    for _ in 1..<modes.count {
      visited.append(CaptureListeningLogic.nextListeningMode(after: visited[visited.count - 1]))
    }

    XCTAssertEqual(Set(visited), Set(modes), "the pointer-free path must reach all three modes, not two")
    XCTAssertEqual(
      CaptureListeningLogic.nextListeningMode(after: visited[visited.count - 1]), .always,
      "cycling wraps rather than dead-ending on the last mode")
  }
}
