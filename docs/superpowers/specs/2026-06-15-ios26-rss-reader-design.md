# iOS 26 RSS Reader Design

## Goal

Add an RSS reader entry point to Atoman iOS using the selected “Creator Studio” visual direction. The first release should prove the reading experience before adding subscription source management.

## Confirmed direction

- Visual direction: Creator Studio.
- First feature: RSS reader.
- First layout: Today Flow.
- API base: move iOS live API base URL from `http://localhost:8080/api` to `http://localhost:8080/api/v1`.
- Backend: use existing feed endpoints in `../Atoman-Backend`; do not add backend endpoints for this release.

## In scope

- Add a new “订阅” tab to the iOS app shell.
- Wrap the tab in the existing authentication gate.
- Fetch the subscribed feed timeline from `/api/v1/feed/timeline` with pagination.
- Default timeline query: `page=1&page_size=20&hide_duplicates=true`.
- Support timeline filters for all items, unread items, and starred items.
- Show timeline cards with source, publish time, title, summary, unread state, and star affordance.
- Open a feed item detail screen from the timeline.
- Mark a feed item as read when it is opened.
- Toggle star state from the timeline or detail screen.
- Update existing blog API usage so the app still works after the shared live base URL changes to `/api/v1`.

## Out of scope

- Adding RSS URLs from iOS.
- OPML import or export.
- Subscription group management.
- Reading-list support.
- Feed discovery.
- Backend schema or route changes.
- Full-text HTML rendering beyond a safe first-pass presentation.

## User experience

### Tab placement

Add “订阅” as a top-level tab beside writing, drafts, and channels. The tab uses an RSS-style SF Symbol such as `dot.radiowaves.left.and.right` or `newspaper`.

### Timeline screen

The timeline is a card-based scroll view rather than a default plain `List`. It should feel like a modern writing and reading workspace:

- Dark, low-chroma background in the Creator Studio direction.
- Large title: “订阅”.
- Small date or context label above the title.
- Acid-lime accent for the unread count and selected filter.
- Filter capsules: “全部”, “未读”, “星标”.
- Feed cards with rounded corners, subtle borders, source metadata, title, summary, and unread indicator.

The first version should prioritize readability and fast scanning over dense management controls.

### Empty states

If the user has no timeline items, show a branded empty state rather than a blank list:

- Title: “还没有订阅内容”.
- Message: “先在网页端添加 RSS 订阅源，新的内容会出现在这里。”
- No add-source form in this release.

### Error states

Show a card-style error state with a retry action when loading fails. Authentication failures should use the existing `AuthenticationGateView` pattern.

### Detail screen

The detail screen shows:

- Source title.
- Publish time.
- Article title.
- Summary or full-text fallback.
- Original link affordance.
- Star button.

Opening a feed item marks it read. If the request fails, the UI should not claim the item was marked read.

## API design

Add a `FeedAPI` alongside `BlogAPI`.

Methods:

- `fetchTimeline(filter: FeedTimelineFilter, page: Int, pageSize: Int) async throws -> FeedTimelinePage`
- `markRead(itemIDs: [String]) async throws`
- `toggleStar(feedItemID: String) async throws -> Bool`

Endpoint mapping:

- `GET feed/timeline?page=<page>&page_size=<pageSize>&hide_duplicates=true`
- `GET feed/timeline?...&is_read=false` for unread.
- Starred filtering may use `GET feed/stars` if timeline cannot express starred state directly.
- `POST feed/timeline/mark-read` with `feed_item_ids`.
- `POST feed/timeline/star` with `feed_item_id`.

Use the app’s shared `APIClient` and `AuthSessionStore`. Do not introduce a second HTTP client.

## Data models

Add feed-specific models under `AtomanStudio/Domain/Models/`:

- `FeedTimelinePage`
- `FeedTimelineItem`
- `FeedItem`
- `FeedSource`
- `FeedTimelineFilter`

The backend timeline item can contain either `post` or `feed_item`. The iOS first release should render external RSS `feed_item` entries and safely ignore unsupported item shapes instead of crashing.

## State management

Add `FeedTimelineViewModel` under `AtomanStudio/Features/Feed/`.

Responsibilities:

- Track timeline items, loading state, error message, selected filter, current page, and whether more pages are available.
- Load initial timeline on first appearance.
- Reload when the filter changes.
- Mark an item read after opening detail.
- Toggle star with local update only after a successful response, or rollback if optimistic update is used.

## App integration

Update `AppEnvironment` to include `FeedAPI`.

Update `MainTabView` to create and display `FeedTimelineView` in a new authenticated “订阅” tab.

Changing the live base URL to `/api/v1` means existing `BlogAPI` paths should remain relative (`blog/...`) and continue resolving to `/api/v1/blog/...`.

## Testing

Add XCTest coverage for:

- Decoding feed timeline envelopes with `feed_item` entries.
- Decoding empty timeline responses.
- Building or invoking feed API requests for timeline, mark-read, and star toggle.
- `FeedTimelineViewModel` loading success and error states.
- Filter changes resetting pagination and reloading data.
- Mark-read behavior when opening an item.
- Star toggle success and failure behavior.
- App smoke test still creating the top-level shell after the new tab is added.

Run at minimum:

```bash
swift test
swift build
```

For UI work, also build the iOS app scheme in Xcode or with `xcodebuild` and manually inspect the new tab in the simulator when available.

## Acceptance criteria

- A logged-in user can open the new “订阅” tab and see RSS timeline cards from the backend.
- Opening a feed item presents a detail screen and marks the item read.
- The user can toggle star state for a feed item.
- Filters for all, unread, and starred content are visible and functional.
- Empty, loading, and error states match the Creator Studio visual direction.
- Existing writing, drafts, and channels tabs still compile and route against the `/api/v1` backend base.
