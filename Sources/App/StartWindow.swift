import AppKit
import UniformTypeIdentifiers

/// Routes ⌘N to the start screen and creates typed untitled documents.
final class HWDocumentController: NSDocumentController {
    enum Kind { case document, presentation, spreadsheet }

    override func newDocument(_ sender: Any?) { StartWindowController.shared.showWindow(nil) }

    func create(_ kind: Kind) {
        let type: String
        switch kind {
        // The document format (hwp, docx, …) is chosen when saving.
        case .document: type = DocType.hwp
        case .presentation: type = DocType.pptx
        case .spreadsheet: type = DocType.xlsx
        }
        do {
            let doc = try makeUntitledDocument(ofType: type)
            addDocument(doc)
            doc.makeWindowControllers()
            doc.showWindows()
        } catch {
            presentError(error)
        }
    }

    @objc func newTextDocument(_ s: Any?) { create(.document) }
    @objc func newPresentation(_ s: Any?) { create(.presentation) }
    @objc func newSpreadsheet(_ s: Any?) { create(.spreadsheet) }

    /// Content types HanX registers as the Finder default for.
    static let defaultTypes = [DocType.hwp, DocType.hwpx, DocType.hwt, DocType.docx, DocType.xlsx, DocType.pptx]

    static func makeDefaultHandler(completion: @escaping ([String]) -> Void) {
        let app = Bundle.main.bundleURL
        var pending = Set(defaultTypes)
        var failed: [String] = []
        var finished = false
        func finish() {
            guard !finished else { return }
            finished = true
            // Requests LaunchServices has not answered yet are checked directly.
            for id in pending {
                if let t = UTType(id), NSWorkspace.shared.urlForApplication(toOpen: t)?.standardizedFileURL != app.standardizedFileURL { failed.append(id) }
            }
            completion(failed)
        }
        for id in defaultTypes {
            guard let t = UTType(id) else { failed.append(id); pending.remove(id); continue }
            NSWorkspace.shared.setDefaultApplication(at: app, toOpen: t) { err in
                DispatchQueue.main.async {
                    pending.remove(id)
                    if err != nil { failed.append(id) }
                    if pending.isEmpty { finish() }
                }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) { finish() }
    }

    @objc func setAsDefaultApp(_ s: Any?) {
        DefaultAppRegistration.shared.register { failed in
            let a = NSAlert()
            a.messageText = failed.isEmpty ? "HanX가 기본 앱으로 설정되었습니다" : "일부 형식을 설정하지 못했습니다"
            a.informativeText = failed.isEmpty
                ? "Finder에서 hwp, hwpx, hwt, docx, xlsx, pptx 파일을 열면 HanX가 형식에 맞는 편집기로 엽니다.\n되돌리려면 파일의 '정보 가져오기의 다음으로 열기'에서 다른 앱을 고르고 '모두 변경'을 누르세요."
                : failed.joined(separator: ", ")
            a.runModal()
        }
    }
}

/// Start screen: sidebar (brand, open, recent) + template gallery.
final class StartWindowController: NSWindowController {
    static let shared = StartWindowController()

    private let recentList = NSStackView()
    private let emptyRecent = NSTextField(labelWithString: "최근 문서 없음")
    private let clearRecentButton = NSButton()
    private let makeDefaultButton = NSButton()
    private let recentDocuments: RecentDocumentStore
    private let defaultRegistration: DefaultAppRegistration

