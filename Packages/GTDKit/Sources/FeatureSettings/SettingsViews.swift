#if canImport(SwiftUI)
import SwiftUI
import UniformTypeIdentifiers
import GTDModel
import GTDAppCore
import DesignSystem
import GTDFixtures
#if canImport(UserNotifications)
import UserNotifications
#endif
#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// First run: explain what to pick, pick it, show a validation preview, ask for notifications,
/// then hint at the capture Shortcut. Returns a plain `URL` — this target must not import
/// `GTDVault`; the app shell turns it into a `VaultBookmark`.
///
/// The validation preview and the rest of onboarding read `@Environment(AppModel.self)` (the
/// same pattern `SettingsView` uses) rather than a second closure: once the shell hands the
/// picked `URL` to `VaultBookmark`/`GTDServices` and mounts a real `AppModel`, this view's next
/// steps see the loaded snapshot for free.
public struct OnboardingView: View {
    private let onVaultPicked: (URL) -> Void
    private let onCreateVault: ((URL, String) async -> String?)?
    private let onFinished: (() -> Void)?
    @Environment(AppModel.self) private var model
    @State private var isPickerPresented = false
    /// What the one folder picker is for (#60): an existing vault, or where a new one goes.
    /// One `.fileImporter` per view — SwiftUI does not reliably present two on the same view.
    @State private var pickerPurpose: PickerPurpose = .existingVault
    @State private var step: Step = .welcome
    @State private var newVaultName = SettingsCopy.newVaultDefaultName
    /// Why the last "Create new vault" was refused (#60) — shown under the field, the person
    /// picks again. Nothing was written when this is set.
    @State private var createRefusal: String?
    @State private var isCreating = false

    private enum Step { case welcome, create, validate, notifications, shortcut }
    private enum PickerPurpose { case existingVault, newVaultLocation }

