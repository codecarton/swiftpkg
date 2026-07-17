# Swiftpkgr implementation plan

## Goal

Add **Swiftpkgr**, a native SwiftUI frontend for `swiftpkg`, without replacing or weakening the existing command-line tool.

Swiftpkgr will:

- create and open `swiftpkg` project directories;
- expose every package configuration field supported by the CLI build path;
- import existing installer packages into projects;
- build packages, export BOM metadata, and synchronize from `Bom.txt`;
- import arbitrary plist or JSON settings files to prefill the editor;
- export editor settings as CLI-compatible plist or JSON files;
- continue to recognize CLI-created plist, JSON, YAML, and YML project files; and
- share the configuration, persistence, validation, import, build, and BOM implementation with `swiftpkg`.

The existing `swiftpkg` executable will continue to support macOS 13 and later. Swiftpkgr will require macOS 15 or later and Swift 6.2 or later.

## Product and technical decisions

1. **One core, two frontends.** Extract reusable code into a `SwiftPkgCore` static library. The `swiftpkg` and `Swiftpkgr` targets will translate their inputs into the same core request and configuration types.
2. **Preserve compatibility at the boundary.** Keep every existing CLI flag and on-disk key, including `product id`, `min-os-version`, `large-payload`, `signing_info`, and `notarization_info`.
3. **Do not couple the core to SwiftUI.** SwiftUI views and observable editor state belong only to the app target. Core models remain Foundation-based, testable, and usable by the macOS 13 CLI.
4. **Use explicit saves.** Editing updates an in-memory draft. Save writes the project's existing build-info format; Build validates and saves before running. Unsaved changes are confirmed before closing or replacing a project.
5. **Keep template and resolved values separate.** Editor import/export preserves strings such as `Package-${version}.pkg`. Version substitution happens only when producing a build configuration.
6. **Support CLI project formats, limit standalone exchange formats.** Open and save project-local plist, JSON, YAML, and YML files. The dedicated Import Settings and Export Settings actions accept plist and JSON, as requested.
7. **Use native macOS UI and no third-party UI frameworks.** SwiftUI is the default. Any unavoidable AppKit file-panel behavior is isolated behind a small service rather than leaking into feature views.
8. **Ship outside the Mac App Store initially.** Enable Hardened Runtime but leave App Sandbox disabled because the app must work with arbitrary project trees, invoke Apple package tools, and access signing resources. Revisit sandboxing only with a deliberate security-scoped bookmark and helper-tool design.
9. **Do not add privilege escalation in the first release.** Match current CLI behavior: warn when ownership operations require root. Swiftpkgr will not ask for an administrator password or install a privileged helper.

## Capability parity

| CLI capability | Swiftpkgr experience | Shared implementation |
| --- | --- | --- |
| Build a project | Open Project, edit, then Build | `PackageBuildCoordinator` through a core operation service |
| `--create` | New Project | `ProjectCreator` |
| `--force` | Convert Existing Folder, with destructive-impact confirmation | `ProjectCreator(force:)` |
| `--import PKG` | Import Package | `PackageImporter` |
| `--json` / `--yaml` | Format picker when creating/importing a project | `BuildInfoFormat` / `BuildInfoStore` |
| `--export-bom-info` | Export BOM after build toggle | Core build options |
| `--sync` | Synchronize from Bom command | `BOMMetadataService` |
| `--quiet` | Not exposed as a user preference; the app always shows structured progress | Shared reporter can suppress or emit events per frontend |
| `--skip-signing` | Skip Signing build toggle | Core build options |
| `--skip-notarization` | Skip Notarization build toggle | Core build options |
| `--skip-stapling` | Skip Stapling build toggle | Core build options |
| `--help` | Help menu and field help | App help content |
| `--version` | About Swiftpkgr | Shared version constant |

The editor must cover all current configuration values:

- name, identifier, version, install location;
- ownership, compression, minimum OS version, large payload;
- post-install action, preserve extended attributes, suppress bundle relocation;
- distribution style, title, and product identifier;
- signing identity, keychain, additional certificate names, and timestamp behavior; and
- notarization authentication, keychain profile or Apple ID credentials, and staple timeout.

