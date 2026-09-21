import Testing
import Foundation
import GTDModel
import GTDAppCore
import DesignSystem
import GTDFixtures
@testable import FeatureInbox

/// The step map, the drag maths and the key map of STYLEGUIDE §3.6 — the one definition both
/// platforms use (ARCHITECTURE §6).
struct CardTargetsTests {

    private let size = CGSize(width: 360, height: 600)
    private let opened = DragContext(step: .actionCard)

    // MARK: Drag (STYLEGUIDE §3.6 "Drag behaviour")

    @Test func dragResolverHonoursAxisLockAndThresholds() {
        #expect(DragResolver.outcome(dx: 8, dy: 4, cardSize: size, in: opened) == nil)
        #expect(DragResolver.outcome(dx: 200, dy: 10, cardSize: size, in: opened) == .file(.next))
        #expect(DragResolver.outcome(dx: -200, dy: 10, cardSize: size, in: opened) == .file(.someday))
        // Up files nothing since the tiers merged into Someday (A3): the card springs back.
        #expect(DragResolver.outcome(dx: 10, dy: -200, cardSize: size, in: opened) == nil)
        // No swipe ever trashes (STYLEGUIDE decision #12): down collapses the card to step 1,
        // past 25 % of its height, and files nothing.
        #expect(DragResolver.outcome(dx: 10, dy: 100, cardSize: size, in: opened) == nil)
        #expect(DragResolver.outcome(dx: 10, dy: 200, cardSize: size, in: opened) == .collapse)
    }

    /// "Step 1 — buttons only, no gestures. No drag is recognised on the small card."
    @Test func noDragIsRecognisedOnStepOne() {
        let step1 = DragContext(step: .step1)
        #expect(DragResolver.recognised(in: step1).isEmpty)
        #expect(DragResolver.direction(dx: 200, dy: 0, in: step1) == nil)
        #expect(DragResolver.outcome(dx: 200, dy: 0, cardSize: size, in: step1) == nil)
        #expect(DragResolver.outcome(dx: 0, dy: 300, cardSize: size, in: step1) == nil)
        #expect(DragResolver.lockedTranslation(dx: 200, dy: 0, in: step1) == .zero)
        #expect(DragResolver.commitment(dx: 200, dy: 0, cardSize: size, in: step1) == 0)
    }

    /// "The Knowledge / List card recognises only the downward drag."
    @Test func theKeepCardRecognisesOnlyTheDownwardDrag() {
        let keep = DragContext(step: .keepCard)
        #expect(DragResolver.recognised(in: keep) == [.down])
        #expect(DragResolver.outcome(dx: 300, dy: 0, cardSize: size, in: keep) == nil)
        #expect(DragResolver.outcome(dx: -300, dy: 0, cardSize: size, in: keep) == nil)
        #expect(DragResolver.outcome(dx: 0, dy: 200, cardSize: size, in: keep) == .collapse)
    }

    /// "Swipes are disabled while any text field is focused (keyboard up)."
    @Test func aFocusedFieldDisablesEverySwipe() {
        for step in InboxStep.allCases {
            let context = DragContext(step: step, isFieldFocused: true)
            #expect(DragResolver.recognised(in: context).isEmpty)
            #expect(DragResolver.outcome(dx: 300, dy: 0, cardSize: size, in: context) == nil)
            #expect(DragResolver.outcome(dx: 0, dy: 300, cardSize: size, in: context) == nil)
        }
    }