    /// `onFinished` (T40-1, defaulted so the frozen one-argument form still compiles) is how the
    /// shell learns that the last step has been read: onboarding is presented by the shell, so
    /// only the shell can take it down.
    ///
    /// `onCreateVault` (#60) creates `<location>/<name>` with the vault's folder skeleton and
    /// opens it; it returns `nil` on success or the reason it refused (a non-empty folder, …),
    /// which the create step shows so the person can pick again. `nil` hides "Create new vault".
    public init(
        onVaultPicked: @escaping (URL) -> Void,
        onCreateVault: ((URL, String) async -> String?)? = nil,
        onFinished: (() -> Void)? = nil
    ) {
        self.onVaultPicked = onVaultPicked
        self.onCreateVault = onCreateVault
        self.onFinished = onFinished
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            switch step {
            case .welcome: welcomeStep
            case .create: createStep
            case .validate: validateStep
            case .notifications: notificationsStep
            case .shortcut: shortcutStep
            }
        }
        .padding(Spacing.screenMargin)
        .frame(maxWidth: Spacing.cardMaxWidth, alignment: .leading)
        .fileImporter(isPresented: $isPickerPresented, allowedContentTypes: [.folder]) { result in
            guard case let .success(url) = result else { return }
            switch pickerPurpose {
            case .existingVault:
                onVaultPicked(url)
                step = .validate
            case .newVaultLocation:
                createVault(in: url)
            }
        }
    }

    // MARK: Step 1 — explain and pick

    private var welcomeStep: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text("Pick your vault").font(Typo.screenTitle).foregroundStyle(Color.ink)
            Text("Choose the Obsidian folder that contains Actions/. The app reads and writes markdown files there — nothing else is touched.")
                .font(Typo.body)
                .foregroundStyle(Color.textSecondary)
            Button("Choose folder…") {
                pickerPurpose = .existingVault
                isPickerPresented = true
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.gtdAccent)
            if onCreateVault != nil {
                Text(SettingsCopy.newVaultOffer)
                    .font(Typo.meta)
                    .foregroundStyle(Color.textSecondary)
                Button(SettingsCopy.createNewVault) {
                    createRefusal = nil
                    step = .create
                }
                .buttonStyle(.bordered)
                .tint(Color.gtdAccent)
            }
        }
    }

    // MARK: Step 1b — create a new, empty vault (#60)

    private var createStep: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text(SettingsCopy.createVaultTitle).font(Typo.screenTitle).foregroundStyle(Color.ink)
            Text(SettingsCopy.createVaultExplanation)
                .font(Typo.body)
                .foregroundStyle(Color.textSecondary)
            TextField(SettingsCopy.newVaultNamePlaceholder, text: $newVaultName)
                .textFieldStyle(.roundedBorder)
                .onSubmit(chooseNewVaultLocation)
                // #94 — a typed name survives leaving onboarding (⌘Q, `Back`) and comes back.
                .keepsDraft(
                    $newVaultName, key: InputDraftKey.newVaultName, in: model.inputDrafts,
                    isEmpty: { InputDrafts.isBlank($0) || $0 == SettingsCopy.newVaultDefaultName })
            if let createRefusal {
                Text(createRefusal)
                    .font(Typo.meta)
                    .foregroundStyle(Color.signalAttention)
            }
            Button(SettingsCopy.chooseNewVaultLocation, action: chooseNewVaultLocation)
                .buttonStyle(.borderedProminent)
                .tint(Color.gtdAccent)
                .disabled(isCreating || newVaultName.trimmingCharacters(in: .whitespaces).isEmpty)
            Button(SettingsCopy.back) { step = .welcome }
                .buttonStyle(.plain)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private func chooseNewVaultLocation() {
        guard !isCreating, !newVaultName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        pickerPurpose = .newVaultLocation
        isPickerPresented = true
    }

    private func createVault(in location: URL) {
        guard let onCreateVault else { return }
        isCreating = true
        let name = newVaultName
        Task {
            let refusal = await onCreateVault(location, name)
            isCreating = false
            createRefusal = refusal
            if refusal == nil {
                model.inputDrafts.clear(InputDraftKey.newVaultName)
                step = .validate
            }
        }
    }

    // MARK: Step 2 — validation preview

    private var validateStep: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text("Looks like this").font(Typo.screenTitle).foregroundStyle(Color.ink)
            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text("\(model.snapshot.actions.count) actions found")
                Text("\(model.snapshot.projects.count) projects found")
                Text(model.snapshot.inbox.isEmpty
                    ? "Inbox is empty"
                    : "\(model.snapshot.inbox.count) item\(model.snapshot.inbox.count == 1 ? "" : "s") in Inbox")
            }
            .font(Typo.body)
            .foregroundStyle(Color.textSecondary)
            if !model.snapshot.issues.isEmpty {
                Text("\(model.snapshot.issues.count) file\(model.snapshot.issues.count == 1 ? "" : "s") need attention — see Vault issues in Settings.")
                    .font(Typo.meta)
                    .foregroundStyle(Color.signalAttention)
            }
            Button("Continue") { step = .notifications }
                .buttonStyle(.borderedProminent)
                .tint(Color.gtdAccent)
        }
    }

    // MARK: Step 3 — notification permission

    private var notificationsStep: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text("Stay on top of things").font(Typo.screenTitle).foregroundStyle(Color.ink)
            Text("Turn on notifications for due dates, follow-ups and routines. You can change this anytime in Settings.")
                .font(Typo.body)
                .foregroundStyle(Color.textSecondary)
            Button("Turn on notifications") { requestNotifications() }
                .buttonStyle(.borderedProminent)
                .tint(Color.gtdAccent)
            Button("Not now") { step = .shortcut }
                .buttonStyle(.plain)
                .foregroundStyle(Color.textSecondary)
        }
    }

    private func requestNotifications() {
        #if canImport(UserNotifications)
        Task {
            _ = try? await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            step = .shortcut
        }
        #else
        step = .shortcut
        #endif
    }

    // MARK: Step 4 — capture Shortcut hint

    private var shortcutStep: some View {
        VStack(alignment: .leading, spacing: Spacing.l) {
            Text("One more thing").font(Typo.screenTitle).foregroundStyle(Color.ink)
            Text("Install the capture Shortcut to add to your Inbox from anywhere — the share sheet, Siri, or the lock screen. See Shortcuts/README.md for the recipe.")
                .font(Typo.body)
                .foregroundStyle(Color.textSecondary)
            Text("You're set. Open Next or process your Inbox to get going.")
                .font(Typo.meta)
                .foregroundStyle(Color.textSecondary)
            if let onFinished {
                Button("Start", action: onFinished)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.gtdAccent)
            }
        }
    }
}

/// Synced settings go through `updateConfig`/`setRoutineTime`; device-local ones through the
/// binding. **Owned by T26.**
public struct SettingsView: View {
    @Binding private var deviceSettings: DeviceSettings
    private let onChangeVault: () -> Void
    @Environment(AppModel.self) private var model

    @State private var newContextName = ""
    @State private var renamingContext: String?
    @State private var renameText = ""
    @State private var pendingRemoval: String?
    /// O3 — the "Add a context" field had no way to dismiss the keyboard; a `.keyboard` toolbar
    /// Done button (the `ActionDetailView` pattern) plus interactive scroll dismissal fix that.
    @FocusState private var isAddContextFocused: Bool

    // MARK: Lists (L2, R-5)