    init(recentDocuments: RecentDocumentStore = NSDocumentController.shared,
         defaultRegistration: DefaultAppRegistration = .shared) {
        self.recentDocuments = recentDocuments
        self.defaultRegistration = defaultRegistration
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 640),
                         styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView], backing: .buffered, defer: false)
        w.titleVisibility = .hidden
        w.titlebarAppearsTransparent = true
        w.isMovableByWindowBackground = true
        HWTheme.style(w)
        w.backgroundColor=HWTheme.paper
        super.init(window: w)
        build()
        rebuildRecent()
        NotificationCenter.default.addObserver(self, selector: #selector(defaultRegistrationCompleted(_:)),
                                               name: DefaultAppRegistration.didComplete, object: defaultRegistration)
        w.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func showWindow(_ sender: Any?) {
        rebuildRecent()
        makeDefaultButton.isHidden = defaultRegistration.isComplete
        super.showWindow(sender)
        window?.makeKeyAndOrderFront(nil)
    }

    private var controller: HWDocumentController? { NSDocumentController.shared as? HWDocumentController }

    private func build() {
        guard let content = window?.contentView else { return }

        // Sidebar
        let side = HWSurfaceView()
        side.fill=HWTheme.toolbar
        side.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(side)

        let icon = NSImageView(image: NSApp.applicationIconImage ?? NSImage())
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.translatesAutoresizingMaskIntoConstraints = false
        let name = NSTextField(labelWithString: "HanX")
        name.font = HWTheme.font(30,weight:.semibold)
        name.textColor=HWTheme.ink
        let brand = NSStackView(views: [icon, name])
        brand.orientation = .vertical
        brand.alignment = .leading
        brand.spacing = 4
        brand.setCustomSpacing(12, after: icon)

        let newButton = SidebarButton(title: "새로 만들기", symbol: "plus.square.fill", selected: true, target: nil, action: nil)
        let openButton = SidebarButton(title: "열기…", symbol: "folder", selected: false, target: self, action: #selector(openFile(_:)))
        let nav = NSStackView(views: [newButton, openButton])
        nav.orientation = .vertical
        nav.alignment = .leading
        nav.spacing = 4

        makeDefaultButton.title = "기본 앱으로 설정"
        makeDefaultButton.target = self
        makeDefaultButton.action = #selector(makeDefault(_:))
        makeDefaultButton.bezelStyle = .smallSquare
        makeDefaultButton.isBordered = true
        makeDefaultButton.font = HWTheme.font(12)
        makeDefaultButton.isHidden = defaultRegistration.isComplete
        makeDefaultButton.toolTip = "HanX를 지원 문서 형식의 기본 앱으로 설정합니다."

        for v in [brand, nav, makeDefaultButton] { v.translatesAutoresizingMaskIntoConstraints = false; side.addSubview(v) }

        // Main area
        let title = NSTextField(labelWithString: "새로 만들기")
        title.font = HWTheme.font(27,weight:.semibold)
        title.textColor=HWTheme.ink

        let tiles = NSStackView(views: [
            TemplateTile(kind: .document, title: "새 문서", caption: "HWP, HWPX, DOCX", target: self, action: #selector(newDoc(_:))),
            TemplateTile(kind: .presentation, title: "새 프레젠테이션", caption: "PPTX", target: self, action: #selector(newSlides(_:))),
            TemplateTile(kind: .spreadsheet, title: "새 도표", caption: "XLSX, CSV", target: self, action: #selector(newSheet(_:))),
        ])
        tiles.spacing = 24
        tiles.alignment = .top

        let recentTitle = NSTextField(labelWithString: "최근 문서")
        recentTitle.font = .systemFont(ofSize: 15, weight: .semibold)
        clearRecentButton.title = "모두 지우기"
        clearRecentButton.target = self
        clearRecentButton.action = #selector(clearRecent(_:))
        clearRecentButton.isBordered = false
        clearRecentButton.font = HWTheme.font(11)
        clearRecentButton.contentTintColor = .secondaryLabelColor
        clearRecentButton.toolTip = "최근 문서 목록을 비웁니다. 파일은 삭제하지 않습니다."
        let recentHeading = NSView()
        recentHeading.translatesAutoresizingMaskIntoConstraints = false
        for view in [recentTitle, clearRecentButton] {
            view.translatesAutoresizingMaskIntoConstraints = false
            recentHeading.addSubview(view)
        }
        NSLayoutConstraint.activate([
            recentHeading.widthAnchor.constraint(equalToConstant: 636),
            recentHeading.heightAnchor.constraint(equalToConstant: 22),
            recentTitle.leadingAnchor.constraint(equalTo: recentHeading.leadingAnchor),
            recentTitle.centerYAnchor.constraint(equalTo: recentHeading.centerYAnchor),
            clearRecentButton.trailingAnchor.constraint(equalTo: recentHeading.trailingAnchor, constant: -4),
            clearRecentButton.centerYAnchor.constraint(equalTo: recentHeading.centerYAnchor),
        ])
        recentList.orientation = .vertical
        recentList.alignment = .leading
        recentList.spacing = 2
        emptyRecent.textColor = .tertiaryLabelColor

        let main = NSStackView(views: [title, tiles, recentHeading, recentList])
        main.orientation = .vertical
        main.alignment = .leading
        main.spacing = 8
        main.setCustomSpacing(28, after: title)
        main.setCustomSpacing(36, after: tiles)
        main.setCustomSpacing(10, after: recentHeading)
        main.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(main)

        NSLayoutConstraint.activate([
            side.leadingAnchor.constraint(equalTo: content.leadingAnchor), side.topAnchor.constraint(equalTo: content.topAnchor),
            side.bottomAnchor.constraint(equalTo: content.bottomAnchor), side.widthAnchor.constraint(equalToConstant: 236),
            icon.widthAnchor.constraint(equalToConstant: 60), icon.heightAnchor.constraint(equalToConstant: 60),
            brand.leadingAnchor.constraint(equalTo: side.leadingAnchor, constant: 24), brand.topAnchor.constraint(equalTo: side.topAnchor, constant: 56),
            nav.leadingAnchor.constraint(equalTo: side.leadingAnchor, constant: 14), nav.trailingAnchor.constraint(equalTo: side.trailingAnchor, constant: -14),
            nav.topAnchor.constraint(equalTo: brand.bottomAnchor, constant: 34),
            newButton.widthAnchor.constraint(equalTo: nav.widthAnchor), openButton.widthAnchor.constraint(equalTo: nav.widthAnchor),
            makeDefaultButton.leadingAnchor.constraint(equalTo: side.leadingAnchor, constant: 24),
            makeDefaultButton.trailingAnchor.constraint(equalTo: side.trailingAnchor, constant: -24),
            makeDefaultButton.heightAnchor.constraint(equalToConstant: 30),
            makeDefaultButton.bottomAnchor.constraint(equalTo: side.bottomAnchor, constant: -22),
            main.leadingAnchor.constraint(equalTo: side.trailingAnchor, constant: 44), main.topAnchor.constraint(equalTo: content.topAnchor, constant: 56),
            main.trailingAnchor.constraint(lessThanOrEqualTo: content.trailingAnchor, constant: -40),
        ])
    }

    private func rebuildRecent() {
        recentList.arrangedSubviews.forEach { $0.removeFromSuperview() }
        let urls = recentDocuments.recentDocumentURLs.prefix(5)
        clearRecentButton.isHidden = urls.isEmpty
        if urls.isEmpty { recentList.addArrangedSubview(emptyRecent); return }
        for url in urls {
            let row = RecentRow(url: url, target: self, action: #selector(openRecent(_:))) { [weak self] url in
                guard let self else { return }
                RecentDocumentHistory.remove(url, from: self.recentDocuments)
                self.rebuildRecent()
            }
            recentList.addArrangedSubview(row)
        }
    }

    @objc private func clearRecent(_ sender: Any?) {
        recentDocuments.clearRecentDocuments(sender)
        rebuildRecent()
    }

    @objc private func defaultRegistrationCompleted(_ notification: Notification) {
        makeDefaultButton.isHidden = defaultRegistration.isComplete
    }

    @objc private func makeDefault(_ sender: Any?) {
        makeDefaultButton.isEnabled = false
        defaultRegistration.register { [weak self] failed in
            guard let self else { return }
            self.makeDefaultButton.isEnabled = true
            self.makeDefaultButton.isHidden = self.defaultRegistration.isComplete
            if !failed.isEmpty {
                let alert = NSAlert()
                alert.messageText = "일부 형식을 설정하지 못했습니다"
                alert.informativeText = failed.joined(separator: ", ")
                if let window = self.window { alert.beginSheetModal(for: window) }
            }
        }
    }

    @objc private func newDoc(_ s: Any?) { close(); controller?.create(.document) }
    @objc private func newSlides(_ s: Any?) { close(); controller?.create(.presentation) }
    @objc private func newSheet(_ s: Any?) { close(); controller?.create(.spreadsheet) }
    @objc private func openFile(_ s: Any?) { close(); NSDocumentController.shared.openDocument(nil) }
    @objc private func openRecent(_ s: RecentRow) {
        close()
        NSDocumentController.shared.openDocument(withContentsOf: s.url, display: true) { _, _, e in
            if let e { NSApp.presentError(e) }
        }
    }
}

/// Clickable view with hover feedback, the base of tiles and rows.
class HoverControl: NSControl {
    var hovering = false { didSet { needsDisplay = true; hoverChanged() } }
    private var area: NSTrackingArea?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let area { removeTrackingArea(area) }
        area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self)
        addTrackingArea(area!)
    }

    override func mouseEntered(with event: NSEvent) { hovering = true }
    override func mouseExited(with event: NSEvent) { hovering = false }
    override var acceptsFirstResponder:Bool { true }
    override init(frame:NSRect) { super.init(frame:frame); focusRingType = .exterior; setAccessibilityElement(true); setAccessibilityRole(.button) }
    required init?(coder:NSCoder) { super.init(coder:coder) }
    override var focusRingMaskBounds:NSRect { bounds }
    override func drawFocusRingMask() { NSBezierPath(roundedRect:bounds,xRadius:4,yRadius:4).fill() }
    override func accessibilityPerformPress()->Bool { guard isEnabled else { return false }; return sendAction(action,to:target) }
    override func keyDown(with event:NSEvent) { if event.keyCode == 36 || event.keyCode == 49 { _=accessibilityPerformPress() } else { super.keyDown(with:event) } }
    override func mouseDown(with event: NSEvent) { window?.makeFirstResponder(self) }
    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) { sendAction(action, to: target) }
    }
    override func resetCursorRects() { addCursorRect(bounds, cursor: .pointingHand) }
    func hoverChanged() {}
}

