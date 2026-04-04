# Claude Token Burn — macOS Menu Bar App

## Overview

A lightweight native macOS menu bar app (status item) that displays real-time token usage percentage and session window time remaining for Claude Code. Sits alongside the clock, Wi-Fi, and battery icons in the system menu bar.

## Goals

- **At-a-glance awareness** of token budget consumption and session time
- **Minimal resource footprint** — under 50MB RAM, negligible CPU
- **Native macOS experience** — Swift/SwiftUI, no web runtime

---

## Technology

| Component       | Choice                       |
|-----------------|------------------------------|
| Language        | Swift 5.9+                   |
| UI Framework    | SwiftUI + AppKit (NSStatusItem) |
| Min macOS       | 13.0 (Ventura)               |
| Build system    | Xcode / Swift Package Manager |
| File watching   | FSEvents (via DispatchSource) |
| Notifications   | UserNotifications framework  |

---

## Data Sources

### Primary: `~/.claude/stats-cache.json`

Aggregate usage data updated by Claude Code:

- `dailyModelTokens[]` — tokens consumed per date per model (`inputTokens`, `outputTokens`, `cacheReadInputTokens`, `cacheCreationInputTokens`)
- `modelUsage{}` — cumulative per-model stats including `costUSD`
- `dailyActivity[]` — message count, session count, tool call count per day
- `totalSessions`, `totalMessages`

### Secondary: `~/.claude/cache/prompt-cache/session-*/`

Per-session data:

- `stats.json` — tracked requests, cache hit/miss/write counts, token counts
- `session-state.json` — `observed_at_unix_secs` timestamp (used for session start/end detection)

### Session History: `~/.claude/history.jsonl`

JSONL with per-command entries containing `timestamp`, `sessionId`, `project`.

---

## Core Features

### 1. Menu Bar Status Item

**Display format:** `🔥 72% | 3h12m`

- **Icon:** Small flame/token icon (SF Symbol: `flame.fill` or custom)
- **Percentage:** Tokens remaining as `%` of user-configured budget
- **Time:** Time remaining in the current 5-hour session window

**Color coding** (applied to the entire status item text):

| Remaining % | Color  |
|-------------|--------|
| 100–50%     | Green  |
| 50–25%      | Yellow |
| 25–10%      | Orange |
| < 10%       | Red    |

### 2. Dropdown Panel (click to expand)

Shown when the user clicks the menu bar item. Displays:

- **Tokens Used / Budget** — e.g., `142,000 / 500,000 tokens`
- **Percentage Remaining** — e.g., `71.6%`
- **Session Window** — Start time, time elapsed, time remaining (out of 5hrs)
- **Burn Rate** — tokens/minute over the current session
- **Estimated Time Until Budget Depleted** — based on current burn rate
- **Model Breakdown** — tokens split by model (Opus, Sonnet, Haiku) for today
- **Cost (if applicable)** — `$X.XX` from `costUSD` field (useful for API/flexible plans)
- **Separator**
- **Reset Window** — manual override button to reset the 5hr timer
- **Settings…** — opens settings window
- **Quit**

### 3. Session Window Auto-Detection

The app detects the start of a usage window by:

1. Reading session directories in `~/.claude/cache/prompt-cache/`
2. Parsing `session-state.json` → `observed_at_unix_secs` to find the earliest session timestamp within the current window
3. A "window" is defined as a rolling 5-hour block starting from first activity after the previous window expired
4. If no recent session is found (>5hrs since last activity), the timer resets on next detected activity

Fallback: manual "Reset Window" button in the dropdown.

### 4. Notifications

macOS native notifications at configurable thresholds:

- Default thresholds: **75%**, **90%**, **95%** consumed
- Each threshold fires once per window (not repeatedly)
- User can enable/disable individually in settings
- Notification includes: percentage used, tokens remaining, estimated time left

### 5. Settings Window

Accessible from the dropdown menu:

| Setting                   | Default         | Description                                    |
|---------------------------|-----------------|------------------------------------------------|
| Plan type                 | Max             | Dropdown: Pro / Max / API / Custom             |
| Token budget per window   | 500,000         | Editable number field (auto-filled by plan)    |
| Window duration           | 5 hours         | Editable (hours)                               |
| Poll interval             | 60 seconds      | Slider: 30s – 300s                             |
| Notification thresholds   | 75%, 90%, 95%   | Checkboxes with editable values                |
| Launch at login           | Off             | Toggle                                         |
| Show cost in dropdown     | Off             | Toggle (for API/flexible plans)                |

Settings persisted to: `~/Library/Application Support/ClaudeTokenBurn/settings.json`

---

## Architecture

