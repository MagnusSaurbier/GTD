import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import GTDMarkdown

/// N2 under randomised input (T41).
///
/// `RoundTripTests` pins the sample vault and ~40 hand-written nasty cases. This suite generates
/// notes instead: every permutation of frontmatter key order, block vs. flow lists, comments,
/// blank lines, unknown keys, unknown body sections, CRLF, BOM and a missing final newline that
/// the generator below can reach. Each note is asserted twice —
///
/// 1. `encode(decode(t)) == t`, byte for byte (nothing is rewritten that nobody touched), and
/// 2. after changing **one** field, everything else decodes back exactly as before and every
///    unknown key and unknown section is still in the file.
///
/// A failure prints the seed; `Fuzz(seed:)` reproduces that one note on its own.
struct FuzzRoundTripTests {

    // MARK: - The two properties

    @Test func fuzzedActionNotesRoundTripByteForByte() throws {
        for seed in UInt64(1)...500 {
            var fuzz = Fuzz(seed: seed)
            let note = fuzz.actionNote(requireKnownHeading: false)
            let id = NoteID(path: "Actions/Fuzzed \(seed).md")
            let action = try NoteCodec.decodeAction(id: id, text: note, timeZone: vaultTimeZone)
            let encoded = NoteCodec.encode(action, timeZone: vaultTimeZone)
            #expect(encoded == note, "seed \(seed) — \(firstDifference(note, encoded))")
        }
    }

