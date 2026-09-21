import Testing
import Foundation
import GTDModel
import GTDFixtures
@testable import FeatureInbox

/// The swipe/key map and the drag maths of STYLEGUIDE §3.6 — the one definition both platforms
/// use (ARCHITECTURE §6).
struct CardTargetsTests {

    @Test func dragResolverHonoursAxisLockAndThresholds() {
        let size = CGSize(width: 360, height: 600)
        #expect(DragResolver.target(dx: 8, dy: 4, cardSize: size) == nil)
        #expect(DragResolver.target(dx: 200, dy: 10, cardSize: size) == .next)
        #expect(DragResolver.target(dx: -200, dy: 10, cardSize: size) == .someday)
        // Up files nothing since the tiers merged into Someday (A3): the card springs back.
        #expect(DragResolver.target(dx: 10, dy: -200, cardSize: size) == nil)
        // Trash needs 40 % of the height, so 25 % is not enough.
        #expect(DragResolver.target(dx: 10, dy: 160, cardSize: size) == nil)
        #expect(DragResolver.target(dx: 10, dy: 260, cardSize: size) == .trash)
    }

    @Test func dragLocksOntoTheDominantAxis() {
        #expect(DragResolver.direction(dx: 5, dy: 5) == nil)              // below the 12 pt lock
        #expect(DragResolver.direction(dx: 30, dy: 12) == .right)
        #expect(DragResolver.direction(dx: -30, dy: 12) == .left)
        #expect(DragResolver.direction(dx: 12, dy: -30) == nil)
        #expect(DragResolver.direction(dx: 12, dy: 30) == .down)

        #expect(DragResolver.lockedTranslation(dx: 40, dy: 15) == CGSize(width: 40, height: 0))
        #expect(DragResolver.lockedTranslation(dx: 15, dy: 40) == CGSize(width: 0, height: 40))
    }

    @Test func commitmentReachesOneExactlyAtTheThreshold() {
        let size = CGSize(width: 400, height: 600)
        // 35 % of 400 = 140 pt.
        #expect(DragResolver.commitment(dx: 140, dy: 0, cardSize: size) == 1)
        #expect(DragResolver.commitment(dx: 70, dy: 0, cardSize: size) == 0.5)
        // Trash: 40 % of 600 = 240 pt.
        #expect(DragResolver.commitment(dx: 0, dy: 240, cardSize: size) == 1)
        #expect(DragResolver.commitment(dx: 0, dy: 0, cardSize: size) == 0)
    }

    @Test func everyTargetHasAKeyANameateSymbolAndThreeAreDirect() {
        #expect(CardTarget.allCases.count == 7)
        #expect(CardTarget.allCases.allSatisfy { !$0.key.isEmpty })
        #expect(CardTarget.allCases.allSatisfy { !$0.title.isEmpty })
        #expect(CardTarget.allCases.allSatisfy { !$0.symbol.isEmpty })
        #expect(CardTarget.allCases.count { $0.isDirect } == 3)
        #expect(CardTarget.allCases.filter(\.requiresWhat) == [.next, .someday])
    }

    @Test func swipeMapMatchesTheCommitmentAxis() {
        #expect(CardTarget.next.swipe == .right)
        #expect(CardTarget.someday.swipe == .left)
        #expect(CardTarget.trash.swipe == .down)
        for direction in SwipeDirection.allCases {
            #expect(KeyMap.target(for: direction).swipe == direction)
        }
    }

    @Test func macLegendReadsAsTheStyleGuideSpellsIt() {
        #expect(CardTarget.keyLegend
            == "← Someday  → Next  ↓ Trash    P Project · K Knowledge · W Waiting · R Review")
    }

    /// Every target is reachable without a swipe: four labelled buttons, three menu entries.
    @Test func theActionBarCoversEveryTargetExactlyOnce() {
        #expect(CardTarget.buttonTargets == [.project, .knowledge, .waiting, .deferToReview])
        #expect(CardTarget.buttonTargets.allSatisfy { !$0.isDirect })
        #expect(CardTarget.menuTargets == [.someday, .next, .trash])
        #expect(Set(CardTarget.buttonTargets + CardTarget.menuTargets) == Set(CardTarget.allCases))
        #expect(CardTarget.deferToReview.shortTitle == "Review")
        #expect(CardTarget.waiting.shortTitle == CardTarget.waiting.title)
    }

    @Test func letterKeysOpenTheSubFlows() {
        #expect(KeyMap.resolve("p") == .target(.project))
        #expect(KeyMap.resolve("P") == .target(.project))
        #expect(KeyMap.resolve("k") == .target(.knowledge))
        #expect(KeyMap.resolve("w") == .target(.waiting))
        #expect(KeyMap.resolve("r") == .target(.deferToReview))
        #expect(KeyMap.resolve("q") == nil)
    }

    @Test func digitsPickContextsAndShiftedDigitsPickTimeBuckets() {
        #expect(KeyMap.resolve("1") == .context(index: 0))
        #expect(KeyMap.resolve("8") == .context(index: 7))
        #expect(KeyMap.resolve("9") == nil)
        #expect(KeyMap.resolve("1", shift: true) == .time(.upTo10))
        #expect(KeyMap.resolve("4", shift: true) == .time(.over60))
        #expect(KeyMap.resolve("5", shift: true) == nil)
        // US layout sends the shifted character rather than the digit.
        #expect(KeyMap.resolve("!") == .time(.upTo10))
        #expect(KeyMap.resolve("$") == .time(.over60))
    }

    @Test func undoAndQuitAreReachable() {
        #expect(KeyMap.resolve("z", command: true) == .undo)
        #expect(KeyMap.resolve("Z", command: true) == .undo)
        #expect(KeyMap.resolve("z") != .undo)
        #expect(KeyMap.resolve("x", command: true) == nil)
        #expect(KeyMap.resolve("\u{1B}") == .quit)
    }
}

/// The sub-flow data: folder tree, project grouping, checklist text.
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

    @Test func projectsAreGroupedByAreaWithUngroupedFirst() {
        var snapshot = Fixtures.sampleSnapshot
        let loose = Project(
            id: NoteID(path: "Projects/Umzug/Umzug.md"), title: "Umzug", area: nil, status: .active)
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

    @Test func titleComesFromTheFirstContentLine() {
        #expect(ChecklistText.firstContentLine("- [ ] Ring them\n- [ ] Note it") == "Ring them")
        #expect(ChecklistText.firstContentLine("\n\n  Ring them") == "Ring them")
        #expect(ChecklistText.firstContentLine("- Ring them") == "Ring them")
        #expect(ChecklistText.firstContentLine("") == "")
        #expect(ChecklistText.firstContentLine("- [ ]    \nNote it") == "Note it")
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