    @Test func dragLocksOntoTheDominantAxis() {
        #expect(DragResolver.direction(dx: 5, dy: 5, in: opened) == nil)   // below the 12 pt lock
        #expect(DragResolver.direction(dx: 30, dy: 12, in: opened) == .right)
        #expect(DragResolver.direction(dx: -30, dy: 12, in: opened) == .left)
        #expect(DragResolver.direction(dx: 12, dy: -30, in: opened) == nil)
        #expect(DragResolver.direction(dx: 12, dy: 30, in: opened) == .down)

        #expect(DragResolver.lockedTranslation(dx: 40, dy: 15, in: opened)
                == CGSize(width: 40, height: 0))
        #expect(DragResolver.lockedTranslation(dx: 15, dy: 40, in: opened)
                == CGSize(width: 0, height: 40))
    }

    @Test func commitmentReachesOneExactlyAtTheThreshold() {
        let size = CGSize(width: 400, height: 600)
        // 35 % of 400 = 140 pt.
        #expect(DragResolver.commitment(dx: 140, dy: 0, cardSize: size, in: opened) == 1)
        #expect(DragResolver.commitment(dx: 70, dy: 0, cardSize: size, in: opened) == 0.5)
        // Collapse: 25 % of 600 = 150 pt.
        #expect(DragResolver.commitment(dx: 0, dy: 150, cardSize: size, in: opened) == 1)
        #expect(DragResolver.commitment(dx: 0, dy: 0, cardSize: size, in: opened) == 0)
    }

    // MARK: Steps and exits

    @Test func everyExitBelongsToExactlyOneStep() {
        #expect(InboxExit.openAction.step == .step1)
        #expect(InboxExit.openKeep.step == .step1)
        // I4c/I5 — Trash and Defer to review are reachable only from step 1.
        #expect(InboxExit.trash.step == .step1)
        #expect(InboxExit.deferToReview.step == .step1)
        for exit in [InboxExit.next, .someday, .waiting, .done] {
            #expect(exit.step == .actionCard)
        }
        for exit in [InboxExit.knowledge, .list("Read"), .more] {
            #expect(exit.step == .keepCard)
        }
        #expect(!InboxStep.step1.isOpened)
        #expect(InboxStep.actionCard.isOpened && InboxStep.keepCard.isOpened)
    }

    @Test func everyExitHasAWordAndASymbolFromTheDesignSystem() {
        let exits: [InboxExit] = [
            .openAction, .openKeep, .trash, .deferToReview,
            .next, .someday, .waiting, .done,
            .knowledge, .list("Read"), .more, .collapse,
        ]
        #expect(exits.allSatisfy { !$0.title.isEmpty && !$0.symbol.isEmpty })
        #expect(InboxExit.openAction.title == Copy.actionKind)
        #expect(InboxExit.openKeep.title == Copy.knowledgeOrList)
        #expect(InboxExit.collapse.title == Copy.back)
        // A list slot speaks its own name and wears its own glyph (§7's fallback for a custom one).
        #expect(InboxExit.list("Read").title == "Read")
        #expect(InboxExit.list("Read").symbol == Symbols.listRead)
        #expect(InboxExit.list("Bücher").symbol == Symbols.listBullet)
    }

    @Test func theStepOneBarHoldsTheThreeKindButtons() {
        // "three equal, neutral, labelled buttons: Action · Knowledge / List · Trash". Defer is
        // the quiet text button under the card, not one of them.
        #expect(InboxExit.stepOneButtons == [.openAction, .openKeep, .trash])
        #expect(!InboxExit.stepOneButtons.contains(.deferToReview))
    }

    @Test func eachStepMapsToItsRebindableKeyScreen() {
        #expect(InboxStep.step1.keyScreen == .inboxStep1)
        #expect(InboxStep.actionCard.keyScreen == .actionCard)
        #expect(InboxStep.keepCard.keyScreen == .knowledgeListCard)
    }

    // MARK: Card targets (the summary and the undo toast)

    @Test func everyCardTargetHasANameASymbolAndItsRequiredFields() {
        #expect(CardTarget.allCases.count == 8)
        #expect(CardTarget.allCases.allSatisfy { !$0.title.isEmpty })
        #expect(CardTarget.allCases.allSatisfy { !$0.symbol.isEmpty })
        // R-3 — what each target demands before the card may leave through it.
        let demanding = CardTarget.allCases.filter {
            !$0.missingFields(why: "", what: "", contexts: [], timeEstimate: nil, followUpDate: nil)
                .isEmpty
        }
        #expect(demanding == [.next, .someday, .waiting])
        #expect(CardTarget.next.missingFields(
            why: "", what: "", contexts: [], timeEstimate: nil, followUpDate: nil)
            == [.why, .what, .context, .timeEstimate])
        #expect(CardTarget.done.missingFields(
            why: "", what: "", contexts: [], timeEstimate: nil, followUpDate: nil).isEmpty)
        #expect(CardTarget.list.missingFields(
            why: "", what: "", contexts: [], timeEstimate: nil, followUpDate: nil).isEmpty)
    }

    @Test func theUndoToastUsesTheCanonicalWording() {
        #expect(CardTarget.someday.undoToastLabel() == "Moved to Someday")
        #expect(CardTarget.next.undoToastLabel() == "Moved to Next")
        #expect(CardTarget.list.undoToastLabel(listName: "Read") == "Added to Read")
        #expect(CardTarget.deferToReview.undoToastLabel() == Copy.deferToReview)
        #expect(CardTarget.deferToReview.shortTitle == "Review")
        #expect(CardTarget.waiting.shortTitle == CardTarget.waiting.title)
    }

    @Test func theCommitmentAxisIsTheOnlyFilingSwipe() {
        #expect(SwipeDirection.right.exit == .next)
        #expect(SwipeDirection.left.exit == .someday)
        #expect(SwipeDirection.down.exit == nil, "down collapses, it does not file")
        #expect(CardTarget.actionCardMenu == [.someday, .next])
        #expect(CardTarget.actionCardButtons == [.waiting, .done])
    }

    // MARK: Keys (R-10 — everything rebindable goes through `KeyBindings`)

    @Test func letterKeysResolvePerStep() {
        #expect(KeyMap.resolve("a", step: .step1) == .command(.stepAction))
        #expect(KeyMap.resolve("A", step: .step1) == .command(.stepAction))
        #expect(KeyMap.resolve("k", step: .step1) == .command(.stepKnowledge))
        #expect(KeyMap.resolve("x", step: .step1) == .command(.stepTrash))
        #expect(KeyMap.resolve("d", step: .step1) == .command(.stepDefer))
        #expect(KeyMap.resolve("q", step: .step1) == nil)
        // The action card's letters are different ones — a step-1 key does nothing there.
        #expect(KeyMap.resolve("w", step: .actionCard) == .command(.cardWaiting))
        #expect(KeyMap.resolve("p", step: .actionCard) == .command(.cardProject))
        #expect(KeyMap.resolve("a", step: .actionCard) == nil)
        #expect(KeyMap.resolve("x", step: .actionCard) == nil, "Trash is step 1 only")
        #expect(KeyMap.resolve("w", step: .keepCard) == nil)
    }

    @Test func arrowsAreTheCommitmentAxisOnTheActionCardOnly() {
        #expect(KeyMap.resolve(stroke: .arrowRight, step: .actionCard) == .command(.cardNext))
        #expect(KeyMap.resolve(stroke: .arrowLeft, step: .actionCard) == .command(.cardSomeday))
        #expect(KeyMap.resolve(stroke: .arrowRight, step: .step1) == nil)
        #expect(KeyMap.resolve(stroke: .arrowRight, step: .keepCard) == nil)
    }

    @Test func projectKeyFollowsARebind() throws {
        var bindings = KeyBindings.defaults
        try bindings.rebind(.cardProject, to: .letter("J"))
        #expect(KeyMap.resolve("j", step: .actionCard, bindings: bindings) == .command(.cardProject))
        #expect(KeyMap.resolve("p", step: .actionCard, bindings: bindings) == nil)
        // A rebind on one screen leaves the others alone.
        #expect(KeyMap.resolve("j", step: .step1, bindings: bindings) == nil)
        #expect(KeyMap.resolve("a", step: .step1, bindings: bindings) == .command(.stepAction))
    }

    @Test func digitsPickContextsAndShiftedDigitsPickTimeBucketsOnTheActionCard() {
        #expect(KeyMap.resolve("1", step: .actionCard) == .context(index: 0))
        #expect(KeyMap.resolve("8", step: .actionCard) == .context(index: 7))
        #expect(KeyMap.resolve("9", step: .actionCard) == nil)
        #expect(KeyMap.resolve("1", shift: true, step: .actionCard) == .time(.upTo10))
        #expect(KeyMap.resolve("4", shift: true, step: .actionCard) == .time(.over60))
        #expect(KeyMap.resolve("5", shift: true, step: .actionCard) == nil)
        // US layout sends the shifted character rather than the digit.
        #expect(KeyMap.resolve("!", step: .actionCard) == .time(.upTo10))
        #expect(KeyMap.resolve("$", step: .actionCard) == .time(.over60))
        // Step 1 has no digits at all.
        #expect(KeyMap.resolve("1", step: .step1) == nil)
        #expect(KeyMap.resolve("!", step: .step1) == nil)
    }

    @Test func digitsAreNavbarSlotsOnTheKeepCard() {
        #expect(KeyMap.resolve("1", step: .keepCard) == .command(.listKnowledge))
        #expect(KeyMap.resolve("2", step: .keepCard) == .command(.listSlot2))
        #expect(KeyMap.resolve("9", step: .keepCard) == .command(.listSlot9))
        #expect(KeyMap.resolve("0", step: .keepCard) == .command(.listMore))
        // No contexts and no time buckets here — the keep card has no chips.
        #expect(KeyMap.resolve("!", step: .keepCard) == nil)
    }

    @Test func undoEscapeAndDoneAreFixedKeys() {
        for step in InboxStep.allCases {
            #expect(KeyMap.resolve("z", command: true, step: step) == .undo)
            #expect(KeyMap.resolve("Z", command: true, step: step) == .undo)
            #expect(KeyMap.resolve("\u{1B}", step: step) == .escape)
            #expect(KeyMap.resolve("q", command: true, step: step) == nil)
        }
        #expect(KeyMap.resolve("z", step: .step1) != .undo)
        // `⌘↩` is Done, and only the action card has a Done.
        #expect(KeyMap.resolve("\r", command: true, step: .actionCard) == .done)
        #expect(KeyMap.resolve("\r", command: true, step: .step1) == nil)
        #expect(KeyMap.resolve(stroke: .commandReturn, step: .keepCard) == nil)
    }
}