## Target and source layout

Use feature-oriented directories and one primary type per Swift file.

```text
Sources/
  SwiftPkgCore/
    Configuration/
      PackageConfiguration.swift
      PackageSettingsDraft.swift
      BuildInfoFormat.swift
      BuildInfoStore.swift
      ConfigurationValidation.swift
    Operations/
      PackageOperationService.swift
      PackageBuildOptions.swift
      ProjectCreator.swift
      PackageImporter.swift
      PackageBuilder.swift
      BOMMetadataService.swift
    Process/
      ProcessRunning.swift
      SystemProcessRunner.swift
      PackageEvent.swift
      PackageEventReporting.swift
    Support/
      FileManager+ProjectSupport.swift
      MunkiPkgError.swift
      Version.swift
  swiftpkg/
    CLI.swift
    CLICommand.swift
    ConsoleReporter.swift
    SwiftPkg.swift
    main.swift
  Swiftpkgr/
    App/
      SwiftpkgrApp.swift
      SwiftpkgrCommands.swift
    Project/
      ProjectEditorModel.swift
      ProjectEditorView.swift
      ProjectSection.swift
    Welcome/
      WelcomeView.swift
    Configuration/
      GeneralSettingsView.swift
      PackageBehaviorView.swift
      DistributionSettingsView.swift
      SigningSettingsView.swift
      NotarizationSettingsView.swift
    Contents/
      ProjectContentsView.swift
    Build/
      BuildOptionsView.swift
      BuildProgressView.swift
    Files/
      ProjectPanelService.swift
      SettingsTransferService.swift
    Support/
      AppErrorPresentation.swift
      DesignMetrics.swift
Tests/
  SwiftPkgCoreTests/
  SwiftPkgCLITests/
SwiftpkgrTests/
SwiftpkgrUITests/
```

Use these target graphs:

```text
Package.swift
SwiftPkgCore (static library, macOS 13+)
└── swiftpkg (command-line executable, macOS 13+)

swiftpkg.xcodeproj
SwiftPkgCore (static library, macOS 13+)
├── swiftpkg (command-line executable, macOS 13+)
└── Swiftpkgr (application bundle, macOS 15+)
```

Do not add the shipping app as a SwiftPM executable product. SwiftPM has a package-wide deployment declaration and does not produce the signed macOS application bundle this project needs. `Package.swift` remains the source-of-truth build for Core/CLI and their tests; the Xcode project adds the macOS 15 app and its unit/UI tests while keeping Core/CLI source membership and dependencies aligned with SwiftPM.

- `SwiftPkgCore` depends on Yams.
- `swiftpkg` depends on `SwiftPkgCore` and ArgumentParser.
- `Swiftpkgr` depends on `SwiftPkgCore` and SwiftUI only.
- Keep the core static so the installed CLI remains a standalone executable without an adjacent dynamic framework.
- Add separate shared Xcode schemes for `SwiftPkgCore`, `swiftpkg`, and `Swiftpkgr`.
- Correct the Xcode deployment settings so Core/CLI are macOS 13 and Swiftpkgr is macOS 15; do not inherit the current project-level macOS 26.5 value.
- Set Swift 6 language mode and complete concurrency checking. Use Main Actor default isolation only for the app target, not for Core or CLI.

## Core architecture changes

### 1. Separate editable and validated configuration

Retain `PackageConfiguration` as the validated, immutable value consumed by builders. Add `PackageSettingsDraft`, a mutable value with optional/text-friendly fields suitable for forms and lossless configuration-file editing.

The draft will provide:

- `init(configuration:)` and `validatedConfiguration()` mappings;
- field-specific validation errors for required names, identifiers, versions, timeouts, and mutually exclusive notarization authentication;
- stable mapping for every legacy wire key;
- `Equatable` conformance for dirty-state detection; and
- `Sendable` conformance where all members allow it.

Do not make a shared core model observable. `ProjectEditorModel` owns a draft and is an `@MainActor @Observable` app type; views own it with private `@State` and pass it using `@Bindable`.

### 2. Split file parsing from project discovery

Refactor `BuildInfoStore` into two layers:

