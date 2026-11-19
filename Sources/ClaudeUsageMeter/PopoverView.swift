import SwiftUI

struct PopoverView: View {
    let service: UsageService
    let updater: Updater
    let statusLine: StatusLineInstaller

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

                Toggle("Launch at login", isOn: Binding(
                    get: { service.launchAtLogin },
                    set: { service.setLaunchAtLogin($0) }))
                    .toggleStyle(.checkbox)

                Toggle("Update automatically", isOn: Binding(
                    get: { updater.automatic },
                    set: { updater.setAutomatic($0) }))
                    .toggleStyle(.checkbox)
                    .disabled(updater.currentVersion == nil)

                HStack {
                    Text(updater.statusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Spacer()
                    Button(updateActionTitle) {
                        Task { await updater.check(install: updateActionInstalls) }
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .disabled(updater.currentVersion == nil || updater.isBusy)
                }

                if statusLine.isAvailable {
                    statusLineRow
                }

                Button("Quit") { NSApp.terminate(nil) }
                    .buttonStyle(.borderless)
            }
            .padding(16)
            .frame(width: 280)
        }
    }

    @ViewBuilder
    private var statusLineRow: some View {
        if statusLine.isInstalled && !statusLine.needsIdleRefresh {
            Label("Claude Code status line installed", systemImage: "checkmark.circle.fill")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Button(statusLine.isInstalled ? "Keep status line fresh while idle" : "Set up Claude Code status line") {
                    Task { await statusLine.install() }
                }
                .buttonStyle(.borderless)
                .disabled(statusLine.isBusy)
                .help("Updates the statusLine entry in ~/.claude/settings.json")
                if let error = statusLine.error {
                    Text(error).font(.caption).foregroundStyle(.orange)
                }
            }
        }
    }

    /// With automatic updates off, the first press only finds the update; the second installs it.
    private var updateActionInstalls: Bool {
        if case .available = updater.status { return true }
        return updater.automatic
    }

    private var updateActionTitle: String {
        if case .available = updater.status { return "Install" }
        return "Check now"
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
                Text(window.map { "\($0.percent)%" } ?? "—")
                    .font(.subheadline.monospacedDigit().weight(.semibold))
            }

            GeometryReader { geo in
                let pct = min(max((window?.utilization ?? 0) / 100, 0), 1)
                ZStack(alignment: .leading) {
                    // Square-ended fill clipped to the rounded track (same as the menu bar icon),
                    // so a tiny percentage doesn't collapse into a squarish pill.
                    ZStack(alignment: .leading) {
                        Rectangle().fill(.quaternary)
                        Rectangle()
                            .fill(Color(nsColor: BarRenderer.color(for: severity)))
                            .frame(width: geo.size.width * pct)
                    }
                    .clipShape(Capsule())
                    // No pace to judge once the window is blocked (matches the menu bar).
                    if severity != .exhausted,
                       let elapsed = window?.elapsedFraction(windowLength: kind.length, now: now) {
                        Rectangle()
                            .fill(.primary)
                            .frame(width: 2, height: geo.size.height + 6)
                            .offset(x: min(max(geo.size.width * elapsed - 1, 0), geo.size.width - 2))
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

    /// Explains an orange/red bar relative to the elapsed-time marker.
    private var paceNote: String? {
        guard let window, let elapsed = window.elapsedFraction(windowLength: kind.length, now: now),
              severity > .normal else { return nil }
        let ahead = max(Int((window.utilization - elapsed * 100).rounded()), 1)
        let left = max(Int((100 - window.utilization).rounded()), 0)
        return severity == .critical
            ? "\(ahead) pts ahead of pace · only \(left)% left"
            : "\(ahead) pts ahead of pace"
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
        return m > 0 ? "\(m)m" : "under 1m"
    }
}