```
┌─────────────────────────────────────┐
│           App (NSApplication)       │
│  ┌───────────┐  ┌────────────────┐  │
│  │ StatusItem │  │ SettingsWindow │  │
│  │ (SwiftUI)  │  │  (SwiftUI)     │  │
│  └─────┬─────┘  └────────────────┘  │
│        │                             │
│  ┌─────▼──────────────────────────┐  │
│  │       TokenBurnViewModel       │  │
│  │  - tokensUsed / budget         │  │
│  │  - percentRemaining            │  │
│  │  - windowStartTime             │  │
│  │  - timeRemaining               │  │
│  │  - burnRate                    │  │
│  │  - modelBreakdown              │  │
│  └─────┬──────────────────────────┘  │
│        │                             │
│  ┌─────▼──────────────────────────┐  │
│  │      ClaudeDataService         │  │
│  │  - readStatsCache()            │  │
│  │  - readSessionData()           │  │
│  │  - detectWindowStart()         │  │
│  │  - calculateTokensForWindow()  │  │
│  └─────┬──────────────────────────┘  │
│        │                             │
│  ┌─────▼──────────────────────────┐  │
│  │      FileWatcher (FSEvents)    │  │
│  │  - watches ~/.claude/          │  │
│  │  - triggers refresh on change  │  │
│  └────────────────────────────────┘  │
│                                      │
│  ┌────────────────────────────────┐  │
│  │   NotificationManager          │  │
│  │  - threshold tracking          │  │
│  │  - fires UNUserNotification    │  │
│  └────────────────────────────────┘  │
└─────────────────────────────────────┘
```

### Key Classes

| Class                  | Responsibility                                                     |
|------------------------|--------------------------------------------------------------------|
| `AppDelegate`          | Sets up NSStatusItem, manages app lifecycle, launch-at-login       |
| `StatusItemView`       | SwiftUI view rendered in the menu bar (icon + text + color)        |
| `DropdownView`         | SwiftUI popover/panel with detailed stats                          |
| `SettingsView`         | SwiftUI settings window                                            |
| `TokenBurnViewModel`   | ObservableObject — central state, drives all UI updates            |
| `ClaudeDataService`    | Reads and parses Claude Code's JSON files                          |
| `FileWatcher`          | FSEvents-based watcher on `~/.claude/` for change detection        |
| `NotificationManager`  | Manages threshold alerts via UserNotifications                     |
| `SettingsStore`        | Persists user settings to disk, provides defaults per plan type    |

### Data Flow

1. **FileWatcher** detects changes in `~/.claude/` → notifies `ClaudeDataService`
2. **ClaudeDataService** re-reads `stats-cache.json` and session files → computes current window usage
3. **TokenBurnViewModel** updates published properties → SwiftUI re-renders
4. **Timer** (60s default) also triggers a refresh as a fallback if FSEvents misses something
5. **NotificationManager** checks thresholds on each update → fires alerts if crossed

---

## Token Calculation Logic

```
todayTokens = sum of all model tokens from dailyModelTokens where date == today
              (inputTokens + outputTokens + cacheCreationInputTokens)

windowTokens = todayTokens filtered to only sessions within the current 5hr window
               (cross-reference session timestamps from history.jsonl)

percentRemaining = ((budget - windowTokens) / budget) * 100
burnRate = windowTokens / minutesElapsedInWindow
estimatedTimeLeft = (budget - windowTokens) / burnRate
```

Note: `cacheReadInputTokens` are excluded from budget consumption as they don't count against usage limits.

---

## File Structure

```
ClaudeTokenBurn/
├── ClaudeTokenBurn.xcodeproj
├── Sources/
│   ├── App/
│   │   ├── ClaudeTokenBurnApp.swift      # @main, menubar-only app
│   │   └── AppDelegate.swift             # NSStatusItem setup
│   ├── Views/
│   │   ├── StatusItemView.swift          # Menu bar display
│   │   ├── DropdownView.swift            # Click-to-expand panel
│   │   └── SettingsView.swift            # Settings window
│   ├── ViewModels/
│   │   └── TokenBurnViewModel.swift      # Central state
│   ├── Services/
│   │   ├── ClaudeDataService.swift       # JSON parsing & computation
│   │   ├── FileWatcher.swift             # FSEvents wrapper
│   │   └── NotificationManager.swift     # Threshold alerts
│   ├── Models/
│   │   ├── StatsCache.swift              # Codable for stats-cache.json
│   │   ├── SessionState.swift            # Codable for session-state.json
│   │   └── Settings.swift                # App settings model
│   └── Utilities/
│       └── Constants.swift               # Plan defaults, paths, colors
├── Resources/
│   └── Assets.xcassets                   # App icon, SF Symbol overrides
├── SPEC.md
└── README.md
```

---

## Constraints

- **No network access required** — all data is read from local files
- **No background processing** beyond the poll timer and FSEvents
- **Sandboxing:** The app needs read access to `~/.claude/`. If distributed outside the App Store, no sandbox is needed. If sandboxed, will require a security-scoped bookmark or run unsandboxed.
- **Memory target:** < 50MB RSS
- **CPU:** Near-zero when idle; brief spike on each poll/refresh

---

## Future Considerations (Out of Scope for v1)

- Historical usage graphs (daily/weekly trends)
- Multiple Claude Code installation support
- Keyboard shortcut to show/hide dropdown
- Widget for macOS Notification Center
- Auto-update mechanism
