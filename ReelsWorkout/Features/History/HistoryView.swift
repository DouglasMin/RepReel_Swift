import ReelsKit
import SwiftUI

enum HistoryDisplayMode: String, CaseIterable, Identifiable {
    case calendar = "달력"
    case list = "전체 목록"

    var id: String { rawValue }
}

struct HistoryView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var store: HistoryStore?
    @State private var displayMode: HistoryDisplayMode = .calendar
    @State private var selectedDate: Date = Date()
    @State private var visibleMonth: Date = Date()

    var body: some View {
        NavigationStack {
            Group {
                if let store {
                    mainContent(store)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("운동 기록")
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("보기 방식", selection: $displayMode) {
                        ForEach(HistoryDisplayMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 170)
                }
            }
            .task {
                if store == nil {
                    store = HistoryStore(client: environment.client)
                }
                await store?.loadHistory()
            }
        }
    }

    @ViewBuilder
    private func mainContent(_ store: HistoryStore) -> some View {
        List {
            switch displayMode {
            case .calendar:
                calendarContent(store)
            case .list:
                listContent(store)
            }
        }
        .listStyle(.plain)
        .background(Theme.listBackground)
        .safeAreaInset(edge: .bottom) {
            if environment.workout != nil {
                Color.clear.frame(height: 64)
            }
        }
        .refreshable {
            await store.loadHistory()
        }
        .alert(
            "오류",
            isPresented: .init(
                get: { store.errorMessage != nil },
                set: { if !$0 { store.errorMessage = nil } }
            )
        ) {
            Button("확인", role: .cancel) { store.errorMessage = nil }
        } message: {
            Text(store.errorMessage ?? "")
        }
    }

    // MARK: - Calendar Mode

    @ViewBuilder
    private func calendarContent(_ store: HistoryStore) -> some View {
        Section {
            MonthCalendarView(
                visibleMonth: $visibleMonth,
                selectedDate: $selectedDate,
                store: store
            )
        }
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .listRowBackground(Color.clear)

        let daySessions = store.sessions(on: selectedDate)
        let formattedSelectedDate = selectedDate.formatted(
            .dateTime.month(.abbreviated).day().locale(Locale(identifier: "ko_KR"))
        )

        Section {
            if daySessions.isEmpty {
                HStack(spacing: 14) {
                    ZStack {
                        Circle()
                            .fill(Color.secondary.opacity(0.12))
                            .frame(width: 44, height: 44)
                        Image(systemName: "bed.double.fill")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 3) {
                        Text("\(formattedSelectedDate) — 휴식일")
                            .font(.subheadline.weight(.semibold))
                        Text("이 날짜에는 완료된 운동 기록이 없습니다.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
                .padding(14)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.cardBackground)
                )
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
            } else {
                ForEach(daySessions) { session in
                    NavigationLink(destination: SessionDetailView(session: session)) {
                        SessionHistoryCard(session: session)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                    .listRowBackground(Color.clear)
                }
            }
        } header: {
            HStack {
                Text("\(formattedSelectedDate)의 운동")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                Spacer()
                if !daySessions.isEmpty {
                    let totalVol = store.dailyVolumeKg(on: selectedDate)
                    Text("총 \(totalVol.formatted(.number.precision(.fractionLength(0...1)))) kg")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.brandPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Theme.brandPrimary.opacity(0.12), in: .capsule)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
    }

    // MARK: - List Mode

    @ViewBuilder
    private func listContent(_ store: HistoryStore) -> some View {
        if !store.sessions.isEmpty {
            Section {
                WeeklyDashboardCard(store: store)
            }
            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
            .listRowBackground(Color.clear)
        }

        Section {
            if store.sessions.isEmpty && !store.isLoading {
                ContentUnavailableView(
                    "아직 완료한 운동이 없습니다",
                    systemImage: "chart.bar.xaxis",
                    description: Text("루틴에서 운동을 시작하고 '운동 끝내기'를 누르면 이곳에 볼륨 분석과 일지가 기록됩니다.")
                )
                .padding(.vertical, 32)
            }

            ForEach(store.sessions) { session in
                NavigationLink(destination: SessionDetailView(session: session)) {
                    SessionHistoryCard(session: session)
                }
                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
                .listRowBackground(Color.clear)
            }
        } header: {
            if !store.sessions.isEmpty {
                Text("완료한 운동 목록")
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 16)
            }
        }
    }
}

// MARK: - Month Calendar View

private struct MonthCalendarView: View {
    @Binding var visibleMonth: Date
    @Binding var selectedDate: Date
    let store: HistoryStore

    private let calendar = Calendar.current
    private let weekdays = ["일", "월", "화", "수", "목", "금", "토"]
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 7)

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.dateFormat = "yyyy년 M월"
        return formatter.string(from: visibleMonth)
    }

    private var daysInMonth: [Date?] {
        guard let monthInterval = calendar.dateInterval(of: .month, for: visibleMonth),
              let firstDayOfWeek = calendar.dateComponents([.weekday], from: monthInterval.start).weekday,
              let numberOfDays = calendar.range(of: .day, in: .month, for: visibleMonth)?.count
        else { return [] }

        var days: [Date?] = []
        for _ in 1..<firstDayOfWeek {
            days.append(nil)
        }
        for day in 1...numberOfDays {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: monthInterval.start) {
                days.append(date)
            }
        }
        return days
    }

    var body: some View {
        VStack(spacing: 14) {
            // Month switcher header
            HStack {
                Text(monthTitle)
                    .font(.headline.weight(.bold))
                Spacer()
                Button(action: previousMonth) {
                    Image(systemName: "chevron.left")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.brandPrimary)
                        .padding(6)
                }
                .buttonStyle(.plain)

                Button(action: today) {
                    Text("오늘")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.brandPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Theme.brandPrimary.opacity(0.12), in: .capsule)
                }
                .buttonStyle(.plain)

                Button(action: nextMonth) {
                    Image(systemName: "chevron.right")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(Theme.brandPrimary)
                        .padding(6)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 4)

            // Weekday labels
            HStack {
                ForEach(weekdays.indices, id: \.self) { idx in
                    Text(weekdays[idx])
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(idx == 0 ? Color.red.opacity(0.8) : (idx == 6 ? Color.blue.opacity(0.8) : .secondary))
                        .frame(maxWidth: .infinity)
                }
            }

            // Days grid
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(daysInMonth.indices, id: \.self) { index in
                    if let dayDate = daysInMonth[index] {
                        DayCell(
                            date: dayDate,
                            isSelected: calendar.isDate(dayDate, inSameDayAs: selectedDate),
                            isToday: calendar.isDateInToday(dayDate),
                            hasWorkout: store.hasWorkout(on: dayDate, calendar: calendar),
                            onTap: { selectedDate = dayDate }
                        )
                    } else {
                        Color.clear
                            .frame(height: 40)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.brandPrimary.opacity(0.15), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
        )
    }

    private func previousMonth() {
        if let prev = calendar.date(byAdding: .month, value: -1, to: visibleMonth) {
            visibleMonth = prev
        }
    }

    private func nextMonth() {
        if let next = calendar.date(byAdding: .month, value: 1, to: visibleMonth) {
            visibleMonth = next
        }
    }

    private func today() {
        visibleMonth = Date()
        selectedDate = Date()
    }
}

private struct DayCell: View {
    let date: Date
    let isSelected: Bool
    let isToday: Bool
    let hasWorkout: Bool
    let onTap: () -> Void

    private var dayString: String {
        String(Calendar.current.component(.day, from: date))
    }

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 2) {
                Text(dayString)
                    .font(.subheadline.weight(isSelected ? .bold : (isToday ? .bold : .medium)))
                    .foregroundStyle(isSelected ? .white : (isToday ? Theme.brandPrimary : .primary))

                Circle()
                    .fill(hasWorkout ? (isSelected ? .white : Theme.brandPrimary) : Color.clear)
                    .frame(width: 5, height: 5)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(
                Group {
                    if isSelected {
                        Circle().fill(Theme.brandGradient)
                    } else if isToday {
                        Circle().strokeBorder(Theme.brandPrimary.opacity(0.4), lineWidth: 1.5)
                    }
                }
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Components

private struct WeeklyDashboardCard: View {
    let store: HistoryStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Header: Streak & Comparison Badge
            HStack(alignment: .center) {
                HStack(spacing: 6) {
                    Image(systemName: "flame.fill")
                        .font(.subheadline)
                        .foregroundStyle(Theme.brandGradient)
                    Text(store.currentStreakDays > 0 ? "\(store.currentStreakDays)일 연속 운동 달성!" : "이번 주 \(store.weeklySessionCount)회 운동")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.primary)
                }

                Spacer()

                if let percentage = store.weekOverWeekPercentage {
                    HStack(spacing: 3) {
                        Image(systemName: percentage >= 0 ? "arrow.up.right" : "arrow.down.right")
                        Text("\(abs(percentage).formatted(.number.precision(.fractionLength(0...1))))%")
                    }
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(percentage >= 0 ? Color(hex: "#34C759") : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(
                        (percentage >= 0 ? Color(hex: "#34C759") : Color.secondary).opacity(0.12),
                        in: .capsule
                    )
                }
            }

            // Big Metric Tonnage
            VStack(alignment: .leading, spacing: 2) {
                Text("이번 주 총 볼륨")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("\(store.thisWeekVolumeKg.formatted(.number.precision(.fractionLength(0...1))))")
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(Theme.brandPrimary)
                        .monospacedDigit()
                    Text("kg")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text("총 \(store.weeklySetsCount)세트 · \(store.weeklySessionCount)회 완료")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                }
            }

            // 7-Day Mini Bar Chart
            let maxVol = max(1.0, store.currentWeekDays.map(\.volumeKg).max() ?? 1.0)
            HStack(alignment: .bottom, spacing: 8) {
                ForEach(store.currentWeekDays) { day in
                    VStack(spacing: 6) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 4)
                                .fill(Color.primary.opacity(0.06))
                                .frame(height: 48)

                            if day.volumeKg > 0 {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(day.isToday ? Theme.brandGradient : LinearGradient(colors: [Theme.brandPrimary.opacity(0.7), Theme.brandSecondary.opacity(0.7)], startPoint: .top, endPoint: .bottom))
                                    .frame(height: max(10, 48 * CGFloat(day.volumeKg / maxVol)))
                                    .animation(.spring(duration: 0.5), value: day.volumeKg)
                            }
                        }

                        Text(day.dayName)
                            .font(.caption2.weight(day.isToday ? .bold : .regular))
                            .foregroundStyle(day.isToday ? Theme.brandPrimary : .secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.top, 4)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Theme.brandPrimary.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.04), radius: 8, y: 3)
        )
    }
}

