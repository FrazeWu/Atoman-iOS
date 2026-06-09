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