- project discovery resolves `build-info.plist`, `.json`, `.yaml`, or `.yml` and rejects ambiguous projects; and
- file serialization reads or writes a specific URL and format.

Add APIs equivalent to:

```swift
loadTemplate(from:defaultsFor:)
loadResolvedConfiguration(fromProject:requestedFormat:)
writeTemplate(_:to:format:)
```

`loadTemplate` must not substitute `${version}`. `loadResolvedConfiguration` performs substitution for builds, preserving existing CLI behavior. Standalone settings imports may have any filename but must have a `.plist` or `.json` extension and a dictionary root.

Export must use the exact CLI-compatible schema and deterministic JSON output. Plist export uses XML. YAML/YML support remains in Core for existing CLI projects but is not offered by standalone Import/Export Settings.

### 3. Move frontend-neutral options into Core

Move `BuildConfiguration` out of `CLI.swift`, rename it to a frontend-neutral `PackageBuildOptions`, and keep these values:

- requested project format;
- export BOM;
- reporting verbosity;
- skip signing;
- skip notarization; and
- skip stapling.

The CLI parser maps flags into this type. Swiftpkgr maps build controls into the same type. Similar request values should represent create, package import, build, and BOM synchronization so neither frontend duplicates orchestration rules.

### 4. Replace console coupling with structured events

Replace direct `Console` and `FileHandle` writes in Core with a reporting abstraction that emits typed events such as status, warning, tool output, produced artifact, and failure. Keep `ConsoleReporter` in the CLI target and add an app reporter that updates build progress and an accessible log.

Errors remain typed and gain localized, user-actionable descriptions. Errors triggered by UI actions must be presented in alerts and never only printed or silently swallowed.

### 5. Make long-running operations concurrency-safe

Package import, build, BOM sync, and notarization must not block the Main Actor.

- Convert process execution and coordinating operations to `async throws` using Swift concurrency.
- Replace `Thread.sleep` in notarization polling with `Task.sleep(for:)`.
- Propagate cancellation and terminate an active child process where safe.
- Keep mutable operation state actor-isolated.
- Update the CLI entry point to await the same operations and preserve its exit codes and output behavior.
- Keep `RecordingRunner` as the hermetic test double, updated for async calls.

## Swiftpkgr user experience

### Welcome and project lifecycle

The first window presents four labeled actions:

1. **New Project** — choose a new project folder, derive defaults from its name, choose plist/JSON/YAML format, then open the editor.
2. **Open Project** — select an existing project directory and discover its build-info file.
3. **Import Package** — select a flat or bundle `.pkg`, choose a new destination and project format, run the shared importer, then open the result.
4. **Convert Existing Folder** — select an existing folder and confirm creation of the conventional project subdirectories, matching `--create --force` safeguards.

Recent-project persistence may be added after the main workflows are reliable. It must store only URLs/bookmarks, never signing or notarization credentials.

### Editor layout

Use `NavigationSplitView` with a sidebar rather than a large single form. Sidebar destinations are enum-backed and registered once.

- General
- Package Behavior
- Project Contents
- Distribution
- Signing
- Notarization
- Build

Each destination is a dedicated view file. Use `Form`, `Section`, `LabeledContent`, native pickers/toggles, and vertically growing `TextField`s where appropriate. Avoid fixed dimensions and custom scrolling. Use `ContentUnavailableView` when no project is open.

The toolbar and app commands provide text-labeled actions for Save, Import Settings, Export Settings, Build, Cancel, Synchronize BOM, Reveal Project, and Reveal Built Package. Keyboard commands should cover New, Open, Save, Build, and Close.

### Project contents

The CLI treats `payload/` and `scripts/` as project filesystem inputs, so the first UI release will show their presence and contents and provide Reveal in Finder/Open Folder actions. It will not invent a second payload model or duplicate files inside app storage.

The view must clearly distinguish:

- missing payload (payload-free package);
- present but empty payload (empty-payload receipt package);
- scripts-only package; and
- missing both payload and scripts (invalid build).

Drag-and-drop payload authoring can be a later feature after destination-path and conflict semantics are designed and tested.

### Settings import and export

**Import Settings** selects a plist or JSON file, decodes it using defaults derived from the current project, validates it, and replaces the in-memory draft after confirmation if there are unsaved edits. It does not overwrite the project file until Save.