    @State private var newListName = ""
    @State private var addListRefusal: String?
    @FocusState private var isAddListFocused: Bool
    @State private var renamingList: String?
    @State private var renameListText = ""
    @State private var renameListRefusal: String?
    @State private var pendingListRemoval: String?
    /// The list whose icon picker is open (L2).
    @State private var iconPickerList: IconPickerTarget?

    #if os(macOS)
    // MARK: Keyboard (R-10, N7, STYLEGUIDE §4.5) — Mac only

    @State private var recordingCommand: KeyCommand?
    @State private var keyRefusals: [KeyCommand: String] = [:]
    #endif

    public init(deviceSettings: Binding<DeviceSettings>, onChangeVault: @escaping () -> Void) {
        self._deviceSettings = deviceSettings
        self.onChangeVault = onChangeVault
    }

    public var body: some View {
        let session = SettingsSession(model: model)
        Form {
            contextsSection(session)
            onTheGoSection(session)
            listsSection(session)
            favouritesSection(session)
            nextCapSection(session)
            routinesSection(session)
            notificationsSection
            #if os(macOS)
            keyboardSection
            #endif
            vaultSection
            aboutSection
        }
        // macOS' default form style (`.columns`) lays every row out at full height and never
        // scrolls, so anything below the window's edge is unreachable. `.grouped` scrolls on
        // both platforms and is what STYLEGUIDE §4.4 asks for ("stock `Form` (grouped)").
        .formStyle(.grouped)
        #if os(iOS)
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button(Copy.done) { isAddContextFocused = false }
            }
        }
        #endif
        .confirmationDialog(
            "Remove context?",
            isPresented: Binding(
                get: { pendingRemoval != nil },
                set: { if !$0 { pendingRemoval = nil } }),
            presenting: pendingRemoval
        ) { context in
            Button("Remove", role: .destructive) {
                Task { try? await session.removeContext(context) }
                pendingRemoval = nil
            }
            Button("Cancel", role: .cancel) { pendingRemoval = nil }
        } message: { context in
            let count = session.affectedActionCount(for: context)
            Text("\(count) action\(count == 1 ? "" : "s") still use \"\(context)\". They keep the text; it just won't show as a chip.")
        }
        // L2/R-5: removing a list is undoable, but it takes every item with it — that bulk
        // consequence is why this one still asks first (ARCHITECTURE §6), unlike most undoable
        // actions in this app.
        .sheet(item: $iconPickerList) { target in
            ListIconPicker(
                listName: target.name,
                current: Symbols.list(named: target.name, icons: session.config.listIcons),
                builtIn: Symbols.list(named: target.name)
            ) { symbol in
                Task { try? await session.setListIcon(target.name, symbol: symbol) }
            }
            #if os(iOS)
            .presentationDetents([.medium, .large])
            #endif
        }
        .confirmationDialog(
            SettingsCopy.removeListTitle,
            isPresented: Binding(
                get: { pendingListRemoval != nil },
                set: { if !$0 { pendingListRemoval = nil } }),
            presenting: pendingListRemoval
        ) { list in
            Button(SettingsCopy.removeList, role: .destructive) {
                Task { try? await session.removeList(list) }
                pendingListRemoval = nil
            }
            Button(Copy.cancel, role: .cancel) { pendingListRemoval = nil }
        } message: { list in
            Text(SettingsCopy.removeListMessage(name: list, itemCount: session.itemCount(inList: list)))
        }
        .alert(
            "Rename context",
            isPresented: Binding(
                get: { renamingContext != nil },
                set: { if !$0 { renamingContext = nil } })
        ) {
            TextField("Name", text: $renameText)
            Button("Rename") {
                if let old = renamingContext {
                    let new = renameText
                    // #94 — the typed name stays kept until the rename went through; a
                    // refusal reaches the alert instead of vanishing.
                    Task {
                        if await model.report({ try await session.renameContext(old, to: new) }) {
                            model.inputDrafts.clear(InputDraftKey.settingsRenameContext(old))
                        }
                    }
                }
                renamingContext = nil
            }
            Button("Cancel", role: .cancel) {
                // The one deliberate discard (#94).
                if let old = renamingContext {
                    model.inputDrafts.clear(InputDraftKey.settingsRenameContext(old))
                }
                renamingContext = nil
            }
        }
        // #94 — Settings' name fields keep what was typed when Settings is left (a closed
        // window, another tab, ⌘Q) and show it again; a rename's draft comes back when the same
        // context or list is renamed again. Only `Cancel` discards.
        .keepsDraft($newContextName, key: InputDraftKey.settingsNewContext, in: model.inputDrafts)
        .keepsDraft($newListName, key: InputDraftKey.settingsNewList, in: model.inputDrafts)
        .keepsDraft(
            $renameText, key: renamingContext.map(InputDraftKey.settingsRenameContext),
            in: model.inputDrafts, isEmpty: { [renamingContext] in InputDrafts.isBlank($0) || $0 == renamingContext })
        .keepsDraft(
            $renameListText, key: renamingList.map(InputDraftKey.settingsRenameList),
            in: model.inputDrafts, isEmpty: { [renamingList] in InputDrafts.isBlank($0) || $0 == renamingList })
    }

    // MARK: Contexts (A4)

    @ViewBuilder
    private func contextsSection(_ session: SettingsSession) -> some View {
        Section {
            #if os(iOS)
            // iPhone (walkthrough 2026-09-19, P18): four text buttons per row were cramped and
            // tiny. Stock list editing instead — `Edit` in the header shows the drag handles and
            // delete controls, a swipe offers Rename / Remove.
            ForEach(session.config.contexts, id: \.self) { context in
                Text(context).font(Typo.body).foregroundStyle(Color.ink)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            requestRemoval(session, of: context)
                        } label: {
                            Label("Remove", systemImage: Symbols.trash)
                        }
                        Button {
                            beginRenaming(context)
                        } label: {
                            Label("Rename", systemImage: Symbols.rename)
                        }
                        .tint(Color.gtdAccent)
                    }
            }
            .onMove { offsets, destination in
                Task { try? await session.reorderContexts(from: offsets, to: destination) }
            }
            .onDelete { offsets in
                for context in offsets.map({ session.config.contexts[$0] }) {
                    requestRemoval(session, of: context)
                }
            }
            #else
            ForEach(Array(session.config.contexts.enumerated()), id: \.offset) { index, context in
                contextRow(session, index: index, context: context, count: session.config.contexts.count)
            }
            #endif
            HStack {
                TextField("Add a context", text: $newContextName)
                    .focused($isAddContextFocused)
                    .submitLabel(.done)
                    .onSubmit { isAddContextFocused = false }
                Button("Add") {
                    let name = newContextName
                    // #94 — the field empties once the context exists; a refusal keeps the
                    // name and reaches the alert.
                    Task {
                        guard await model.report({ try await session.addContext(name) }) else { return }
                        if newContextName == name { newContextName = "" }
                    }
                }
                .disabled(newContextName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: {
            #if os(iOS)
            HStack {
                Text("Contexts")
                Spacer()
                EditButton().font(Typo.meta).textCase(nil)
            }
            #else
            Text("Contexts")
            #endif
        } footer: {
            Text("Removing a context in use asks first; it never rewrites existing actions.")
        }
    }

    /// A4: removing a context that actions still use asks first; an unused one goes at once.
    private func requestRemoval(_ session: SettingsSession, of context: String) {
        if session.affectedActionCount(for: context) > 0 {
            pendingRemoval = context
        } else {
            Task { try? await session.removeContext(context) }
        }
    }

    private func beginRenaming(_ context: String) {
        renameText = context
        renamingContext = context
    }

    #if !os(iOS)
    private func contextRow(_ session: SettingsSession, index: Int, context: String, count: Int) -> some View {
        HStack(spacing: Spacing.s) {
            Text(context).font(Typo.body).foregroundStyle(Color.ink)
            Spacer()
            Button("Up") { moveContext(session, at: index, up: true) }
                .disabled(index == 0)
            Button("Down") { moveContext(session, at: index, up: false) }
                .disabled(index == count - 1)
            Button("Rename") { beginRenaming(context) }
            Button {
                requestRemoval(session, of: context)
            } label: {
                Image(systemName: Symbols.trash)
            }
            .accessibilityLabel("Remove \(context)")
        }
        .buttonStyle(.plain)
        .font(Typo.meta)
        .foregroundStyle(Color.gtdAccent)
    }

    private func moveContext(_ session: SettingsSession, at index: Int, up: Bool) {
        let destination = up ? index - 1 : index + 2
        Task { try? await session.reorderContexts(from: IndexSet(integer: index), to: destination) }
    }
    #endif

    // MARK: On-the-go subset (A4, N5)

    @ViewBuilder
    private func onTheGoSection(_ session: SettingsSession) -> some View {
        Section {
            ContextChipGroup(
                contexts: session.config.contexts,
                selection: Binding(
                    get: { session.config.onTheGoContexts },
                    set: { newValue in
                        let changed = Set(newValue).symmetricDifference(session.config.onTheGoContexts)
                        for context in changed {
                            Task { try? await session.toggleOnTheGo(context) }
                        }
                    }))
        } header: {
            Text("On the go")
        } footer: {
            Text("These contexts make up the iPhone's on-the-go Next list.")
        }
    }

    // MARK: Lists (L2, R-5)

    @ViewBuilder
    private func listsSection(_ session: SettingsSession) -> some View {
        Section {
            ForEach(session.listRows, id: \.list.id) { row in
                if renamingList == row.list.name {
                    renamingListRow(session, name: row.list.name)
                } else {
                    listRow(session, row: row)
                }
            }
            VStack(alignment: .leading, spacing: Spacing.xs) {
                HStack {
                    TextField(SettingsCopy.addList, text: $newListName)
                        .focused($isAddListFocused)
                        .submitLabel(.done)
                        .onSubmit { addList(session) }
                    Button("Add") { addList(session) }
                        .disabled(newListName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let addListRefusal {
                    Text(addListRefusal).font(Typo.meta).foregroundStyle(Color.signalAttention)
                }
            }
        } header: {
            Text(Copy.lists)
        } footer: {
            Text("Each list is a folder. Removing one asks first — it takes its items with it.")
        }
    }

    private func listRow(_ session: SettingsSession, row: Rules.ListRow) -> some View {
        HStack(spacing: Spacing.s) {
            listIconButton(session, name: row.list.name)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.list.name).font(Typo.body).foregroundStyle(Color.ink)
                Text(Copy.counter(remaining: row.openCount, total: row.openCount + row.finishedCount))
                    .font(Typo.meta)
                    .foregroundStyle(Color.textSecondary)
            }
            Spacer()
            Button {
                renameListText = row.list.name
                renamingList = row.list.name
                renameListRefusal = nil
            } label: {
                Image(systemName: Symbols.rename)
            }
            Button(role: .destructive) {
                pendingListRemoval = row.list.name
            } label: {
                Image(systemName: Symbols.trash)
            }
            .accessibilityLabel("\(SettingsCopy.removeList) \(row.list.name)")
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.gtdAccent)
        #if os(iOS)
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) { pendingListRemoval = row.list.name } label: {
                Label(SettingsCopy.removeList, systemImage: Symbols.trash)
            }
            Button {
                renameListText = row.list.name
                renamingList = row.list.name
                renameListRefusal = nil
            } label: {
                Label("Rename", systemImage: Symbols.rename)
            }
            .tint(Color.gtdAccent)
        }
        #endif
    }

    /// The row turns into its own inline editor while renamed — refusals show here, never as an
    /// alert (STYLEGUIDE §4.3/T13).
    private func renamingListRow(_ session: SettingsSession, name: String) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack(spacing: Spacing.s) {
                listIconButton(session, name: name)
                    .buttonStyle(.plain)
                TextField(Copy.list, text: $renameListText)
                    .onSubmit { commitRename(session, from: name) }
            }
            if let renameListRefusal {
                Text(renameListRefusal).font(Typo.meta).foregroundStyle(Color.signalAttention)
            }
            HStack {
                Button(Copy.cancel) {
                    // The one deliberate discard (#94).
                    model.inputDrafts.clear(InputDraftKey.settingsRenameList(name))
                    renamingList = nil
                    renameListRefusal = nil
                }
                Spacer()
                Button("Save") { commitRename(session, from: name) }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.gtdAccent)
            }
        }
    }

    /// The list's icon, tappable: it opens `ListIconPicker` (L2). Same button in the plain row
    /// and in the rename editor, so the icon can be changed either way.
    private func listIconButton(_ session: SettingsSession, name: String) -> some View {
        Button {
            iconPickerList = IconPickerTarget(name: name)
        } label: {
            Image(systemName: Symbols.list(named: name, icons: session.config.listIcons))
                .foregroundStyle(Color.gtdAccent)
                .frame(minWidth: 28, minHeight: 28)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(SettingsCopy.chooseListIcon(name))
    }

    private func addList(_ session: SettingsSession) {
        let name = newListName
        Task {
            do {
                try await session.createList(name)
                newListName = ""
                addListRefusal = nil
            } catch let error as GTDError {
                addListRefusal = SettingsCopy.message(for: error)
            } catch {
                addListRefusal = Copy.actionFailed
            }
        }
    }

    private func commitRename(_ session: SettingsSession, from old: String) {
        let new = renameListText
        Task {
            do {
                try await session.renameList(old, to: new)
                model.inputDrafts.clear(InputDraftKey.settingsRenameList(old))
                renamingList = nil
                renameListRefusal = nil
            } catch let error as GTDError {
                renameListRefusal = SettingsCopy.message(for: error)
            } catch {
                renameListRefusal = Copy.actionFailed
            }
        }
    }

    // MARK: Favourites (I4b, R-5)

    @ViewBuilder
    private func favouritesSection(_ session: SettingsSession) -> some View {
        Section {
            #if os(iOS)
            ForEach(Array(session.favouriteListNames.enumerated()), id: \.element) { index, name in
                favouriteRow(name: name, index: index)
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            Task { try? await session.toggleFavourite(name) }
                        } label: {
                            Label(SettingsCopy.removeList, systemImage: Symbols.trash)
                        }
                    }
            }
            .onMove { offsets, destination in
                Task { try? await session.reorderFavourites(from: offsets, to: destination) }
            }
            #else
            ForEach(Array(session.favouriteListNames.enumerated()), id: \.element) { index, name in
                HStack(spacing: Spacing.s) {
                    favouriteRow(name: name, index: index)
                    Spacer()
                    Button("Up") { moveFavourite(session, at: index, up: true) }
                        .disabled(index == 0)
                    Button("Down") { moveFavourite(session, at: index, up: false) }
                        .disabled(index == session.favouriteListNames.count - 1)
                    Button {
                        Task { try? await session.toggleFavourite(name) }
                    } label: {
                        Image(systemName: Symbols.trash)
                    }
                    .accessibilityLabel("\(SettingsCopy.removeList) \(name)")
                }
                .buttonStyle(.plain)
                .font(Typo.meta)
                .foregroundStyle(Color.gtdAccent)
            }
            #endif
            if session.favouriteListNames.count < ListsEditing.storageLimit {
                Menu(SettingsCopy.addFavourite) {
                    ForEach(session.listsAvailableToFavourite, id: \.self) { name in
                        Button(name) { Task { try? await session.toggleFavourite(name) } }
                    }
                }
                .disabled(session.listsAvailableToFavourite.isEmpty)
            } else {
                Text(SettingsCopy.favouritesFull(ListsEditing.storageLimit))
                    .font(Typo.meta)
                    .foregroundStyle(Color.textSecondary)
            }
        } header: {
            Text(SettingsCopy.favourites)
        } footer: {
            Text(SettingsCopy.favouritesFooter)
        }
    }

    private func favouriteRow(name: String, index: Int) -> some View {
        HStack(spacing: Spacing.s) {
            Image(systemName: Symbols.list(named: name, icons: model.snapshot.config.listIcons))
                .foregroundStyle(Color.textSecondary)
            Text(name).font(Typo.body).foregroundStyle(Color.ink)
            if !ListsEditing.isShownOnPhone(index: index) {
                Text(SettingsCopy.macOnlyFavourite)
                    .font(Typo.meta)
                    .foregroundStyle(Color.textSecondary)
            }
        }
    }

    #if !os(iOS)
    private func moveFavourite(_ session: SettingsSession, at index: Int, up: Bool) {
        let destination = up ? index - 1 : index + 2
        Task { try? await session.reorderFavourites(from: IndexSet(integer: index), to: destination) }
    }
    #endif

    // MARK: Next cap (A3)

    @ViewBuilder
    private func nextCapSection(_ session: SettingsSession) -> some View {
        Section {
            Stepper(
                "Next cap: \(session.config.nextCap)",
                value: Binding(
                    get: { session.config.nextCap },
                    set: { newValue in Task { try? await session.setNextCap(newValue) } }),
                in: NextCapPolicy.minimum...999)
            if NextCapPolicy.showsRaisedWarning(session.config.nextCap) {
                Text("A higher cap makes Next less focused.")
                    .font(Typo.meta)
                    .foregroundStyle(Color.textSecondary)
            }
        } header: {
            Text(Copy.next)
        }
    }

    // MARK: Routine times (R3)

    @ViewBuilder
    private func routinesSection(_ session: SettingsSession) -> some View {
        Section {
            ForEach(session.routines) { routine in
                RoutineTimeRow(routine: routine, session: session)
            }
        } header: {
            Text(Copy.routine)
        }
    }

    #if os(macOS)
    // MARK: Keyboard (R-10, N7, STYLEGUIDE §4.5) — Mac only; the model itself is not.

    private var keyboardSection: some View {
        Section {
            ForEach(KeyBindingsEditing.screens, id: \.screen) { screen, commands in
                Text(SettingsCopy.screenTitle(screen))
                    .font(Typo.meta)
                    .foregroundStyle(Color.textSecondary)
                    .padding(.top, Spacing.xs)
                ForEach(commands, id: \.self) { command in
                    keyRow(command)
                }
            }
            Button(SettingsCopy.resetToDefaults) {
                deviceSettings.keyBindings.reset()
                keyRefusals.removeAll()
                recordingCommand = nil
            }
            .foregroundStyle(Color.gtdAccent)
        } header: {
            Text(SettingsCopy.keyboardSection)
        } footer: {
            Text(SettingsCopy.keyboardFooter)
        }
    }

    private func keyRow(_ command: KeyCommand) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            HStack {
                Text(SettingsCopy.commandTitle(command)).font(Typo.body).foregroundStyle(Color.ink)
                Spacer()
                keyRecorder(command)
            }
            if let refusal = keyRefusals[command] {
                Text(refusal).font(Typo.meta).foregroundStyle(Color.signalAttention)
            }
        }
    }

    /// Captures one key press (STYLEGUIDE §4.5's "key-recorder field"). Tapping starts recording;
    /// the next key press attempts the rebind and shows any refusal inline on the row above.
    private func keyRecorder(_ command: KeyCommand) -> some View {
        let isRecording = recordingCommand == command
        return Button {
            recordingCommand = isRecording ? nil : command
            keyRefusals[command] = nil
        } label: {
            Text(isRecording ? SettingsCopy.pressAKey : deviceSettings.keyBindings.key(for: command).display)
                .font(Typo.meta)
                .frame(minWidth: 72)
        }
        .buttonStyle(.bordered)
        .tint(isRecording ? Color.gtdAccent : Color.textSecondary)
        .onKeyPress(.leftArrow) { attemptRebind(command, to: .arrowLeft, isRecording: isRecording) }
        .onKeyPress(.rightArrow) { attemptRebind(command, to: .arrowRight, isRecording: isRecording) }
        .onKeyPress(.escape) { attemptRebind(command, to: .escape, isRecording: isRecording) }
        .onKeyPress(phases: .down) { press in
            guard isRecording, let character = press.characters.first,
                  let stroke = KeyBindingsEditing.stroke(forCharacter: character)
            else { return .ignored }
            return attemptRebind(command, to: stroke, isRecording: isRecording)
        }
    }

    private func attemptRebind(_ command: KeyCommand, to stroke: KeyStroke, isRecording: Bool) -> KeyPress.Result {
        guard isRecording else { return .ignored }
        switch KeyBindingsEditing.rebinding(command, to: stroke, in: deviceSettings.keyBindings) {
        case let .success(next):
            deviceSettings.keyBindings = next
            keyRefusals[command] = nil
        case let .failure(error):
            keyRefusals[command] = SettingsCopy.message(for: error)
        }
        recordingCommand = nil
        return .handled
    }
    #endif

    // MARK: Device-local (D2, notifications + morning time)

    private var notificationsSection: some View {
        Section {
            ForEach(NotificationKindOption.allCases) { option in
                Toggle(
                    option.label,
                    isOn: Binding(
                        get: { deviceSettings.notificationKinds[option.rawValue] ?? true },
                        set: { deviceSettings.notificationKinds[option.rawValue] = $0 }))
            }
            DatePicker(
                "Morning time",
                selection: Binding(
                    get: { deviceSettings.morningTime.asDate },
                    set: { deviceSettings.morningTime = DayTime($0) }),
                displayedComponents: .hourAndMinute)
        } header: {
            Text("Notifications")
        }
    }

    private var vaultSection: some View {
        Section {
            if let name = deviceSettings.vaultDisplayName {
                LabeledContent("Vault", value: name)
            }
            Button("Change vault…", action: onChangeVault)
        } header: {
            Text("Vault")
        } footer: {
            Text(SettingsCopy.changeVaultFooter)
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Self.appVersion)
            Text("A personal GTD app over a plain-markdown Obsidian vault.")
                .font(Typo.meta)
                .foregroundStyle(Color.textSecondary)
        } header: {
            Text("About")
        }
    }

    /// `AppVersion` reads the bundle; an unversioned bundle shows an empty row, not "1.0".
    private static var appVersion: String { AppVersion.current.settingsLabel }
}