final class TemplateTile: HoverControl {
    let kind: HWDocumentController.Kind
    private let preview = TilePreview()

    init(kind: HWDocumentController.Kind, title: String, caption: String, target: AnyObject, action: Selector) {
        self.kind = kind
        super.init(frame: .zero)
        self.target = target
        self.action = action
        setAccessibilityLabel(title)
        preview.kind = kind
        let t = NSTextField(labelWithString: title)
        t.font = .systemFont(ofSize: 14, weight: .semibold)
        let c = NSTextField(labelWithString: caption)
        c.font = .systemFont(ofSize: 11.5)
        c.textColor = .secondaryLabelColor
        for v in [preview, t, c] as [NSView] { v.translatesAutoresizingMaskIntoConstraints = false; addSubview(v) }
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 196),
            preview.topAnchor.constraint(equalTo: topAnchor), preview.leadingAnchor.constraint(equalTo: leadingAnchor),
            preview.trailingAnchor.constraint(equalTo: trailingAnchor), preview.heightAnchor.constraint(equalToConstant: 150),
            t.topAnchor.constraint(equalTo: preview.bottomAnchor, constant: 12), t.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            c.topAnchor.constraint(equalTo: t.bottomAnchor, constant: 2), c.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2),
            c.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }
    override func hoverChanged() { preview.hovering = hovering }
}

