import OmiTheme
import SwiftUI

/// Paces a streaming reply's reveal on its own clock, the way the notch's
/// `StreamingReplyText` does, instead of rendering each token batch the instant
/// it lands.
///
/// Deltas arrive in lumps: `ChatStreamingBuffer` flushes every 35ms, but a flush
/// carries however many characters happened to arrive, and one containing a
/// newline changes the wrapped height far more than one that does not. Rendering
/// those directly makes the transcript grow in uneven steps, and the follow
/// scroll can only ever be as smooth as the height it is chasing.
///
/// The reveal instead approaches the buffer exponentially: a steady floor so it
/// always moves, plus a term proportional to how far behind it is so a burst
/// drains quickly without a jump. It never snaps — when the stream ends the
/// backlog simply drains to zero, so the handover from streaming to final text
/// is continuous.
///
/// The rate is capped, and that cap is the whole difference between text that
/// appears and text that is written. Uncapped, the catch-up term alone reaches
/// thousands of characters a second on any real reply, so the pacing exists but
/// is never visible.
@MainActor
final class ChatRevealModel {
  /// Floor rate, in characters per second. Roughly unhurried reading speed:
  /// enough that a short answer does not feel withheld, slow enough that the
  /// words arrive one at a time.
  static let baseCharsPerSecond: Double = 100
  /// Seconds for the backlog to drain to roughly a third of itself.
  static let catchUpSeconds: Double = 1.2
  /// Ceiling while tokens are still arriving. Set near a model's own output
  /// rate: the reveal tracks the stream rather than racing ahead of it.
  static let streamingCharsPerSecond: Double = 250
  /// Ceiling once the stream has ended. A long reply may still have a backlog
  /// when the last token lands, and text crawling on after omi has visibly
  /// finished reads as a stall — so the tail is allowed to close faster while
  /// still gliding rather than snapping.
  static let drainCharsPerSecond: Double = 900
  /// The reveal's redraw ceiling. Markdown is re-parsed on every distinct
  /// string, so this bounds parse work; 30/s is well past what reads as smooth.
  /// Nonisolated because the transcript's follow pins on this same clock, and
  /// its timing constants are read outside the main actor.
  nonisolated static let minimumInterval: Double = 1.0 / 30.0

  private var revealed: Double = 0
  private var lastTime: CFTimeInterval?
  private var lastFullCount = 0
  /// Whether this model has ever been asked about a real reply, by rendering a
  /// frame or by being told the text was already whole.
  private var hasSeenText = false

  /// True once the reveal has caught up with everything buffered so far. The
  /// authority for stopping the clock: the step is rate-limited per frame, so a
  /// duration estimate would be wrong after any dropped frames.
  ///
  /// A model that has never seen text is never complete. Fresh, `revealed` and
  /// `lastFullCount` are both zero, so a bare `>=` reports a brand-new turn as
  /// already finished — the view then never starts its clock, and the whole
  /// paced reveal renders as raw text the instant each flush lands.
  var isComplete: Bool { hasSeenText && revealed >= Double(lastFullCount) }

  /// Marks everything already revealed, with no animation. Saved history and
  /// completed replies are whole when they first render; only a live turn is
  /// paced, and without this every message would replay on scroll-in.
  func finish(full: String) {
    lastFullCount = full.count
    revealed = Double(lastFullCount)
    lastTime = nil
    hasSeenText = true
  }

  func revealed(at date: Date, full: String, isStreaming: Bool = true) -> String {
    let count = full.count
    // A shorter buffer means a new turn started — restart the reveal.
    if count < lastFullCount {
      revealed = 0
      lastTime = nil
    }
    lastFullCount = count
    hasSeenText = true

    let now = date.timeIntervalSinceReferenceDate
    if let last = lastTime {
      let dt = min(0.1, max(0, now - last))
      let backlog = Double(count) - revealed
      let ceiling = isStreaming ? Self.streamingCharsPerSecond : Self.drainCharsPerSecond
      let rate = min(
        ceiling,
        Self.baseCharsPerSecond + max(0, backlog) / Self.catchUpSeconds
      )
      revealed = min(Double(count), revealed + rate * dt)
    } else if revealed == 0 {
      // First frame of a live turn: show the opening word rather than a blank
      // beat, so the reply starts the instant it has something to say.
      revealed = Double(Self.firstWordLength(of: full))
    }
    lastTime = now

    return Self.prefix(of: full, characters: Int(revealed))
  }