**Export Settings** validates the current draft, asks for plist or JSON and a destination, and writes the template values without `${version}` substitution. Exporting Apple ID notarization credentials requires a warning that the CLI-compatible schema stores the password in plaintext; `SecureField` protects only on-screen display.

### Build and progress

Build validates and saves the active draft, presents build-only toggles, then runs the shared operation. The UI shows:

- current stage and cancellable progress;
- warnings separately from routine messages, with icon/text rather than color alone;
- an accessible, selectable event log; and
- success actions to reveal the `.pkg` and project build folder.

Only one mutating operation may run for a project at a time. Disable conflicting controls while it runs. Closing a window with an active operation requires confirmation.

### Accessibility and macOS conventions

- Use semantic system fonts and flexible form layouts so macOS text-size settings do not clip fields.
- Give every icon button a text label, even when a toolbar renders it icon-only.
- Support full keyboard navigation, standard commands, VoiceOver labels/help, Increased Contrast, Differentiate Without Color, and Reduce Motion.
- Use `Button`, not tap gestures, for actions.
- Keep progress understandable without animation and avoid unnecessary custom animation.
- Use system styles and hierarchical colors; never use color as the only status signal.
- Use `#Preview` with representative defaults, imported nested settings, validation failures, and build states.

## Delivery phases

### Phase 1 — establish the shared module without behavior changes

- Add `SwiftPkgCore` to SwiftPM and Xcode as a static library.
- Move existing domain/build/import/support files into Core and CLI-only files into the executable target.
- Introduce only the access control needed by the two frontend modules; keep implementation details internal.
- Split the existing tests into Core and CLI test targets.
- Verify identical CLI help, exit codes, generated build-info files, and integration behavior before UI work begins.

Exit gate: `swift test`, `./scripts/verify-loop.sh`, release CLI build, and Xcode CLI build all pass with no behavior changes.

### Phase 2 — add editable configuration and direct plist/JSON transfer

- Add `PackageSettingsDraft` and field-level validation.
- Split template loading from resolved build loading.
- Add specific-file plist/JSON import and export APIs.
- Add round-trip and legacy-key tests, including nested signing/notarization dictionaries and `${version}` preservation.
- Extend `ProjectCreator` to accept a validated configuration rather than always writing defaults.

Exit gate: plist and JSON round trips are byte-schema compatible with the CLI, while existing YAML projects and version substitution still pass tests.

### Phase 3 — modernize shared operations for both frontends

- Introduce frontend-neutral operation requests and structured reporting.
- Convert process/build/import/sync paths to async operations with cancellation.
- Adapt the CLI console and exit-code mapping without changing its public behavior.
- Add tests for event ordering, cancellation, failures, and CLI mapping.

Exit gate: the CLI integration loop passes and no shared operation writes directly to stdout/stderr.

### Phase 4 — add the Swiftpkgr target and project editor

- Add the macOS 15 SwiftUI app target, app icon/assets, bundle identifier, schemes, and Hardened Runtime configuration.
- Build welcome, project lifecycle, split-view editor, settings sections, dirty-state handling, and commands.
- Implement project format discovery and explicit save.
- Add model tests and previews for every editor section.

Exit gate: a user can create/open a project, edit every current configuration field, save it, and build the same project successfully with the CLI.

### Phase 5 — add package import, settings transfer, and build operations

- Wire Import Package, Convert Existing Folder, Import Settings, Export Settings, Build, Cancel, Export BOM, and Synchronize BOM.
- Add progress/events, error presentation, output reveal actions, and operation locking.
- Test all build-only toggles and format choices through the shared request types.

Exit gate: the acceptance scenarios below pass on macOS 15 and the CLI remains unchanged.

### Phase 6 — accessibility, distribution, documentation, and CI

- Perform VoiceOver, keyboard-only, increased-contrast, text-size, Differentiate Without Color, and Reduce Motion checks.
- Add `xcodebuild` app build/tests to CI using an Xcode version with Swift 6.2 or later.
- Update README/verification documentation for both products.
- Decide whether releases contain a separate Swiftpkgr artifact or one installer that places `Swiftpkgr.app` in `/Applications` alongside `/usr/local/bin/swiftpkg`.
- Update signing/notarization and release scripts only after the artifact decision; use a Developer ID Application identity for the app and retain the existing installer signing path.