/// Miniature of each kind of file, drawn rather than bitmapped so it stays
/// crisp at any scale and in dark mode.
final class TilePreview: NSView {
    var kind: HWDocumentController.Kind = .document
    var hovering = false { didSet { needsDisplay = true } }
    override var isFlipped: Bool { true }

    var accent: NSColor {
        switch kind {
        case .document: return HWTheme.accent
        case .presentation: return NSColor(srgbRed:0.61,green:0.34,blue:0.19,alpha:1)
        case .spreadsheet: return NSColor(srgbRed:0.21,green:0.44,blue:0.36,alpha:1)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let card = bounds.insetBy(dx: 1.5, dy: 1.5)
        let shape = NSBezierPath(roundedRect: card, xRadius: 5, yRadius: 5)
        (hovering ? HWTheme.selection : HWTheme.toolbar).setFill()
        shape.fill()
        (hovering ? accent : HWTheme.border).setStroke()
        shape.lineWidth = hovering ? 2 : 1
        shape.stroke()

        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowBlurRadius = 2
        shadow.shadowOffset = NSSize(width: 0, height: -2)
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.08)
        shadow.set()
        let paper: NSRect
        switch kind {
        case .document: paper = NSRect(x: card.midX - 44, y: 16, width: 88, height: card.height - 32)
        case .presentation: paper = NSRect(x: card.midX - 74, y: 36, width: 148, height: 84)
        case .spreadsheet: paper = NSRect(x: card.midX - 72, y: 24, width: 144, height: 104)
        }
        NSColor.white.setFill()
        NSBezierPath(roundedRect: paper, xRadius: 3, yRadius: 3).fill()
        NSGraphicsContext.restoreGraphicsState()

        let gray = HWTheme.border
        func bar(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat = 3, _ c: NSColor? = nil) {
            (c ?? gray).setFill()
            NSBezierPath(roundedRect: NSRect(x: x, y: y, width: w, height: h), xRadius: h / 2, yRadius: h / 2).fill()
        }
        switch kind {
        case .document:
            let x = paper.minX + 10, w = paper.width - 20
            bar(x + 14, paper.minY + 12, w - 28, 5, accent)
            for (i, f) in [1.0, 0.92, 0.97, 0.7].enumerated() { bar(x, paper.minY + 26 + CGFloat(i) * 7, w * f) }
            let t = NSRect(x: x, y: paper.minY + 58, width: w, height: 26)
            NSColor(white: 0.7, alpha: 1).setStroke()
            let tp = NSBezierPath(rect: t); tp.lineWidth = 0.6; tp.stroke()
            accent.withAlphaComponent(0.15).setFill(); NSRect(x: t.minX, y: t.minY, width: t.width, height: 8.7).fill()
            for k in 1..<3 { NSBezierPath.strokeLine(from: NSPoint(x: t.minX, y: t.minY + CGFloat(k) * 8.7), to: NSPoint(x: t.maxX, y: t.minY + CGFloat(k) * 8.7)) }
            NSBezierPath.strokeLine(from: NSPoint(x: t.minX + w / 3, y: t.minY), to: NSPoint(x: t.minX + w / 3, y: t.maxY))
            for (i, f) in [0.95, 0.8, 0.9].enumerated() { bar(x, paper.minY + 92 + CGFloat(i) * 7, w * f) }
        case .presentation:
            accent.setFill()
            NSBezierPath(rect: NSRect(x: paper.minX, y: paper.minY, width: 6, height: paper.height)).fill()
            bar(paper.minX + 18, paper.minY + 14, 80, 6, NSColor(white: 0.3, alpha: 1))
            for i in 0..<3 {
                accent.setFill()
                NSBezierPath(ovalIn: NSRect(x: paper.minX + 18, y: paper.minY + 31 + CGFloat(i) * 11, width: 4, height: 4)).fill()
                bar(paper.minX + 26, paper.minY + 31.5 + CGFloat(i) * 11, [52, 44, 58][i])
            }
            for (i, h) in [18.0, 30, 24, 38].enumerated() {
                (i == 3 ? accent : accent.withAlphaComponent(0.45)).setFill()
                NSRect(x: paper.maxX - 50 + CGFloat(i) * 10, y: paper.maxY - 12 - h, width: 7, height: h).fill()
            }
        case .spreadsheet:
            let cols = 5, rows = 7
            let cw = paper.width / CGFloat(cols), rh = paper.height / CGFloat(rows)
            accent.withAlphaComponent(0.85).setFill()
            NSRect(x: paper.minX, y: paper.minY, width: paper.width, height: rh).fill()
            accent.withAlphaComponent(0.12).setFill()
            for r in stride(from: 2, to: rows, by: 2) { NSRect(x: paper.minX, y: paper.minY + CGFloat(r) * rh, width: paper.width, height: rh).fill() }
            NSColor(white: 0.8, alpha: 1).setStroke()
            for c in 1..<cols { NSBezierPath.strokeLine(from: NSPoint(x: paper.minX + CGFloat(c) * cw, y: paper.minY), to: NSPoint(x: paper.minX + CGFloat(c) * cw, y: paper.maxY)) }
            for r in 1..<rows { NSBezierPath.strokeLine(from: NSPoint(x: paper.minX, y: paper.minY + CGFloat(r) * rh), to: NSPoint(x: paper.maxX, y: paper.minY + CGFloat(r) * rh)) }
            for r in 1..<rows { for c in 0..<cols where (r + c) % 3 != 0 { bar(paper.minX + CGFloat(c) * cw + 4, paper.minY + CGFloat(r) * rh + rh / 2 - 1.5, cw * 0.55) } }
        }
    }
}