  /// The revealed prefix, cut at exactly the character the clock reached, so a
  /// word grows letter by letter instead of appearing whole. A fully caught-up
  /// reveal returns the text untouched.
  ///
  /// Two things are still held back, because both are markdown that renders as
  /// something else until it is complete: an inline marker with no closer yet,
  /// and a line showing only its list or heading marker.
  static func prefix(of full: String, characters shown: Int) -> String {
    guard shown < full.count else { return full }
    guard shown > 0 else { return "" }
    let end = full.index(full.startIndex, offsetBy: shown)
    return withoutDanglingMarker(withoutOpenInlineMarkup(String(full[..<end])))
  }

  /// Trims a trailing inline marker that has not closed yet. Revealed a
  /// character at a time, `**bold` would spend several frames drawn as literal
  /// asterisks before snapping to bold, and a half-written `[label](htt` as a
  /// bracketed fragment before snapping to a link.
  private static func withoutOpenInlineMarkup(_ text: String) -> String {
    let lineStart = text.lastIndex(of: "\n").map(text.index(after:)) ?? text.startIndex
    guard let cut = openMarkupIndex(in: text[lineStart...]) else { return text }
    return String(text[..<cut])
  }

  /// The earliest still-open inline marker on `line`, or nil when every marker
  /// on it is closed. Underscores are deliberately not tracked: `snake_case`
  /// identifiers would trip on them constantly, and a lone underscore renders
  /// as itself anyway.
  private static func openMarkupIndex(in line: Substring) -> String.Index? {
    var codeOpen: String.Index?
    var boldOpen: String.Index?
    var italicOpen: String.Index?
    var linkOpen: String.Index?
    var awaitingLinkTarget = false
    var sawNonSpace = false

    var index = line.startIndex
    while index < line.endIndex {
      let character = line[index]
      let next = line.index(after: index)
      defer { sawNonSpace = sawNonSpace || !character.isWhitespace }

      if character == "`" {
        codeOpen = codeOpen == nil ? index : nil
        index = next
        continue
      }
      // Inside inline code nothing else is markup.
      if codeOpen != nil {
        index = next
        continue
      }

      if character == "*" {
        if next < line.endIndex, line[next] == "*" {
          boldOpen = boldOpen == nil ? index : nil
          index = line.index(after: next)
          continue
        }
        // A bullet opens a list item, not emphasis.
        let isBullet = !sawNonSpace && (next == line.endIndex || line[next] == " ")
        if !isBullet {
          italicOpen = italicOpen == nil ? index : nil
        }
        index = next
        continue
      }

      switch character {
      case "[":
        linkOpen = linkOpen ?? index
        awaitingLinkTarget = false
      case "]" where linkOpen != nil:
        awaitingLinkTarget = next < line.endIndex && line[next] == "("
        if !awaitingLinkTarget { linkOpen = nil }
      case ")" where awaitingLinkTarget:
        linkOpen = nil
        awaitingLinkTarget = false
      default:
        break
      }
      index = next
    }

    return [codeOpen, boldOpen, italicOpen, linkOpen].compactMap { $0 }.min()
  }

  /// Holds back a line that has revealed its markdown marker but not yet a word.
  /// A word-boundary cut alone leaves a bare "-" or "##", which the renderer
  /// draws as an empty list item or heading for a frame — a flicker on every
  /// list in every reply, which is exactly the jitter the pacing exists to
  /// remove.
  private static func withoutDanglingMarker(_ text: String) -> String {
    guard let lineStart = text.lastIndex(of: "\n") else {
      return isMarkerOnly(text[...]) ? "" : text
    }
    guard isMarkerOnly(text[text.index(after: lineStart)...]) else { return text }
    return String(text[..<lineStart])
  }

  private static let markerCharacters = Set("-*#>+.0123456789 \t")

  private static func isMarkerOnly(_ line: Substring) -> Bool {
    !line.isEmpty && line.allSatisfy { markerCharacters.contains($0) }
  }