/// The sub-flow data: folder tree, project picker model, navbar, checklist text.
struct InboxPickerTests {

    @Test func folderTreeMaterialisesMissingParents() {
        let tree = KnowledgeTree.build(["Studium/Thesis", "Finanzen", "Technik/Server/Backup"])
        #expect(tree.map(\.name) == ["Finanzen", "Studium", "Technik"])

        let studium = try! #require(tree.first { $0.name == "Studium" })
        #expect(studium.path == "Studium")
        #expect(studium.childNodes?.map(\.path) == ["Studium/Thesis"])

        let technik = try! #require(tree.first { $0.name == "Technik" })
        let server = try! #require(technik.children.first)
        #expect(server.path == "Technik/Server")
        #expect(server.children.first?.path == "Technik/Server/Backup")
        #expect(server.children.first?.childNodes == nil)   // leaf
    }

    @Test func folderTreeOfTheSampleVault() {
        let tree = KnowledgeTree.build(Fixtures.sampleSnapshot.knowledgeFolders)
        #expect(tree.map(\.name) == ["Finanzen", "Studium", "Technik", "Wohnen"])
        #expect(tree.first { $0.name == "Studium" }?.children.map(\.name) == ["Thesis"])
    }

    @Test func newFoldersAreAddedWithoutTouchingTheVault() {
        let folders = ["Technik"]
        #expect(KnowledgeTree.adding("Server", under: "Technik", to: folders) == ["Technik", "Technik/Server"])
        #expect(KnowledgeTree.adding("Reisen", under: "", to: folders) == ["Technik", "Reisen"])
        #expect(KnowledgeTree.adding("  ", under: "", to: folders) == folders)
        #expect(KnowledgeTree.adding("Technik", under: "", to: folders) == folders)   // no duplicates
    }

