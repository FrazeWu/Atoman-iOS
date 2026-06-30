# Atoman iOS

This directory is maintained as a standalone Git repository for the native iOS client.
The parent Atoman repository ignores `ios/`, so iOS work, history, and releases can move independently from the web and server codebase.

## Scope

- Swift Package: `Package.swift`
- App source: `AtomanStudio/`
- Tests: `AtomanStudioTests/`

## Requirements

- Xcode 16+
- Swift 5.10+
- iOS 17+
- macOS 14+

## Local development

```bash
swift package resolve
swift test
open Package.swift
```

## Development Plan

The iOS client should start from the existing Atoman Studio direction instead of copying every web module at once. The first usable version should focus on writing, reading, and light interaction.

### Phase 1: Studio foundation

- Align the API base path with the backend `/api/v1` routes.
- Complete auth session handling with login, session restore, logout, and persistent token storage.
- Finish the blog writing loop: create post, edit post, publish, save cloud draft, and sync local drafts.
- Make the draft list read from the local GRDB database instead of static placeholder data.
- Complete channel and collection selection for publishing.
- Keep verification simple: run `swift test` before considering the phase complete.

### Phase 2: Reading experience

- Add Feed screens for timeline, explore, item detail, starred items, reading list, and subscriptions.
- Add Blog reading screens for post list, post detail, channel pages, collection pages, and bookmarks.
- Add notification entry points for unread count and notification list.
- Prefer mobile-first reading ergonomics over reproducing web sidebar layouts.

### Phase 3: Community interaction

- Add Forum basics: category/topic list, topic detail, new topic, replies, likes, and bookmarks.
- Add Debate basics: debate list, detail, and voting.
- Defer realtime DM and WebSocket-heavy flows until notifications and forum interaction are stable.

### Phase 4: Media and knowledge modules

- Add Music browsing first: artists, albums, details, and starred items.
- Add Video and Podcast playback/detail views before upload or editor features.
- Keep Timeline and admin/review workflows as later additions unless they become a core mobile use case.

### Milestones

- M1: Login, API path alignment, local/cloud drafts, and publish flow.
- M2: Feed reading, Blog reading, bookmarks, and reading list.
- M3: Notifications and basic Forum interaction.
- M4: Music browsing plus Video/Podcast playback.
- M5: Advanced management features such as channel management, subscription management, upload, review, and collaboration.

## Repository bootstrap

Initialize this directory as its own repository if it has not been initialized yet:

```bash
git init -b main
git add .
git commit -m "Initial iOS repository import"
```

Add the dedicated remote after the repository URL is ready:

```bash
git remote add origin <ios-remote-url>
git push -u origin main
```

## Notes

- `Package.resolved` is kept in version control for reproducible dependency resolution.
- `.build/` and `.swiftpm/` stay local to each machine.