  private static func firstWordLength(of text: String) -> Int {
    text.firstIndex(where: { $0.isWhitespace })
      .map { text.distance(from: text.startIndex, to: $0) } ?? text.count
  }
}

/// Omi's reply text, revealed at a paced rate while it streams and rendered
/// directly once it is whole.
///
/// The newest characters sit under a short fade at the foot of the block, so a
/// line arrives by resolving out of the edge rather than by switching on. The
/// fade band is absolute, not proportional: a one-line answer would otherwise
/// be dimmed end to end.
struct StreamingMarkdownText: View {
  let text: String
  let isStreaming: Bool

  /// Height of the fade band, and the height below which there is no room for
  /// one. Roughly a line and a half of body text.
  private static let fadeBand: CGFloat = 22

  @State private var model = ChatRevealModel()
  @State private var isRevealing: Bool
  @State private var primed = false
  /// Animates the band open and shut so the last line is never left mid-fade
  /// once the reveal finishes.
  @State private var fadeAmount: CGFloat
  /// Keeps the mask mounted through the closing animation. Unmounted at rest so
  /// a settled transcript composites no offscreen layers.
  @State private var isFading: Bool

  /// A live turn starts revealing on its very first frame. Waiting for `.task`
  /// to arm it renders one frame of raw text first, and the reveal then opens
  /// on its first word — so the reply would visibly go *backwards* before it
  /// started.
  init(text: String, isStreaming: Bool) {
    self.text = text
    self.isStreaming = isStreaming
    _isRevealing = State(initialValue: isStreaming)
    _isFading = State(initialValue: isStreaming)
    _fadeAmount = State(initialValue: isStreaming ? 1 : 0)
  }

  var body: some View {
    Group {
      if isFading {
        revealedText.mask(revealFade)
      } else {
        revealedText
      }
    }
    .onChange(of: isRevealing) { _, revealing in
      handleRevealChange(revealing)
    }
    // Re-arms on every buffered change, then polls the model rather than
    // guessing a duration — the per-frame step is rate-limited, so a dropped
    // frame makes the real reveal outlast any estimate and the text would
    // freeze mid-sentence.
    .task(id: text) {
      if !primed {
        primed = true
        if !isStreaming { model.finish(full: text) }
      }
      guard !model.isComplete else {
        isRevealing = false
        return
      }
      isRevealing = true
      while !Task.isCancelled, !model.isComplete {
        try? await Task.sleep(for: .milliseconds(80))
      }
      // Cancellation means the next flush already re-armed this task, not that
      // the reveal finished. Clearing the flag here published one frame of raw
      // text between every flush — a strobe at the buffer's own 35ms cadence,
      // which is most of what read as "it just appears".
      guard !Task.isCancelled else { return }
      isRevealing = false
    }
  }

  private var revealedText: some View {
    TimelineView(
      .animation(minimumInterval: ChatRevealModel.minimumInterval, paused: !isRevealing)
    ) { timeline in
      OmiMarkdown(
        text: isRevealing
          ? model.revealed(at: timeline.date, full: text, isStreaming: isStreaming)
          : text,
        sender: .ai
      )
    }
  }

  private func handleRevealChange(_ revealing: Bool) {
    if revealing {
      isFading = true
      OmiMotion.withGated(.easeOut(duration: 0.2)) { fadeAmount = 1 }
      return
    }
    OmiMotion.withGated(.easeOut(duration: 0.28)) { fadeAmount = 0 }
    Task {
      try? await Task.sleep(for: .milliseconds(320))
      guard !isRevealing else { return }
      isFading = false
    }
  }

  /// Solid everywhere but the last `fadeBand` points. `band` shrinks with the
  /// block so a short reply keeps a proportionally smaller fade and a
  /// single-line one gets none at all.
  private var revealFade: some View {
    GeometryReader { geometry in
      let room = geometry.size.height - Self.fadeBand
      let band = max(0, min(Self.fadeBand, room)) * fadeAmount
      VStack(spacing: 0) {
        Rectangle()
        LinearGradient(
          colors: [.black, .black.opacity(0.12)],
          startPoint: .top,
          endPoint: .bottom
        )
        .frame(height: band)
      }
    }
  }
}
