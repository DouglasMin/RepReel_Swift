# 🏋️‍♂️ RepReel (인스타그램 릴스 기반 스마트 워크아웃 iOS 앱)

<p align="center">
  <img src="https://img.shields.io/badge/iOS-18.0%2B-black?style=for-the-badge&logo=apple&logoColor=white" alt="iOS 18.0+"/>
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Swift 6.0"/>
  <img src="https://img.shields.io/badge/SwiftUI-Apple%20HIG-0071e3?style=for-the-badge&logo=swift&logoColor=white" alt="SwiftUI"/>
  <img src="https://img.shields.io/badge/Architecture-Clean%20%2B%20Modular-success?style=for-the-badge" alt="Modular"/>
  <img src="https://img.shields.io/badge/Tests-24%20Passing-brightgreen?style=for-the-badge" alt="Tests"/>
</p>

> **RepReel**은 인스타그램 릴스에서 본 운동 루틴을 단 한 번의 공유로 정밀하게 분석하여 나만의 맞춤형 운동 프로그램으로 변환하고, 실시간 세트 기록 및 주간 볼륨 통계를 제공하는 최고 수준의 iOS 피트니스 앱입니다.

---

## ✨ 핵심 기능 (Key Features)

### 1. 📱 인스타그램 릴스 원탭 루틴 추출 (Share Extension & AI Ingest)
- 인스타그램 릴스 화면에서 **`공유 → RepReel`** 선택 시, AI 백엔드를 통해 종목, 세트/반복수, 휴식 시간, 코칭 가이드가 자동 추출되어 보관함에 저장됩니다.
- 루틴 병합(Merge) 기능을 통해 여러 릴스를 하나의 **통합 분할 프로그램(Push/Pull/Legs 등)**으로 손쉽게 묶을 수 있습니다.

### 2. ⚡ 실시간 인터랙티브 운동 트래커 (Live Workout Session)
- **순방향 중량 자동 계승 (Forward Weight Cascade)**:
  - 1세트의 중량을 입력하면 2~5세트에 자동으로 채워지며, 2세트에서 중량을 올리면 3~5세트로 새로운 중량이 자동 승계됩니다. (완료된 세트는 안전하게 보존).
- **진행도 게이지 & 실시간 완료 뱃지**:
  - 상단 그라데이션 게이지와 세트 카운터 칩 (`8 / 16 세트`) 및 숫자 롤링 애니메이션.
  - 특정 종목의 모든 세트를 마치는 즉시 녹색 **`✓ 완료`** 캡슐 뱃지가 팝업됩니다.
- **스마트 원형 휴식 타이머 (Rest Timer)**:
  - 세트 완료 체크 시 자동 실행되는 원형 카운트다운 링 (`+30s` / `-15s` 즉시 조절 가능).
  - 휴식 종료 시 **오디오 차임 사운드 🔔 및 햅틱 진동**과 함께 **백그라운드 로컬 푸시 알림** 발송.
  - 휴식 완료 시 타이머 바가 아래로 자동 퇴장(Auto-dismiss).
- **인라인 대체 운동 탐색 (Exercise Swap)**:
  - 헬스장 기구가 꽉 차 있거나 부상이 있을 때, 동일 타겟 근육군의 대체 종목을 즉시 추천받아 스왑.
- **Apple Music 스타일 도킹 미니 플레이어 (Docked Mini Player)**:
  - 운동 화면을 아래로 쓸어내리면 하단 탭 바(`내 루틴`, `운동 기록`) 바로 윗 공간에 컴팩트한 플로팅 카드로 도킹되어, 탭 전환을 자유롭게 지원합니다.

### 3. 📊 주간 볼륨 대시보드 & 스트릭 트래커 (Weekly Volume & Consistency)
- 🔥 **연속 운동 스트릭 뱃지**: `N일 연속 운동 달성!` 또는 `이번 주 N회 운동`.
- 📈 **전주 대비 볼륨 증감률**: `+14.2% vs 지난주` 증감률 뱃지.
- 🏋️ **총 중량톤수 ($kg$) 요약**: 실시간 계산된 주간 총 볼륨과 세트/세션 카운트.
- 📅 **7일 미니 볼륨 바 차트 & 캘린더 일지**: 월~일요일별 운동량 시각화 및 날짜별 운동 일지/볼륨 상세 리포트.