final class SidebarButton: HoverControl {
    private let selected: Bool

    init(title: String, symbol: String, selected: Bool, target: AnyObject?, action: Selector?) {
        self.selected = selected
        super.init(frame: .zero)
        self.target = target
        self.action = action
        let icon = NSImageView(image: NSImage(systemSymbolName: symbol, accessibilityDescription: title)!)
        icon.contentTintColor = selected ? .controlAccentColor : .secondaryLabelColor
        let label = NSTextField(labelWithString: title)
        label.font = .systemFont(ofSize: 13, weight: selected ? .semibold : .regular)
        let row = NSStackView(views: [icon, label])
        row.spacing = 8
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            heightAnchor.constraint(equalToConstant: 30),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 10), row.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        guard selected || hovering else { return }
        (selected ? NSColor.controlAccentColor.withAlphaComponent(0.14) : NSColor.labelColor.withAlphaComponent(0.06)).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 7, yRadius: 7).fill()
    }
}

final class RecentRow: HoverControl {
    let url: URL
    private let removeButton = NSButton()
    private let removeAction: ((URL) -> Void)?

    init(url: URL, target: AnyObject, action: Selector, removeAction: ((URL) -> Void)? = nil) {
        self.url = url
        self.removeAction = removeAction
        super.init(frame: .zero)
        self.target = target
        self.action = action
        let icon = NSImageView(image: NSWorkspace.shared.icon(forFile: url.path))
        icon.translatesAutoresizingMaskIntoConstraints = false
        let name = NSTextField(labelWithString: url.deletingPathExtension().lastPathComponent)
        name.font = HWTheme.font(13,weight:.semibold)
        name.lineBreakMode = .byTruncatingMiddle
        let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate).map {
            $0.formatted(date: .abbreviated, time: .shortened)
        } ?? ""
        let detail = NSTextField(labelWithString: "\(url.pathExtension.uppercased()) ,  \(url.deletingLastPathComponent().lastPathComponent) ,  \(date)")
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = .secondaryLabelColor
        let text = NSStackView(views: [name, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 1
        removeButton.image = NSImage(systemSymbolName: "xmark", accessibilityDescription: "최근 문서에서 제거")
        removeButton.imagePosition = .imageOnly
        removeButton.isBordered = false
        removeButton.contentTintColor = .secondaryLabelColor
        removeButton.target = self
        removeButton.action = #selector(removeFromHistory(_:))
        removeButton.wantsLayer = true
        removeButton.alphaValue = 0
        removeButton.toolTip = "최근 문서에서 제거"
        removeButton.setAccessibilityLabel("최근 문서에서 \(url.lastPathComponent) 제거")
        removeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(removeButton)
        detail.lineBreakMode = .byTruncatingMiddle
        text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let row = NSStackView(views: [icon, text])
        row.spacing = 10
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)
        translatesAutoresizingMaskIntoConstraints = false
        setAccessibilityLabel(url.lastPathComponent)
        toolTip = url.path
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: 636), heightAnchor.constraint(equalToConstant: 42),
            icon.widthAnchor.constraint(equalToConstant: 28), icon.heightAnchor.constraint(equalToConstant: 28),
            row.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8), row.centerYAnchor.constraint(equalTo: centerYAnchor),
            row.trailingAnchor.constraint(lessThanOrEqualTo: removeButton.leadingAnchor, constant: -8),
            name.widthAnchor.constraint(lessThanOrEqualToConstant: 500),
            detail.widthAnchor.constraint(lessThanOrEqualToConstant: 500),
            removeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            removeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            removeButton.widthAnchor.constraint(equalToConstant: 26),
            removeButton.heightAnchor.constraint(equalToConstant: 26),
        ])
    }

    required init?(coder: NSCoder) { fatalError() }

    @objc private func removeFromHistory(_ sender: Any?) { removeAction?(url) }

    override func hoverChanged() {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.16
            removeButton.animator().alphaValue = hovering ? 1 : 0
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        guard hovering else { return }
        NSColor.labelColor.withAlphaComponent(0.06).setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()
    }
}
