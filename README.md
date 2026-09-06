# ⚡️ RepReel (AI-Powered Workout Parser & Gym Tracker)

<p align="center">
  <img src="https://img.shields.io/badge/iOS-18.0%2B-black?style=for-the-badge&logo=apple&logoColor=white" alt="iOS 18.0+"/>
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Swift 6.0"/>
  <img src="https://img.shields.io/badge/SwiftUI-Apple%20HIG-0071e3?style=for-the-badge&logo=swift&logoColor=white" alt="SwiftUI"/>
  <img src="https://img.shields.io/badge/Tests-41%20Passing-brightgreen?style=for-the-badge" alt="41 Tests Passing"/>
  <img src="https://img.shields.io/badge/License-Proprietary-orange?style=for-the-badge" alt="License"/>
</p>

> **RepReel** automatically transforms Instagram Reels and YouTube Shorts workout videos into structured routines, actionable gym checklists, and volume analytics via multimodal AI.

---

## 🌐 Official Links & App Store Metadata

- **Marketing Website:** [https://douglasmin.github.io/RepReel_Swift/](https://douglasmin.github.io/RepReel_Swift/)
- **Support & Feedback:** [https://douglasmin.github.io/RepReel_Swift/#support](https://douglasmin.github.io/RepReel_Swift/#support)
- **Privacy Policy:** [https://douglasmin.github.io/RepReel_Swift/privacy/](https://douglasmin.github.io/RepReel_Swift/privacy/)

---

## ✨ Key Features

### 1. 🪄 1-Tap Video Ingestion (Instagram Reels & YouTube Shorts)
- **Share Extension Integration**: Tap the iOS Share Sheet from Instagram or YouTube directly into RepReel.
- **Multimodal AI Parsing**: Extracts exercise names, target sets, rep ranges, rest intervals, and coaching tips in seconds.
- **Multi-Part Series Stitching**: Automatically merges Part 1, Part 2, and Part 3 video routines into a unified training split (e.g. 3-Day PPL).

### 2. ⚡️ Live Workout Tracker & Rest Timer
- **Forward Weight Cascade**: Entering a weight in Set 1 automatically pre-fills subsequent uncompleted sets; editing Set 2 propagates forward while preserving Set 1.
- **Automated Rest Timer**: Checking off a set immediately activates a circular rest countdown with haptic feedback and local notifications.
- **Exercise Substitution**: Tap to swap any exercise with biomechanically equivalent alternatives (e.g. Incline Hammer Strength $\leftrightarrow$ Incline DB Press).
- **Docked Mini Player**: Swipe down on an active workout to collapse it into a floating mini-player bar, allowing seamless navigation across tabs.

### 3. 📊 Volume Analytics & Consistency
- **Cumulative Tonnage ($kg$)**: Live tracking of total volume lifted, completed sets, and estimated 1RMs.
- **7-Day Bar Charts & Streaks**: Visualizes weekly lifting cadence and progressive overload trends.
- **History Management**: Edit or delete logged sessions with automatic volume recalculation.

### 4. 🎨 Apple Human Interface Guidelines (HIG) & Accessibility
- **Apple Fitness+ Dark Aesthetic**: Dark glassmorphism, glowing accents, tactile checkmarks, and SF Pro tabular typography.
- **iPad & Full Screen Support**: Compliant with App Store bundle requirements (`UIRequiresFullScreen` + 4-way rotation).
- **Accessibility & VoiceOver**: Fully annotated accessibility labels and `@ScaledMetric` Dynamic Type support.

---

## 🏗️ Architecture & Modules

```
instagram-reels-workout-swift/
├── ReelsKit/                   # Core Swift Package (Domain & Network Layer)
│   ├── Sources/ReelsKit/
│   │   ├── Models/             # WorkoutProgram, WorkoutDraft, ActiveSession, Coaching
│   │   ├── Networking/         # APIClient, HTTPTransport, Endpoint Requests
│   │   └── Storage/            # SharedStore, Volume Helpers
│   └── Tests/ReelsKitTests/    # 41 Isolated Domain & Mock Network Unit Tests
│
├── ReelsWorkout/               # Main SwiftUI Application Target (iOS 18+)
│   ├── App/                    # AppRootView, AppEnvironment, ReelsWorkoutApp
│   ├── Features/
│   │   ├── Library/            # LibraryView, LibraryStore, MergeProgramsSheet
│   │   ├── ProgramDetail/      # ProgramDetailView, EditProgramSheet
│   │   ├── Workout/            # WorkoutSessionView, WorkoutSessionStore, RestTimerBar
│   │   └── History/            # HistoryView, HistoryStore, SessionDetailView
│   ├── Support/                # Theme, Color+Hex, PreviewFixtures
│   └── Resources/              # Info.plist, Entitlements, Assets
│
├── ReelsShareExtension/        # iOS Share Extension Target (Reels & Shorts Ingestion)
│   └── ShareViewController.swift
│
├── ReelsWidgetExtension/       # WidgetKit Target (Live Activity & Dynamic Island)
│
├── docs/                       # GitHub Pages Landing Page, Support & Privacy Policy
│   ├── index.html              # Marketing Landing Page
│   ├── privacy/index.html      # App Store Compliant Privacy Policy
│   ├── style.css               # Modern CSS Design System
│   └── API_SPECIFICATION.md    # REST API Specification
│
├── ReelsWorkoutTests/          # App-Level Integration Tests
└── project.yml                 # XcodeGen Specification
```

---

## 🚀 Quick Start

### Prerequisites
- **macOS Sequoia** (or newer)
- **Xcode 16.0+** (Swift 6.0 toolchain)
- **XcodeGen** (`brew install xcodegen`)
- **xcbeautify** (`brew install xcbeautify` — optional)

### Build & Run
```bash
# 1. Bootstrap project configuration and generate Xcode project
make bootstrap

# 2. Build and launch in iPhone Simulator
make run

# 3. Run ReelsKit pure unit tests (instant feedback loop)
make unit

# 4. Run full test suite through Xcode scheme
make test
```

---

## 🧪 Test Coverage

ReelsWorkout features comprehensive unit tests across domain models, cascading state mutations, and mock API network interactions:

```bash
$ make unit
✔ Suite "AppConfig" passed
✔ Suite "APIClient" passed
✔ Suite "WorkoutDraft seeding" passed
✔ Suite "WorkoutDraft weight carry-down" passed
✔ Suite "WorkoutDraft wire conversion" passed
✔ Suite "Active workout draft" passed
✔ Suite "Program decoding" passed
✔ Suite "PendingJobStore" passed
✔ Suite "Volume helpers" passed
✔ Test run with 41 tests in 9 suites passed!
```

---

## 📄 License & Copyright

Copyright © 2026 Douglas Min. All rights reserved.
