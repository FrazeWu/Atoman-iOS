# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project overview

Atoman iOS is maintained as a standalone Git repository for the native client. The repository contains a Swift Package library target plus a small runnable iOS app wrapper.

- `Package.swift` defines the `AtomanStudio` library target and `AtomanStudioTests` test target.
- `AtomanStudioApp.xcodeproj` provides the runnable iOS app target and schemes `AtomanStudio` and `AtomanStudioApp`.
- Minimum platforms are iOS 17 and macOS 14. Xcode 16+ and Swift 5.10+ are expected.
- `Package.resolved` is committed for reproducible dependency resolution.

## Common commands

```bash
swift package resolve
swift build
swift test
swift test list
swift test --filter BlogEditorViewModelTests/testDraftPayloadCarriesVisibilityAndCollections
xcodebuild -list -project AtomanStudioApp.xcodeproj
open Package.swift
open AtomanStudioApp.xcodeproj
```

Use `swift test --filter <TestClass>/<testMethod>` for a single XCTest method, or filter by class name to run one test case.

For simulator/device work, use the `AtomanStudioApp` scheme from `AtomanStudioApp.xcodeproj`.

## Architecture

`AtomanStudioApp/AtomanStudioApp.swift` is only the SwiftUI app entry point. It constructs `AppEnvironment.live()` and injects it into `RootAppView`.

`AtomanStudio/App/AppEnvironment.swift` is the composition root for runtime dependencies:

- `APIClient` points at `http://localhost:8080/api` in the live environment.
- `AuthSessionStore` holds the current auth token.
- `AppDatabase.openDefault()` opens the GRDB-backed SQLite database in Application Support.
- `BlogAPI` combines the API client and auth session for authenticated blog endpoints.

`AtomanStudio/App/RootAppView.swift` builds the top-level SwiftUI shell. `MainTabView` owns the selected tab and a shared `BlogEditorViewModel`, then wires the Writing, Drafts, and Channels tabs.

The library is organized by responsibility:

- `Features/` contains SwiftUI screens and feature view models for auth, editor, publishing, drafts, collections, channels, and media.
- `Domain/Models/` contains request/response and editor payload models shared across UI, API, and persistence.
- `Domain/Services/` contains pure business services such as draft recovery selection, embed insertion, and Markdown import.
- `Infrastructure/API/` contains the low-level `APIClient` and `BlogAPI` endpoint wrapper.
- `Infrastructure/Auth/` contains auth session state.
- `Persistence/` contains GRDB database setup and local record types.

## Persistence

`AppDatabase` uses GRDB. The current migrations create:

- `local_editor_drafts`, keyed by `context_key`, for local editor draft state.
- `pending_sync_records`, keyed by `id`, for queued sync payloads.

Tests generally use `AppDatabase.inMemory()` rather than the default on-disk database.

## Testing notes

The test suite is XCTest-based under `AtomanStudioTests/`. Existing tests cover app bootstrapping, auth gate state, blog API decoding, editor payload/publish behavior, draft sync selection, local draft persistence, Markdown import, embed insertion, and login validation.

Prefer testing domain services and view models through the Swift Package with `swift test`; use Xcode/simulator when verifying app-shell or device-specific SwiftUI behavior.