    /// I4b — the tree **plus** a `Projects` section of active projects, and the last-used folder
    /// as a suggestion that is never part of a decision.
    @Test func theKnowledgePickerOffersTheTreeTheProjectsAndASuggestion() {
        let snapshot = Fixtures.sampleSnapshot
        let model = KnowledgeTree.model(
            folders: snapshot.knowledgeFolders,
            projects: snapshot.projects,
            suggestion: "Technik")
        #expect(model.tree.map(\.name) == ["Finanzen", "Studium", "Technik", "Wohnen"])
        #expect(model.suggestion == "Technik")
        #expect(model.suggestedTarget == .folder("Technik"))
        // Only active projects take reference material (D36).
        #expect(!model.projects.isEmpty)
        #expect(model.projects.allSatisfy { $0.status == .active })
    }

    @Test func aSuggestedFolderThatNoLongerExistsIsDropped() {
        let model = KnowledgeTree.model(
            folders: ["Technik"], projects: [], suggestion: "Reisen")
        #expect(model.suggestion == nil)
        #expect(model.suggestedTarget == nil)
    }

    @Test func projectsAreGroupedByAreaWithUngroupedFirst() {
        var snapshot = Fixtures.sampleSnapshot
        let loose = Project(
            id: NoteID(path: "Projects/no_area/Umzug/Umzug.md"), title: "Umzug", area: nil,
            status: .active)
        snapshot.projects.append(loose)

        let groups = ProjectPicker.groups(snapshot)
        // Ungrouped projects come first, in one headerless group.
        #expect(groups.first?.area == nil)
        #expect(groups.first?.title == nil)
        #expect(groups.first?.projects.contains { $0.title == "Umzug" } == true)
        #expect(groups.dropFirst().allSatisfy { $0.area != nil })
        // Areas are sorted, and an area with no open project gets no empty section.
        let areaTitles = groups.dropFirst().compactMap(\.title)
        #expect(areaTitles == areaTitles.sorted())
        #expect(groups.dropFirst().allSatisfy { !$0.projects.isEmpty })
        // Done projects are never offered.
        #expect(!groups.flatMap(\.projects).contains { $0.status == .done })
        #expect(groups.flatMap(\.projects).count
                == snapshot.projects.count { $0.status != .done })
    }

    /// I4a — "Typing filters the tree. When the text matches no project exactly, the last row is
    /// `Create project "<text>"`."
    @Test func theProjectPickerFiltersTheTreeAndOffersTheCreateRow() {
        var snapshot = Fixtures.sampleSnapshot
        snapshot.projects.append(
            Project(id: NoteID(path: "Projects/no_area/Umzug/Umzug.md"), title: "Umzug",
                    area: nil, status: .active))

        let unfiltered = ProjectPicker.model(snapshot)
        #expect(unfiltered.groups == ProjectPicker.groups(snapshot))
        #expect(unfiltered.createTitle == nil, "an empty search offers no create row")

        let filtered = ProjectPicker.model(snapshot, search: "umz")
        #expect(filtered.groups.count == 1)
        #expect(filtered.groups.first?.area == nil)
        #expect(filtered.groups.flatMap(\.projects).map(\.title) == ["Umzug"])
        #expect(filtered.createTitle == "umz", "a partial match still offers the create row")

        // An exact match, case-insensitive and trimmed, takes the create row away.
        #expect(ProjectPicker.model(snapshot, search: "Umzug").createTitle == nil)
        #expect(ProjectPicker.model(snapshot, search: "  umzug  ").createTitle == nil)

        let miss = ProjectPicker.model(snapshot, search: "Steuererklärung 2031")
        #expect(miss.groups.isEmpty)
        #expect(miss.isEmpty)
        #expect(miss.createTitle == "Steuererklärung 2031")
    }

    /// STYLEGUIDE §3.6 — the navbar's fixed slots, clipped to the platform's favourite limit.
    @Test func theNavbarKeepsKnowledgeFirstAndMoreLast() {
        let favourites = ["Read", "Watch", "Wish", "Bücher", "Podcasts", "Kurse", "Reisen", "Ideen", "Extra"]
        let phone = NavbarLayout.slots(favourites: favourites, platform: .iPhone)
        #expect(phone.first?.kind == .knowledge)
        #expect(phone.last?.kind == .more)
        #expect(phone.count == 6, "Knowledge + 4 favourites + More…")

        let mac = NavbarLayout.slots(favourites: favourites, platform: .mac)
        #expect(mac.count == 10, "Knowledge + 8 favourites + More…")
        #expect(mac.dropFirst().dropLast().map(\.keyIndex) == Array(2...9))

        // Zero favourites still leaves both fixed slots.
        let bare = NavbarLayout.slots(favourites: [], platform: .iPhone)
        #expect(bare.map(\.kind) == [.knowledge, .more])
    }

    @Test func checklistButtonIsIdempotentAndReversible() {
        let plain = "Ring the Hausverwaltung\nNote the case number"
        let list = ChecklistText.asChecklist(plain)
        #expect(list == "- [ ] Ring the Hausverwaltung\n- [ ] Note the case number")
        #expect(ChecklistText.asChecklist(list) == list)
        #expect(ChecklistText.isChecklist(list))
        #expect(!ChecklistText.isChecklist(plain))
        #expect(ChecklistText.asPlainText(list) == plain)
        #expect(Checkbox.scan(list).count == 2)
    }

    @Test func typingADashTurnsTheLineIntoACheckbox() {
        #expect(ChecklistText.autoFormat("- Ring them") == "- [ ] Ring them")
        #expect(ChecklistText.autoFormat("- ") == "- [ ] ")
        #expect(ChecklistText.autoFormat("- [ ] Ring them") == "- [ ] Ring them")
        #expect(ChecklistText.autoFormat("Ring them") == "Ring them")
        #expect(ChecklistText.autoFormat("- [") == "- [")   // mid-marker, left alone
        #expect(ChecklistText.autoFormat("a\n- b") == "a\n- [ ] b")
    }

    /// R-4 replaced "the title is derived from What?" with "the capture text is the title";
    /// `CaptureText` (GTDModel) owns that rule now and is tested there. What is left here is the
    /// checklist helper the card still uses.
    @Test func checklistLinesReportTheirFirstContentLine() {
        #expect(ChecklistText.firstContentLine("- [ ] Ring them\n- [ ] Note it") == "Ring them")
        #expect(ChecklistText.firstContentLine("\n\n  Ring them") == "Ring them")
        #expect(ChecklistText.firstContentLine("") == "")
    }

    @Test func captureStampShowsTheOnlyTimeOfDayInTheApp() {
        let stamp = InboxCopy.captureStamp(
            Fixtures.date(Fixtures.today, 8, 12), today: Fixtures.today, calendar: Fixtures.calendar)
        #expect(stamp == "today 08:12")
        let older = InboxCopy.captureStamp(
            Fixtures.date(Fixtures.day(-11), 17, 5), today: Fixtures.today, calendar: Fixtures.calendar)
        #expect(older == "8 Sep 17:05")
    }

    @MainActor
    @Test func deviceLocalStoreKeepsTheLastFolderAndTheHintFlag() {
        let defaults = EphemeralInboxDefaults(lastKnowledgeFolder: nil, didShowSwipeHint: false)
        #expect(defaults.string(forKey: InboxDefaultsKey.lastKnowledgeFolder) == nil)
        #expect(!defaults.flag(forKey: InboxDefaultsKey.didShowSwipeHint))
        defaults.setString("Technik", forKey: InboxDefaultsKey.lastKnowledgeFolder)
        defaults.setFlag(true, forKey: InboxDefaultsKey.didShowSwipeHint)
        #expect(defaults.string(forKey: InboxDefaultsKey.lastKnowledgeFolder) == "Technik")
        #expect(defaults.flag(forKey: InboxDefaultsKey.didShowSwipeHint))
    }
}