private struct SessionHistoryCard: View {
    let session: WorkoutSessionLog

    private var formattedDate: String {
        guard let loggedAt = session.loggedAt else { return "-" }
        let date = Date(timeIntervalSince1970: TimeInterval(loggedAt))
        return date.formatted(date: .omitted, time: .shortened)
    }

    private var durationString: String? {
        guard let duration = session.durationSeconds, duration > 0 else { return nil }
        let minutes = duration / 60
        return "\(minutes)분"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.programId)
                        .font(.headline.weight(.semibold))
                        .lineLimit(1)
                    Text(formattedDate)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let volume = session.volumeAnalytics?.totalVolumeKg {
                    Text("\(volume.formatted(.number.precision(.fractionLength(0...1)))) kg")
                        .font(.subheadline.monospacedDigit().weight(.bold))
                        .foregroundStyle(Theme.brandPrimary)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Theme.brandPrimary.opacity(0.12), in: .capsule)
                }
            }

            HStack(spacing: 12) {
                if let dayNum = session.dayNumber as Int?, dayNum > 0 {
                    Text("Day \(dayNum)")
                        .font(.caption2.weight(.bold))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2.5)
                        .background(.secondary.opacity(0.15), in: .capsule)
                }

                if let duration = durationString {
                    Label(duration, systemImage: "timer")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let sets = session.volumeAnalytics?.totalSetsCompleted {
                    Text("\(sets)세트")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let notes = session.sessionNotes, !notes.isEmpty {
                    Image(systemName: "text.bubble.fill")
                        .font(.caption)
                        .foregroundStyle(Theme.brandPrimary.opacity(0.8))
                }

                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary.opacity(0.5))
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Color.primary.opacity(0.05), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.03), radius: 6, y: 2)
        )
    }
}

#if DEBUG
#Preview("운동 기록 탭") {
    HistoryView()
        .environment(PreviewFixtures.environment())
}
#endif
