# clickup-mac-widget

ClickUp has no macOS desktop widget. This repo adds two, which use the same API
calls and sort tasks the same way:

| | `macos/` WidgetKit | `swiftbar/` plugin |
| --- | --- | --- |
| Where it shows | Desktop / Notification Center (small, medium, large) | Menu bar |
| Needs | Xcode 15+, macOS 14+, XcodeGen | [SwiftBar](https://swiftbar.app) or [xbar](https://xbarapp.com), python3 |
| Refresh | about every 15 min (WidgetKit budget) | every 5 min (file name `.5m.`) |
| Stop timer | button in the widget (AppIntent) | menu item |

Both show **my open tasks** in four groups: overdue, due today, upcoming, no due date.
They also show the **running timer**. Clicking a task opens it in ClickUp.

Auth is a personal API token: ClickUp → avatar → Settings → Apps → API Token (`pk_…`).
The two widgets keep the token in different places (see below), because a sandboxed
widget cannot read the login keychain item the plugin uses.

## SwiftBar / xbar

```bash
security add-generic-password -s clickup-widget -a "$USER" -w 'pk_...'
ln -s "$PWD/swiftbar/clickup.5m.py" "$HOME/Library/Application Support/SwiftBar/Plugins/"
```

Pick a workspace other than the first one with `CLICKUP_TEAM_ID`. In xbar, set it in
the plugin's variables. In SwiftBar, use the environment.

Tests (offline): `python3 -m pytest swiftbar`.

## WidgetKit

```bash
brew install xcodegen
cd macos && xcodegen && open ClickUpWidget.xcodeproj
```

1. Choose your team under Signing & Capabilities for both targets. A free personal team
   is enough to run it locally. Or set `DEVELOPMENT_TEAM` in `project.yml`.
2. Run the `ClickUpWidget` scheme. Paste the token, pick a workspace, then click
   **Save & test**.
3. Right-click the desktop → Edit Widgets → ClickUp.

The token lives in the data-protection keychain, in the access group
`<TeamID>.com.wansiedler.clickupwidget`. The app and the extension share that group.