Exit gate: CI builds both products, the app launches on macOS 15, CLI support remains macOS 13, and release documentation is reproducible.

## Test strategy

### Core unit and contract tests

- Default values and every typed enum.
- All legacy wire keys and defaults for missing keys.
- Plist, JSON, YAML, and YML project loading.
- Standalone plist/JSON import and export round trips.
- Template preservation versus build-time `${version}` substitution.
- Signing and both notarization authentication modes.
- Invalid field values and useful field-level errors.
- Build request construction for every CLI/UI toggle.
- Package importer rollback and event reporting.
- Cancellation and process failure propagation.

Add a parity contract test that enumerates every `PackageConfiguration` field and `PackageBuildOptions` value and verifies that both CLI mapping and UI draft mapping cover it. This prevents future CLI options from silently missing in Swiftpkgr.

### App model and UI tests

- New/open/import/convert project state transitions.
- Dirty-state confirmation and save behavior.
- Import Settings replacement and invalid-file errors.
- Export extension/format agreement and credential warning.
- Build control enablement, single-operation locking, cancellation, and success/failure presentation.
- Keyboard commands and VoiceOver labels for primary controls.

Inject a fake core operation service into app tests. Do not invoke real package tools from unit or UI tests.

### Integration and manual verification

Continue running:

```sh
swift test
./scripts/verify-loop.sh
swift build -c release
xcodebuild -project swiftpkg.xcodeproj -scheme swiftpkg -configuration Release build
xcodebuild -project swiftpkg.xcodeproj -scheme Swiftpkgr -configuration Release build
git diff --check
```

Add an isolated Swiftpkgr integration fixture that creates projects in plist and JSON, opens a CLI-created YAML project, imports a built package, and verifies exported settings by loading them through Core and building them with the CLI.

## Acceptance scenarios

1. Create a plist project in Swiftpkgr, configure every section, build it in Swiftpkgr, then rebuild it with `swiftpkg` without editing the file.
2. Import a CLI-created JSON settings file containing legacy keys and nested signing/notarization settings; edit and export it; load the export with `swiftpkg` with no schema loss.
3. Import a plist containing `${version}` in name/title, export it, and confirm the placeholder remains in the exported file while the built package uses the substituted version.
4. Open and build an existing YAML CLI project even though standalone settings export is limited to plist/JSON.
5. Import an existing flat or supported bundle package into a new project, inspect the generated settings/payload/scripts, and build it.
6. Build with each of Export BOM, Skip Signing, Skip Notarization, and Skip Stapling and verify the same core arguments/events as the corresponding CLI flags.
7. Synchronize `Bom.txt`; when ownership needs root, receive the same warning as the CLI without a password prompt or silent partial-success claim.
8. Navigate all primary workflows with the keyboard and VoiceOver, with status never communicated by color alone.

## Risks to address during implementation

- **Round-trip data loss:** Current `BuildInfoStore.load` substitutes versions immediately. The template/resolved API split must land before the editor writes files.
- **CLI regression during modularization:** Move code in a behavior-neutral phase and keep the integration loop as a phase gate.
- **Main-thread blocking:** Do not wrap synchronous builders in Main Actor tasks. Modernize operation/process APIs before connecting them to buttons.
- **Plaintext notarization passwords:** Preserve the compatibility schema, use a secure on-screen field, warn on export, and recommend keychain profiles.
- **Filesystem permissions and root ownership:** Avoid an ad hoc authorization prompt. Document limitations and consider a privileged helper only as a separately reviewed future project.
- **App sandbox constraints:** The initial non-sandboxed, notarized distribution is deliberate; enabling sandboxing later requires persistent security-scoped access and subprocess testing.
- **Deployment mismatch:** Keep Core/CLI at macOS 13 while setting only Swiftpkgr to macOS 15. Test both deployment targets in CI.
- **Release complexity:** Do not silently change the current CLI installer. Make the combined-versus-separate app artifact decision before modifying release automation.
