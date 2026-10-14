import AppKit
import NetMonCore

final class StatusBarSummaryView: NSView {
    private static let font = NSFont.monospacedDigitSystemFont(
        ofSize: 8.5,
        weight: .regular
    )
    private static let labelFont = NSFont.systemFont(
        ofSize: 8.5,
        weight: .regular
    )
    private static let separatorX: CGFloat = 62
    private static let lineHeight: CGFloat = 10
    private static let maximumNetworkNameLength = 6

    private var uploadSpeed = "0 B/s"
    private var downloadSpeed = "0 B/s"
    private var networkName = "—"
    private var usage = "0 B"

    override var isFlipped: Bool { true }

    func update(
        uploadSpeed: String,
        downloadSpeed: String,
        networkName: String,
        usage: String
    ) {
        let compactName = Self.compactNetworkName(networkName)
        guard self.uploadSpeed != uploadSpeed ||
            self.downloadSpeed != downloadSpeed ||
            self.networkName != compactName ||
            self.usage != usage
        else {
            needsDisplay = true
            return
        }

        self.uploadSpeed = uploadSpeed
        self.downloadSpeed = downloadSpeed
        self.networkName = compactName
        self.usage = usage
        needsDisplay = true
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        nil
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let highlighted = (superview as? NSButton)?.isHighlighted == true
        let textColor: NSColor = highlighted
            ? .selectedMenuItemTextColor
            : .labelColor
        let separatorColor = textColor.withAlphaComponent(0.55)
        let contentHeight = Self.lineHeight * 2
        let top = floor((bounds.height - contentHeight) / 2)

        drawText(
            "↑ \(uploadSpeed)",
            in: NSRect(
                x: 3,
                y: top,
                width: Self.separatorX - 6,
                height: Self.lineHeight
            ),
            font: Self.font,
            color: textColor
        )
        drawText(
            "↓ \(downloadSpeed)",
            in: NSRect(
                x: 3,
                y: top + Self.lineHeight,
                width: Self.separatorX - 6,
                height: Self.lineHeight
            ),
            font: Self.font,
            color: textColor
        )

        let separator = NSBezierPath()
        separator.move(to: NSPoint(x: Self.separatorX + 0.5, y: top + 1))
        separator.line(
            to: NSPoint(
                x: Self.separatorX + 0.5,
                y: top + contentHeight - 1
            )
        )
        separator.lineWidth = 1
        separatorColor.setStroke()
        separator.stroke()

        let usageX = Self.separatorX + 7
        let usageWidth = max(0, bounds.width - usageX - 2)
        drawText(
            networkName,
            in: NSRect(
                x: usageX,
                y: top,
                width: usageWidth,
                height: Self.lineHeight
            ),
            font: Self.labelFont,
            color: textColor,
            lineBreakMode: .byTruncatingTail
        )
        drawText(
            usage,
            in: NSRect(
                x: usageX,
                y: top + Self.lineHeight,
                width: usageWidth,
                height: Self.lineHeight
            ),
            font: Self.font,
            color: textColor
        )
    }

    private func drawText(
        _ value: String,
        in rect: NSRect,
        font: NSFont,
        color: NSColor,
        lineBreakMode: NSLineBreakMode = .byClipping
    ) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = lineBreakMode
        paragraph.alignment = .left
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        (value as NSString).draw(in: rect, withAttributes: attributes)
    }

    private static func compactNetworkName(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "—" }
        guard trimmed.count > maximumNetworkNameLength else { return trimmed }
        return String(trimmed.prefix(maximumNetworkNameLength - 1)) + "…"
    }
}

@MainActor
final class StatusBarPresentation {
    private static let summaryWidth: CGFloat = 104

    private var summaryView: StatusBarSummaryView?

    func configure(statusItem: NSStatusItem) {
        guard let button = statusItem.button else { return }

        statusItem.length = Self.summaryWidth
        button.image = nil
        button.title = ""
        button.imagePosition = .noImage
        button.setAccessibilityLabel("NetMon")

        let summaryView = StatusBarSummaryView()
        summaryView.translatesAutoresizingMaskIntoConstraints = false
        button.addSubview(summaryView)
        NSLayoutConstraint.activate([
            summaryView.leadingAnchor.constraint(equalTo: button.leadingAnchor),
            summaryView.trailingAnchor.constraint(equalTo: button.trailingAnchor),
            summaryView.topAnchor.constraint(equalTo: button.topAnchor),
            summaryView.bottomAnchor.constraint(equalTo: button.bottomAnchor),
        ])
        self.summaryView = summaryView
    }

    func update(
        statusItem: NSStatusItem?,
        uploadSpeed: String,
        downloadSpeed: String,
        networkNameLabel: String,
        currentNetworkName: String,
        todayTotal: String
    ) {
        guard let button = statusItem?.button else { return }

        summaryView?.update(
            uploadSpeed: uploadSpeed,
            downloadSpeed: downloadSpeed,
            networkName: networkNameLabel,
            usage: todayTotal
        )
        button.setAccessibilityLabel(
            L10n.format("NetMon，当前网络 {0}，上传速度 {1}，", currentNetworkName, uploadSpeed) +
                L10n.format("下载速度 {0}，", downloadSpeed) +
                L10n.format("当前网络今日总流量 {0}", todayTotal)
        )
    }

}
