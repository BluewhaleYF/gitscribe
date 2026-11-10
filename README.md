# GitScribe

AI-assisted git commit message drafter for macOS. Pick a repo, review the
changes, and let GitScribe write the commit.

## Features

- **Open any local repository** — browse to a folder or paste a path; GitScribe
  resolves the repository root automatically.
- **Read the working tree** — see staged/unstaged/untracked files with a
  colored status badge, the current branch, and the full diff.
- **Draft commit messages** — a built-in offline drafter produces a
  [Conventional Commits](https://www.conventionalcommits.org/) message from the
  changed files.
- **Optional AI pass** — plug in any OpenAI-compatible chat completions
  endpoint (base URL, API key, model) to refine the draft.
- **Commit from the app** — stage all changes and commit, or copy the message
  to paste elsewhere.

## Requirements

- macOS with Xcode and CocoaPods installed.
- Flutter 3.x (stable) with the macOS desktop toolchain enabled.

## Run

```sh
flutter pub get
flutter run -d macos
```

## Project layout

```
lib/
  main.dart                 # app entry point and theme
  src/
    models.dart             # ChangeType, FileChange, RepoInfo
    git_service.dart        # git CLI wrapper (status/diff/commit)
    message_generator.dart  # offline Conventional Commits drafter
    ai_service.dart         # OpenAI-compatible client
    app_config.dart         # persisted settings (last repo, AI provider)
    home_page.dart          # main UI
```
