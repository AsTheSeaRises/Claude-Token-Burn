import SwiftUI

struct DropdownView: View {
    @ObservedObject var viewModel: TokenBurnViewModel
    var onSettingsTap:  (() -> Void)?
    var onResetWindow:  (() -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider().padding(.vertical, 6)

            if let err = viewModel.errorMessage {
                errorSection(err)
            } else {
                sessionSection
                Divider().padding(.vertical, 6)
                weeklySection
                if viewModel.extraUsage?.isEnabled == true {
                    Divider().padding(.vertical, 6)
                    extraUsageSection
                }
            }

            Divider().padding(.vertical, 6)
            actionsSection
        }
        .padding(14)
        .frame(width: 300)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 6) {
            Image(systemName: "flame.fill")
                .foregroundColor(sessionColor)
            Text("Claude Token Burn")
                .font(.headline)
            Spacer()
            if viewModel.isLoading {
                ProgressView().scaleEffect(0.6)
            } else if let updated = viewModel.lastUpdated {
                Text(updated, style: .relative)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Session (5-hour)

    private var sessionSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionLabel("Current Session")

            progressBar(fraction: viewModel.sessionPercentRemaining / 100, color: sessionColor)
                .padding(.bottom, 2)

            row("Used", value: "\(viewModel.sessionUtilization)%", valueColor: sessionColor)
            row("Remaining", value: String(format: "%.0f%%", viewModel.sessionPercentRemaining))

            if let resets = viewModel.sessionResetsAt {
                row("Resets In", value: formatCountdown(resets))
                row("Resets At", value: formatTime(resets))
            }
        }
    }

    // MARK: - Weekly

    private var weeklySection: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionLabel("This Week")

            progressBar(fraction: Double(100 - viewModel.weeklyUtilization) / 100, color: weeklyColor)
                .padding(.bottom, 2)

            row("All Models", value: "\(viewModel.weeklyUtilization)% used", valueColor: weeklyColor)

            if let resets = viewModel.weeklyResetsAt {
                row("Resets", value: formatWeeklyReset(resets))
            }

            if let opus = viewModel.weeklyOpus {
                row("  Opus", value: "\(opus)% used")
            }
            if let sonnet = viewModel.weeklySonnet {
                row("  Sonnet", value: "\(sonnet)% used")
            }
        }
    }

    // MARK: - Extra Usage

    private var extraUsageSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionLabel("Extra Usage")
            if let extra = viewModel.extraUsage {
                let currency = extra.currency ?? "USD"
                let used     = extra.usedCredits.map { formatCredits($0, currency: currency) } ?? "—"
                let limit    = extra.monthlyLimit.map { formatCredits($0, currency: currency) } ?? "—"
                row("Spent", value: "\(used) / \(limit)")
            }
        }
    }

    // MARK: - Error

    private func errorSection(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.orange)
            Text(message)
                .font(.callout)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Actions

    private var actionsSection: some View {
        VStack(spacing: 2) {
            actionButton("arrow.clockwise", label: "Refresh Now") {
                viewModel.refresh()
            }
            actionButton("gearshape", label: "Settings…") {
                onSettingsTap?()
            }
            actionButton("xmark.circle", label: "Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }

    // MARK: - Reusable components

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .fontWeight(.semibold)
            .foregroundColor(.secondary)
            .textCase(.uppercase)
    }

    private func progressBar(fraction: Double, color: Color) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color(.separatorColor))
                    .frame(height: 5)
                RoundedRectangle(cornerRadius: 3)
                    .fill(color)
                    .frame(width: geo.size.width * CGFloat(max(0, min(1, fraction))), height: 5)
            }
        }
        .frame(height: 5)
    }

    @ViewBuilder
    private func row(_ label: String, value: String, valueColor: Color = .primary) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .font(.callout)
            Spacer()
            Text(value)
                .foregroundColor(valueColor)
                .font(.callout)
                .fontWeight(.medium)
                .monospacedDigit()
        }
    }

    @ViewBuilder
    private func actionButton(_ icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon).frame(width: 14)
                Text(label)
                Spacer()
            }
            .foregroundColor(.secondary)
            .font(.callout)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 2)
    }

    // MARK: - Colours

    private var sessionColor: Color {
        Constants.tokenColorSwiftUI(percentRemaining: viewModel.sessionPercentRemaining)
    }

    private var weeklyColor: Color {
        Constants.tokenColorSwiftUI(percentRemaining: Double(100 - viewModel.weeklyUtilization))
    }

    // MARK: - Formatters

    private func formatCountdown(_ date: Date) -> String {
        let secs = date.timeIntervalSinceNow
        guard secs > 0 else { return "Expired" }
        let h = Int(secs) / 3600
        let m = (Int(secs) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }

    private func formatTime(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateStyle = .none
        fmt.timeStyle = .short
        return fmt.string(from: date)
    }

    private func formatWeeklyReset(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "EEE h:mma"
        return fmt.string(from: date)
    }

    private func formatCredits(_ credits: Int, currency: String) -> String {
        let symbol = currency == "GBP" ? "£" : currency == "EUR" ? "€" : "$"
        return String(format: "%@%.2f", symbol, Double(credits) / 100.0)
    }
}