### 4. 🎨 Apple HIG & 접근성 극대화
- **Shimmer 스켈레톤 로딩 (`.shimmering()`)**: 데이터 로딩 중 은은한 광택 스켈레톤 UI 제공 (Reduce Motion 자동 준수).
- **터치 영역 $\ge 44 \times 44\text{ pt}$**: 모든 버튼, 스텝퍼, 체크박스 터치 타겟 준수.
- **Dynamic Type**: `@ScaledMetric` 기반 텍스트 크기 자동 대응.
- **Full VoiceOver**: 세트 번호, 무게, 횟수, 완료 상태가 통합된 친절한 접근성 레이블 지원.

---

## 🏗️ 아키텍처 (Architecture & Modules)

```
instagram-reels-workout-swift/
├── ReelsKit/                   # Core Swift Package (Pure Domain & Network Layer)
│   ├── Sources/ReelsKit/
│   │   ├── Models/             # WorkoutProgram, WorkoutDraft, ActiveSession, Coaching
│   │   └── Networking/         # APIClient, HTTPTransport, Endpoint Requests
│   └── Tests/ReelsKitTests/    # 100% Mocked Network & Domain Unit Tests
│
├── ReelsWorkout/               # SwiftUI iOS Application Target
│   ├── App/                    # AppRootView, AppEnvironment, ReelsWorkoutApp
│   ├── Features/
│   │   ├── Library/            # LibraryView, LibraryStore, MergeProgramsSheet
│   │   ├── ProgramDetail/      # ProgramDetailView, EditProgramSheet
│   │   ├── Workout/            # WorkoutSessionView, WorkoutSessionStore, RestTimerBar, SetRow
│   │   └── History/            # HistoryView, HistoryStore, SessionDetailView
│   ├── Support/                # Theme, Color+Hex, PreviewFixtures
│   └── Resources/              # Info.plist, Entitlements, Assets
│
├── ReelsShareExtension/        # iOS Share Extension Target
│   └── ShareViewController.swift
│
├── ReelsWorkoutTests/          # App-Level Integration & Lifecycle Tests
└── project.yml                 # XcodeGen Project Specification
```

---

## 🚀 빠른 시작 (Getting Started)

### 요구 사양 (Prerequisites)
- **macOS Sequoia** 또는 최신 버전
- **Xcode 16.0+** (Swift 6.0)
- **XcodeGen** (`brew install xcodegen`)
- **xcbeautify** (`brew install xcbeautify` - 선택 사항)

### 빌드 및 시뮬레이터 실행
```bash
# 1. 프로젝트 설정 및 Xcode 프로젝트 생성
make bootstrap

# 2. 빌드 및 iPhone 17 Pro 시뮬레이터 실행
make run

# 3. 전체 테스트 스위트 실행 (24개 테스트)
make test

# 4. ReelsKit 단위 테스트만 빠르게 실행
make unit
```

---

## 🧪 테스트 (Testing)

ReelsWorkout은 실제 네트워크 I/O 없이도 모든 시나리오를 빠르고 안전하게 검증할 수 있도록 설계되었습니다:
- **`WorkoutDraftTests`**: 중량 순방향 계승(Cascade), 세트 추가/삭제, 완료 세트 카운트 및 진행률 계산.
- **`WorkoutSessionStoreTests`**: 디바운스 세이브, 즉시 플러시, 휴식 카운트다운 타이머, 세션 라이프사이클.
- **`HistoryStoreTests`**: 과거 세션 파싱, 일자별 볼륨 필터링, 주간 대시보드 및 스트릭 계산.
- **`LibraryStoreTests`**: 릴스 인제스트 큐잉, 프로그램 삭제, 멀티 프로그램 병합.

```bash
$ make test
✔ Suite "HistoryStore" passed (4 tests)
✔ Suite "LibraryStore" passed (6 tests)
✔ Suite "WorkoutSessionStore" passed (7 tests)
✔ Suite "WorkoutSessionStore lifecycle" passed (7 tests)
** TEST SUCCEEDED ** (24 tests in 4 suites passed)
```

---

## 📄 License
Copyright © 2026 Douglas Min. All rights reserved.