/// One routine's schedule (R1, R3): an on/off toggle plus a time picker while on. Turning it on
/// commits an explicit, user-chosen starting time immediately — the same "tap to confirm" rule
/// `DateValueChip` uses elsewhere, not a silently-written default.
private struct RoutineTimeRow: View {
    let routine: Routine
    let session: SettingsSession

    @State private var isScheduled: Bool
    @State private var time: Date

    init(routine: Routine, session: SettingsSession) {
        self.routine = routine
        self.session = session
        _isScheduled = State(initialValue: routine.time != nil)
        _time = State(initialValue: (routine.time ?? DayTime(hour: 7, minute: 0)).asDate)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            Toggle(routine.title, isOn: $isScheduled)
                .onChange(of: isScheduled) { _, on in
                    Task { try? await session.setRoutineTime(routine.id, to: on ? DayTime(time) : nil) }
                }
            if isScheduled {
                DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .onChange(of: time) { _, newValue in
                        Task { try? await session.setRoutineTime(routine.id, to: DayTime(newValue)) }
                    }
            }
        }
    }
}

/// Files the app refuses to guess about (N3 §7). **Owned by T26.**
public struct VaultIssuesView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.vaultRootPath) private var vaultRootPath
    @Environment(\.openURL) private var openURL

    public init() {}

    public var body: some View {
        List {
            if model.snapshot.issues.isEmpty {
                ContentUnavailableView("No issues", systemImage: Symbols.done)
            } else {
                ForEach(Array(model.snapshot.issues.enumerated()), id: \.offset) { _, issue in
                    VStack(alignment: .leading, spacing: Spacing.xs) {
                        Text(issue.path).font(Typo.body).foregroundStyle(Color.ink)
                        Text(issue.message).font(Typo.meta).foregroundStyle(Color.textSecondary)
                        HStack(spacing: Spacing.l) {
                            Button("Reveal") { reveal(issue.path) }
                            if let url = ObsidianLink.url(forVaultPath: issue.path, vaultRoot: vaultRootPath) {
                                Button("Open in Obsidian") { openURL(url) }
                            }
                        }
                        .buttonStyle(.plain)
                        .font(Typo.meta)
                        .foregroundStyle(Color.gtdAccent)
                    }
                    .padding(.vertical, Spacing.xs)
                }
            }
        }
        .navigationTitle("Vault issues")
    }

    /// `issue.path` is vault-relative; Finder needs the absolute path, resolved against the root
    /// the shell hands down (`\.vaultRootPath`).
    private func reveal(_ path: String) {
        #if canImport(AppKit)
        guard let file = ObsidianLink.filePath(forVaultPath: path, vaultRoot: vaultRootPath) else { return }
        NSWorkspace.shared.selectFile(file, inFileViewerRootedAtPath: "")
        #endif
        // No Files-app equivalent on iOS without a resolvable URL.
    }
}