    @Test func changingOneFieldOfAFuzzedActionChangesNothingElse() throws {
        for seed in UInt64(1000)...1400 {
            var fuzz = Fuzz(seed: seed)
            let note = fuzz.actionNote(requireKnownHeading: true)
            let id = NoteID(path: "Actions/Fuzzed \(seed).md")
            let before = try NoteCodec.decodeAction(id: id, text: note, timeZone: vaultTimeZone)
            // #86 — a note with a legacy `defer:` is rewritten as waiting by any edit that leaves
            // it open, on purpose (`PatchTests`); "nothing else moved" holds for every other note.
            if try NoteCodec.decodeStoredAction(id: id, text: note, timeZone: vaultTimeZone).deferDate != nil {
                continue
            }

            let mutation = fuzz.pick(Mutation.all)
            var after = before
            mutation.apply(&after)
            let rewritten = NoteCodec.encode(after, timeZone: vaultTimeZone)
            let reread = try NoteCodec.decodeAction(id: id, text: rewritten, timeZone: vaultTimeZone)

            #expect(mutation.reads(reread) == mutation.reads(after),
                    "seed \(seed) — \(mutation.name) did not survive the write")
            for other in Mutation.all where other.name != mutation.name {
                #expect(other.reads(reread) == other.reads(before),
                        "seed \(seed) — \(mutation.name) disturbed \(other.name)")
            }
            for key in Fuzz.unknownKeyNames where note.contains("\n\(key):") || note.hasPrefix("\(key):") {
                #expect(rewritten.contains("\(key):"),
                        "seed \(seed) — unknown key \(key) was dropped by \(mutation.name)")
            }
            for heading in Fuzz.unknownHeadings where note.contains("# \(heading)") {
                #expect(rewritten.contains("# \(heading)"),
                        "seed \(seed) — unknown section \(heading) was dropped by \(mutation.name)")
            }
        }
    }

    @Test func fuzzedProjectNotesRoundTripByteForByte() throws {
        for seed in UInt64(2000)...2300 {
            var fuzz = Fuzz(seed: seed)
            let note = fuzz.projectNote()
            let id = NoteID(path: "Projects/Fuzz \(seed)/Fuzz \(seed).md")
            let project = try NoteCodec.decodeProject(id: id, text: note)
            let encoded = NoteCodec.encode(project)
            #expect(encoded == note, "seed \(seed) — \(firstDifference(note, encoded))")
        }
    }

    /// Steps and the log are the two lists the reducer rewrites most often; a project note keeps
    /// its unknown sections and its `# Outcome`/`# Why?` text while they change.
    @Test func editingProjectStepsKeepsEverythingElseInTheProjectNote() throws {
        for seed in UInt64(3000)...3300 {
            var fuzz = Fuzz(seed: seed)
            let note = fuzz.projectNote()
            let id = NoteID(path: "Projects/Fuzz \(seed)/Fuzz \(seed).md")
            let before = try NoteCodec.decodeProject(id: id, text: note)

            var after = before
            after.steps.append(ProjectStep(text: "A new step", done: false))
            if !after.steps.isEmpty { after.steps[0].done.toggle() }
            after.log.append(LogEntry(day: Day(year: 2026, month: 9, day: 19), text: "Fuzzed"))
            let rewritten = NoteCodec.encode(after)
            let reread = try NoteCodec.decodeProject(id: id, text: rewritten)

            #expect(reread.steps.map(\.text) == after.steps.map(\.text), "seed \(seed) — step texts")
            #expect(reread.steps.map(\.done) == after.steps.map(\.done), "seed \(seed) — step marks")
            #expect(reread.steps.map(\.promotedTo) == after.steps.map(\.promotedTo),
                    "seed \(seed) — a promoted step's wikilink")
            #expect(reread.log == after.log, "seed \(seed) — log")
            #expect(reread.outcome == before.outcome, "seed \(seed) — outcome")
            #expect(reread.why == before.why, "seed \(seed) — why")
            #expect(reread.status == before.status, "seed \(seed) — status")
            #expect(reread.area == before.area, "seed \(seed) — area")
            for heading in Fuzz.unknownHeadings where note.contains("# \(heading)") {
                #expect(rewritten.contains("# \(heading)"),
                        "seed \(seed) — unknown section \(heading) was dropped")
            }
        }
    }

    @Test func fuzzedInboxItemsRoundTripAndSurviveATextEdit() throws {
        for seed in UInt64(4000)...4300 {
            var fuzz = Fuzz(seed: seed)
            let note = fuzz.inboxNote()
            let id = NoteID(path: "Inbox/2026-09-19 093000.md")
            let item = try NoteCodec.decodeInboxItem(id: id, text: note, timeZone: vaultTimeZone)
            #expect(NoteCodec.encode(item, timeZone: vaultTimeZone) == note,
                    "seed \(seed) — \(firstDifference(note, NoteCodec.encode(item, timeZone: vaultTimeZone)))")

            var edited = item
            edited.body = "rewritten by the user\nwith a second line"
            let rewritten = NoteCodec.encode(edited, timeZone: vaultTimeZone)
            let reread = try NoteCodec.decodeInboxItem(id: id, text: rewritten, timeZone: vaultTimeZone)
            #expect(reread.body == edited.body, "seed \(seed) — edited body")
            #expect(reread.created == item.created, "seed \(seed) — created must survive an edit (I1)")
            #expect(reread.reviewReason == item.reviewReason, "seed \(seed) — reviewReason")
            for key in Fuzz.unknownKeyNames where note.contains("\n\(key):") || note.hasPrefix("\(key):") {
                #expect(rewritten.contains("\(key):"), "seed \(seed) — unknown key \(key) was dropped")
            }
        }
    }

    /// Deliverable 2 of the T41 brief: the codec against **damaged** files.
    ///
    /// Every file of the sample vault is mutated in a dozen ways a bad sync, a half-finished
    /// hand edit or a crash could produce (truncation, a dropped line, a duplicated line, junk
    /// inserted, a swapped pair of lines). Two outcomes are acceptable and no third one is:
    /// the file decodes — and then still round-trips byte for byte, so the app will not rewrite
    /// the damage into something else — or it is refused as `NoteCodecError.unreadable`, which
    /// `GTDVault` shows as a `VaultIssue`. A crash, a hang or a silent content change is a bug.
    @Test func mutatedSampleVaultFilesEitherRoundTripOrAreRefused() throws {
        var decoded = 0, refused = 0
        for (path, original) in SampleVault.files.sorted(by: { $0.key < $1.key }) {
            let id = NoteID(path: path)
            for seed in UInt64(1)...12 {
                var fuzz = Fuzz(seed: seed &* 31 &+ UInt64(path.count))
                let damaged = fuzz.damage(original)
                let encoded: String
                do {
                    encoded = try RoundTrip.encodeDecoded(path: path, text: damaged)
                    decoded += 1
                } catch is NoteCodecError {
                    refused += 1
                    continue
                } catch {
                    Issue.record("\(path) seed \(seed) — threw \(error), not NoteCodecError")
                    continue
                }
                let where_ = "\(path) seed \(seed)"

                switch RoundTrip.kind(of: id, text: damaged) {
                case .routineLog:
                    // The one encoder that regenerates instead of patching (module README), so
                    // byte equality is not its contract — not losing an entry is.
                    let before = try NoteCodec.decodeRoutineLog(id: id, text: damaged, timeZone: vaultTimeZone)
                    let after = try NoteCodec.decodeRoutineLog(id: id, text: encoded, timeZone: vaultTimeZone)
                    #expect(after == before, "\(where_) — a routine log lost entries on rewrite")

                default:
                    // A note whose `kind:` line was the casualty gets it back: without it the
                    // file cannot be classified at all, so this one insertion is deliberate
                    // self-healing. Nothing else may move.
                    let hadKind = (try? FrontmatterDocument(text: damaged, path: path))?.hasKey("kind") ?? true
                    let healed = hadKind ? encoded : withoutFirstKindLine(encoded)
                    // A file whose frontmatter lost its closing `---` is all body, so the
                    // encoder gives it a fresh frontmatter block on top. Nothing is deleted —
                    // the damaged text is still there, in full, underneath.
                    let lossless = healed == damaged || encoded.hasSuffix(damaged)
                    let why = "\(where_) — a damaged file was rewritten: "
                        + firstDifference(damaged, healed)
                    #expect(lossless, "\(why)")
                }
            }
        }
        #expect(decoded > 100, "the damage was so heavy nothing decoded (\(decoded))")
        #expect(refused > 5, "no damaged file was refused (\(refused)) — the generator is too gentle")
    }

    // MARK: - A single-field mutation, described so the test can name it

    struct Mutation: Sendable {
        let name: String
        let apply: @Sendable (inout Action) -> Void
        /// A printable projection of the field this mutation owns, for the "nothing else moved" check.
        let reads: @Sendable (Action) -> String

        static let all: [Mutation] = [
            Mutation(name: "status",
                     apply: { $0.status = $0.status == .next ? .someday : .next },
                     reads: { $0.status.rawValue }),
            Mutation(name: "contexts",
                     apply: { $0.contexts = $0.contexts == ["home"] ? [] : ["home"] },
                     reads: { $0.contexts.joined(separator: ",") }),
            Mutation(name: "timeEstimate",
                     apply: { $0.timeEstimate = $0.timeEstimate == 45 ? nil : 45 },
                     reads: { $0.timeEstimate.map(String.init) ?? "-" }),
            Mutation(name: "project",
                     apply: { $0.project = $0.project == nil ? NoteID(path: "Projects/Fuzz/Fuzz.md") : nil },
                     reads: { $0.project?.path ?? "-" }),
            Mutation(name: "due",
                     apply: { $0.due = $0.due == nil ? Day(year: 2027, month: 2, day: 4) : nil },
                     reads: { $0.due.map(\.iso) ?? "-" }),
            Mutation(name: "waitingFor",
                     apply: { $0.waitingFor = $0.waitingFor == nil ? "Someone: else" : nil },
                     reads: { $0.waitingFor ?? "-" }),
            Mutation(name: "followUpDate",
                     apply: { $0.followUpDate = $0.followUpDate == nil ? Day(year: 2027, month: 3, day: 5) : nil },
                     reads: { $0.followUpDate.map(\.iso) ?? "-" }),
            Mutation(name: "completedDate",
                     apply: { $0.completedDate = $0.completedDate == nil ? Fuzz.aDate : nil },
                     reads: { $0.completedDate.map { String($0.timeIntervalSince1970) } ?? "-" }),
            Mutation(name: "reviewReason",
                     apply: { $0.reviewReason = $0.reviewReason == nil ? "Needs a decision" : nil },
                     reads: { $0.reviewReason ?? "-" }),
            Mutation(name: "why",
                     apply: { $0.why = $0.why == "Because it matters." ? "Another reason." : "Because it matters." },
                     reads: { $0.why }),
            Mutation(name: "what",
                     apply: { $0.what = $0.what.contains("rewritten") ? "- [ ] first\n- [x] second" : "rewritten" },
                     reads: { $0.what }),
        ]
    }
}

