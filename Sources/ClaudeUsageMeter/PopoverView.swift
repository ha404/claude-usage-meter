import SwiftUI

struct PopoverView: View {
    let service: UsageService

    var body: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            VStack(alignment: .leading, spacing: 14) {
                Text("Claude Usage").font(.headline)

                ForEach(WindowKind.allCases, id: \.self) { kind in
                    WindowRow(kind: kind, window: service.usage?.window(kind), now: context.date)
                }

                if let error = service.error {
                    Label(error, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }

                Divider()

                HStack {
                    if let updated = service.lastUpdated {
                        Text("Updated \(updated, format: .relative(presentation: .named))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button {
                        Task { await service.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(service.isLoading)
                }

                // Bindable(...) instead of @State/@Bindable: the Command Line Tools ship without SwiftUI's macro plugins.
                Toggle("Launch at login", isOn: Bindable(service).launchAtLogin)
                    .toggleStyle(.checkbox)

                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
            }
            .padding(16)
            .frame(width: 280)
        }
    }
}

private struct WindowRow: View {
    let kind: WindowKind
    let window: UsageWindow?
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(kind.title).font(.subheadline.weight(.medium))
                Spacer()
                Text(window.map { "\(Int($0.utilization.rounded()))%" } ?? "—")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }

            GeometryReader { geo in
                let pct = min(max((window?.utilization ?? 0) / 100, 0), 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule()
                        .fill(Color(nsColor: BarRenderer.color(for: severity)))
                        .frame(width: geo.size.width * pct)
                    if let elapsed = window?.elapsedFraction(windowLength: kind.length, now: now) {
                        Rectangle()
                            .fill(.primary)
                            .frame(width: 2, height: geo.size.height + 6)
                            .offset(x: geo.size.width * elapsed - 1)
                    }
                }
            }
            .frame(height: 8)

            if let resetsAt = window?.resetsAt {
                if severity == .exhausted {
                    Label("Limit reached · back \(resetsAt.formatted(resetFormat)) (in \(remaining(until: resetsAt)))",
                          systemImage: "exclamationmark.octagon.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.red)
                } else {
                    Text("Resets in \(remaining(until: resetsAt)) · \(resetsAt.formatted(resetFormat))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let note = paceNote {
                        Text(note)
                            .font(.caption)
                            .foregroundStyle(Color(nsColor: BarRenderer.color(for: severity)))
                    }
                }
            }
        }
    }

    private var severity: Severity {
        window?.severity(windowLength: kind.length, now: now) ?? .normal
    }

    /// Explains a warning color that comes from pace rather than the raw percentage.
    private var paceNote: String? {
        guard let window, let elapsed = window.elapsedFraction(windowLength: kind.length, now: now),
              severity > .normal else { return nil }
        let ahead = Int((window.utilization - elapsed * 100).rounded())
        return ahead > 10 ? "\(ahead) pts ahead of pace" : nil
    }

    private var resetFormat: Date.FormatStyle {
        kind == .fiveHour
            ? .dateTime.hour().minute()
            : .dateTime.weekday(.abbreviated).hour().minute()
    }

    private func remaining(until date: Date) -> String {
        let secs = max(Int(date.timeIntervalSince(now)), 0)
        let d = secs / 86400, h = (secs % 86400) / 3600, m = (secs % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}