#Preview("Onboarding") {
    OnboardingView(onVaultPicked: { _ in }, onCreateVault: { _, _ in nil })
        .environment(AppModel(
            backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
            snapshot: Fixtures.sampleSnapshot,
            today: { Fixtures.today }))
}

#Preview("Onboarding — dark") {
    OnboardingView(onVaultPicked: { _ in }, onCreateVault: { _, _ in nil })
        .environment(AppModel(
            backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
            snapshot: Fixtures.sampleSnapshot,
            today: { Fixtures.today }))
        .preferredColorScheme(.dark)
}

#Preview("Onboarding — AX1") {
    OnboardingView(onVaultPicked: { _ in }, onCreateVault: { _, _ in nil })
        .environment(AppModel(
            backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
            snapshot: Fixtures.sampleSnapshot,
            today: { Fixtures.today }))
        .dynamicTypeSize(.accessibility1)
}

#Preview("Settings") {
    @Previewable @State var settings = DeviceSettings.default
    return NavigationStack {
        SettingsView(deviceSettings: $settings, onChangeVault: {})
    }
    .environment(AppModel(
        backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
        snapshot: Fixtures.sampleSnapshot,
        today: { Fixtures.today }))
}

#Preview("Settings — dark") {
    @Previewable @State var settings = DeviceSettings.default
    return NavigationStack {
        SettingsView(deviceSettings: $settings, onChangeVault: {})
    }
    .environment(AppModel(
        backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
        snapshot: Fixtures.sampleSnapshot,
        today: { Fixtures.today }))
    .preferredColorScheme(.dark)
}