/// Drops the first `kind: …` frontmatter line, so the self-healing insertion can be discounted.
private func withoutFirstKindLine(_ text: String) -> String {
    var lines = RawText.split(text)
    guard let index = lines.firstIndex(where: { $0.content.hasPrefix("kind:") }) else { return text }
    lines.remove(at: index)
    return lines.map { $0.content + $0.terminator }.joined()
}

// MARK: - The generator

/// A deterministic note generator. `Fuzz(seed:)` reproduces exactly one note, so a failing
/// `#expect` message ("seed 1234") is enough to debug it.
struct Fuzz {
    private var state: UInt64

    init(seed: UInt64) { state = seed &* 0x9E37_79B9_7F4A_7C15 &+ 0x1234_5678 }

    /// SplitMix64 — small, self-contained, identical on every platform (unlike `SystemRandomNumberGenerator`).
    mutating func next() -> UInt64 {
        state = state &+ 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func int(_ upperBound: Int) -> Int { Int(next() % UInt64(upperBound)) }
    mutating func bool(_ percent: Int = 50) -> Bool { int(100) < percent }
    mutating func pick<T>(_ options: [T]) -> T { options[int(options.count)] }

    mutating func shuffled<T>(_ items: [T]) -> [T] {
        var copy = items
        guard copy.count > 1 else { return copy }
        for index in stride(from: copy.count - 1, to: 0, by: -1) {
            copy.swapAt(index, int(index + 1))
        }
        return copy
    }

    static let aDate = Date(timeIntervalSince1970: 1_790_000_000)
    static let unknownKeyNames = ["tags", "priority", "Ressources", "aliases", "cssclass", "obsidianUIMode"]
    static let unknownHeadings = ["Notes", "Links", "Scratch", "Anhang"]

    // MARK: Pieces

    /// One frontmatter entry, already split into its own lines (a block list is several).
    private mutating func knownActionEntries() -> [[String]] {
        var entries: [[String]] = [["status: \(pick(["next", "someday", "backlog", "maybe", "trash", "in-progress", "waiting", "done"]))"]]
        if bool(70) {
            entries.append(bool() ? ["contexts: [mac, campus]"] : ["contexts:", "  - mac", "  - campus"])
        }
        if bool(50) { entries.append(["timeEstimate: \(pick(["10", "30", "60", "90", "0"]))"]) }
        if bool(40) { entries.append(["project: \"[[Projects/Applications/DAAD/DAAD]]\""]) }
        if bool(25) { entries.append(["defer: 2026-10-01"]) }
        if bool(25) { entries.append(["due: 2026-10-05"]) }
        if bool(20) { entries.append(["waitingFor: \(pick(["\"Prof. Weber\"", "Marie", "\"a person: with a colon\""]))"]) }
        if bool(20) { entries.append(["followUpDate: 2026-09-26"]) }
        if bool(60) { entries.append(["created: \(pick(["2026-09-19T09:30:00+02:00", "2026-09-19 09:30:00", "2026-09-19"]))"]) }
        if bool(15) { entries.append(["completedDate: 2026-09-18T20:00:00+02:00"]) }
        if bool(15) { entries.append(["reviewReason: \"It is a decision, not an action.\""]) }
        return entries
    }

    private mutating func unknownEntries() -> [[String]] {
        var entries: [[String]] = []
        for name in Fuzz.unknownKeyNames where bool(30) {
            switch name {
            case "tags": entries.append(bool() ? ["tags: [uni, admin]"] : ["tags:", "  - uni", "  - admin"])
            case "aliases": entries.append(["aliases:", "  - the other name"])
            case "Ressources": entries.append(["Ressources: \"\""])
            case "obsidianUIMode":
                entries.append(bool()
                    ? ["obsidianUIMode: preview"]
                    : ["obsidianUIMode:", "  mode: preview", "  pinned: true"])   // a nested mapping
            default:
                entries.append(bool(80)
                    ? ["\(name): \(pick(["high", "\"quoted\"", "42", "true", "\"a # not a comment\"", "'single'"]))"]
                    : ["\(name): |", "  a block scalar", "  over two lines"])
            }
        }
        return entries
    }

    private mutating func decorate(_ entries: [[String]]) -> [String] {
        var lines: [String] = []
        for entry in entries {
            if bool(15) { lines.append("# \(pick(["a comment", "TODO: check this", "written by hand"]))") }
            if bool(10) { lines.append("") }
            lines.append(contentsOf: entry)
        }
        if bool(15) { lines.append("") }
        return lines
    }

    private mutating func bodySections(known: [String], requireKnownHeading: Bool) -> [[String]] {
        var sections: [[String]] = []
        for heading in known where bool(75) || (requireKnownHeading && sections.isEmpty) {
            sections.append(["# \(spelling(of: heading))"] + sectionBody(for: heading))
            // Obsidian users repeat headings; the codec patches the first and leaves the rest.
            if bool(10) { sections.append(["# \(spelling(of: heading))", "a second copy"]) }
        }
        if requireKnownHeading && sections.isEmpty {
            sections.append(["# \(known[0])"] + sectionBody(for: known[0]))
        }
        for heading in Fuzz.unknownHeadings where bool(25) {
            sections.append(["# \(heading)", pick(["some text", "- a bullet", "> a quote", ""])])
        }
        return sections
    }

    /// The codec matches headings case- and punctuation-insensitively, so a real vault's
    /// `# why` or `# WHAT` must be found and patched in place, never duplicated.
    private mutating func spelling(of heading: String) -> String {
        let bare = heading.hasSuffix("?") ? String(heading.dropLast()) : heading
        return pick([heading, bare, bare.lowercased(), bare.uppercased(), heading.lowercased(),
                     heading + " ", bare + ":"])
    }

    private mutating func sectionBody(for heading: String) -> [String] {
        switch heading {
        case "What?":
            return bool() ? ["- [ ] Pay at the counter", "- [x] Print the form"] : ["Just prose."]
        case "Steps":
            var steps: [String] = []
            for index in 0..<(1 + int(3)) {
                let done = bool(30) ? "x" : " "
                let link = bool(30) ? " → [[Actions/Step \(index)]]" : ""
                steps.append("- [\(done)] Step \(index)\(link)")
            }
            return steps
        case "Log":
            return (0..<(1 + int(2))).map { "- 2026-09-1\($0) Did a thing" }
        default:
            return [pick(["Because it matters.", "A reason\nspanning two lines.", ""])]
        }
    }

    private mutating func assemble(frontmatter: [String], body: [[String]]) -> String {
        let terminator = bool(15) ? "\r\n" : "\n"
        var lines = ["---"] + frontmatter + ["---"]
        var sections = shuffled(body)
        if bool(15), !sections.isEmpty { sections.insert([pick(["A loose intro line.", "---"])], at: 0) }
        for (index, section) in sections.enumerated() {
            lines.append(contentsOf: section)
            if index < sections.count - 1 && bool(80) { lines.append("") }
        }
        var text = lines.joined(separator: terminator)
        if bool(85) { text += terminator }              // 15 % of notes have no final newline
        if bool(8) { text = "\u{FEFF}" + text }          // and a few carry a BOM
        return text
    }

    // MARK: Damage

    /// One random edit of the kind a bad sync or a half-finished hand edit leaves behind.
    mutating func damage(_ text: String) -> String {
        var lines = RawText.split(text).map { $0.content + $0.terminator }
        guard lines.count > 2 else { return text }
        switch int(6) {
        case 0:                                     // truncated mid-file
            lines = Array(lines.prefix(1 + int(lines.count)))
        case 1:                                     // a line vanished
            lines.remove(at: int(lines.count))
        case 2:                                     // a line arrived twice
            let index = int(lines.count)
            lines.insert(lines[index], at: index)
        case 3:                                     // junk inserted
            lines.insert(pick(["status: nonsense", "\t", "---", "# ", "key: [unclosed",
                               "  indented orphan", "\u{0}"]), at: int(lines.count))
        case 4:                                     // two lines swapped
            let a = int(lines.count), b = int(lines.count)
            lines.swapAt(a, b)
        default:                                    // one character mangled
            let index = int(lines.count)
            if !lines[index].isEmpty { lines[index] = String(lines[index].dropFirst()) }
        }
        return lines.joined()
    }

    // MARK: Notes

    mutating func actionNote(requireKnownHeading: Bool) -> String {
        let entries = shuffled(knownActionEntries() + unknownEntries())
        // `status` must stay, but may sit anywhere: shuffling above already guarantees that.
        return assemble(frontmatter: decorate(entries),
                        body: bodySections(known: ["Why?", "What?"], requireKnownHeading: requireKnownHeading))
    }

    mutating func projectNote() -> String {
        var entries: [[String]] = [["kind: project"],
                                   ["status: \(pick(["active", "on-hold", "someday", "done"]))"]]
        if bool(60) { entries.append(["area: \"[[Projects/Applications/Applications]]\""]) }
        entries = shuffled(entries + unknownEntries())
        return assemble(frontmatter: decorate(entries),
                        body: bodySections(known: ["Outcome", "Why?", "Steps", "Log"],
                                           requireKnownHeading: true))
    }

    mutating func inboxNote() -> String {
        var entries: [[String]] = [["created: \(pick(["2026-09-19T09:30:00+02:00", "2026-09-19 09:30:00"]))"]]
        if bool(30) { entries.append(["reviewReason: \"It is a decision, not an action.\""]) }
        entries = shuffled(entries + unknownEntries())
        let terminator = bool(15) ? "\r\n" : "\n"
        var text = (["---"] + decorate(entries) + ["---"]).joined(separator: terminator) + terminator
        text += pick(["renew the Semesterticket",
                      "call the bank\nabout the card",
                      "- [ ] a captured checkbox",
                      ""])
        if bool(70) { text += terminator }
        if bool(8) { text = "\u{FEFF}" + text }
        return text
    }
}