#Preview("Settings — AX1") {
    @Previewable @State var settings = DeviceSettings.default
    return NavigationStack {
        SettingsView(deviceSettings: $settings, onChangeVault: {})
    }
    .environment(AppModel(
        backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
        snapshot: Fixtures.sampleSnapshot,
        today: { Fixtures.today }))
    .dynamicTypeSize(.accessibility1)
}

#Preview("Vault issues") {
    NavigationStack {
        VaultIssuesView()
    }
    .environment(AppModel(
        backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
        snapshot: Fixtures.sampleSnapshot,
        today: { Fixtures.today }))
}

#Preview("Vault issues — dark") {
    NavigationStack {
        VaultIssuesView()
    }
    .environment(AppModel(
        backend: InMemoryBackend(snapshot: Fixtures.sampleSnapshot),
        snapshot: Fixtures.sampleSnapshot,
        today: { Fixtures.today }))
    .preferredColorScheme(.dark)
}

#Preview("Vault issues — empty") {
    NavigationStack {
        VaultIssuesView()
    }
    .environment(AppModel(
        backend: InMemoryBackend(snapshot: .empty),
        snapshot: .empty,
        today: { Fixtures.today }))
}

/// `sheet(item:)` needs an `Identifiable`; a list is identified by its name.
private struct IconPickerTarget: Identifiable {
    let name: String
    var id: String { name }
}

#endif
