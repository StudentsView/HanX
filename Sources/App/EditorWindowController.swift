import AppKit
import UniformTypeIdentifiers

final class EditorWindowController: NSWindowController, NSTextViewDelegate, NSToolbarDelegate, NSWindowDelegate {
    private(set) var pages: PageLayoutView!
    private var scrollView: NSScrollView!
    private var ribbon: OfficeRibbon!
    private weak var lastTextView: NSTextView?
    private let status = NSTextField(labelWithString: "")
    // Held directly: NSWindowController.document is only set after init.
    private unowned let hwDocument: HWDocument

    init(document: HWDocument) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 860),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
        window.minSize = NSSize(width: 520, height: 400)
        window.tabbingMode = .preferred
        HWTheme.style(window)
        hwDocument = document
        super.init(window: window)
        window.delegate = self
        buildContent(document)
        shouldCascadeWindows = true
        window.center()
    }

    required init?(coder: NSCoder) { fatalError() }

    override func showWindow(_ sender: Any?) {
        super.showWindow(sender)
        if let window { hwDocument.presentImportWarnings(in: window) }
    }

    private func buildContent(_ doc: HWDocument) {
        guard let window, let content = window.contentView else { return }
        let statusHeight: CGFloat = 24
        scrollView = NSScrollView(frame: NSRect(x: 0, y: statusHeight, width: content.bounds.width, height: content.bounds.height - statusHeight - OfficeRibbon.height))
        scrollView.autoresizingMask = [.width, .height]
        scrollView.contentView = CenteringClipView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.backgroundColor = HWTheme.canvas
        scrollView.allowsMagnification = true
        scrollView.minMagnification = 0.25
        scrollView.maxMagnification = 4
        scrollView.hasHorizontalRuler = true
        scrollView.rulersVisible = false
        content.addSubview(scrollView)

        status.frame = NSRect(x: 12, y: 4, width: content.bounds.width - 24, height: 16)
        status.autoresizingMask = [.width]
        status.font = .systemFont(ofSize: 11)
        status.textColor = HWTheme.secondary
        content.addSubview(status)

        pages = PageLayoutView(storage: doc.textStorage, page: doc.page)
        pages.decorations = doc.decorations()
        pages.textDelegate = self
        pages.textViews.forEach { $0.delegate = self }
        pages.onPagesChanged = { [weak self] in self?.updateStatus() }
        scrollView.documentView = pages
        if doc.textStorage.length == 0 { pages.firstTextView.typingAttributes = doc.defaultTypingAttributes() }

        let toolbar = NSToolbar(identifier: "HanXToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconOnly
        window.toolbar = toolbar
        window.toolbarStyle = .unifiedCompact

        window.makeFirstResponder(pages.firstTextView)
        pages.firstTextView.setSelectedRange(NSRange(location: 0, length: 0))
        buildRibbon(in:content)
        updateStatus()
    }

    override func windowTitle(forDocumentDisplayName displayName: String) -> String {
        let badge: String
        switch hwDocument.sourceFormat {
        case .hwp: badge = "HWP"
        case .hwpx: badge = "HWPX"
        case .docx: badge = "DOCX"
        case .unknown: badge = ""
        }
        return badge.isEmpty ? displayName : "\(displayName)  \(badge)"
    }

    // MARK: Status

    private var activeTextView: NSTextView {
        (window?.firstResponder as? NSTextView).flatMap { tv in pages.textViews.first { $0 === tv } } ?? lastTextView ?? pages.firstTextView
    }

    func updateStatus() {
        guard let pages else { return }
        let sel = activeTextView.selectedRange()
        let current = pages.pageIndex(forCharacter: sel.location) + 1
        let text = hwDocument.textStorage.string
        let chars = text.unicodeScalars.filter { !CharacterSet.whitespacesAndNewlines.contains($0) && $0 != "\u{FFFC}" }.count
        let fmt: String
        switch hwDocument.sourceFormat {
        case .hwp: fmt = "한글 문서 (HWP 5.0)"
        case .hwpx: fmt = "한글 표준 문서 (HWPX)"
        case .docx: fmt = "Word 문서 (DOCX)"
        case .unknown: fmt = "새 문서"
        }
        let p = hwDocument.page
        let paper = String(format: "%.0f×%.0fmm", p.width / 72 * 25.4, p.height / 72 * 25.4)
        status.stringValue = "\(current)/\(pages.pageCount)쪽  ,   \(chars.formatted())자  ,   \(fmt)  ,   \(paper)  ,   \(Int((scrollView.magnification * 100).rounded()))%"
    }

    func textViewDidChangeSelection(_ notification: Notification) {
        if let tv=notification.object as? NSTextView, pages.textViews.contains(where:{$0 === tv}) { lastTextView=tv }
        updateStatus(); reflectRibbon()
    }
    func textDidChange(_ notification: Notification) { updateStatus() }

    // MARK: Toolbar

    private enum Item: String, CaseIterable {
        case style, table, image, pageBreak, headerFooter, zoomOut, zoomIn, zoomFit, ruler
        var id: NSToolbarItem.Identifier { .init(rawValue) }
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [Item.style.id, .space, Item.table.id, Item.image.id, Item.pageBreak.id, Item.headerFooter.id, .flexibleSpace, Item.ruler.id, Item.zoomOut.id, Item.zoomFit.id, Item.zoomIn.id]
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        Item.allCases.map(\.id) + [.flexibleSpace, .space]
    }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier, willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let kind = Item(rawValue: id.rawValue) else { return nil }
        if kind == .style {
            let item = NSMenuToolbarItem(itemIdentifier: id)
            item.label = "스타일"
            item.image = NSImage(systemSymbolName: "textformat", accessibilityDescription: "스타일")
            let menu = NSMenu()
            for (i, st) in EditorWindowController.styles.enumerated() {
                let mi = NSMenuItem(title: st.name, action: #selector(applyParagraphStyle(_:)), keyEquivalent: i < 7 ? "\(i + 1)" : "")
                mi.keyEquivalentModifierMask = [.command, .option]
                mi.tag = i
                mi.target = self
                var c = HWDocument.defaultCharProps(for: hwDocument.sourceFormat)
                c.size = min(18, st.size ?? 12); c.bold = st.bold ?? false; c.italic = st.italic ?? false; c.color = st.color ?? .black
                mi.attributedTitle = NSAttributedString(string: st.name, attributes: AttributedBridge.charAttributes(c, eastAsian: true))
                menu.addItem(mi)
            }
            item.menu = menu
            item.showsIndicator = true
            return item
        }
        let item = NSToolbarItem(itemIdentifier: id)
        let spec: (String, String, Selector) = {
            switch kind {
            case .table: return ("표", "tablecells", #selector(insertTable(_:)))
            case .image: return ("그림", "photo", #selector(insertImage(_:)))
            case .pageBreak: return ("쪽 나누기", "doc.badge.plus", #selector(insertPageBreak(_:)))
            case .headerFooter: return ("머리말/꼬리말", "rectangle.topthird.inset.filled", #selector(editHeaderFooter(_:)))
            case .zoomOut: return ("축소", "minus.magnifyingglass", #selector(zoomOut(_:)))
            case .zoomIn: return ("확대", "plus.magnifyingglass", #selector(zoomIn(_:)))
            case .zoomFit: return ("쪽 맞춤", "arrow.up.left.and.down.right.magnifyingglass", #selector(zoomToFit(_:)))
            case .ruler: return ("눈금자", "ruler", #selector(toggleRulerVisibility(_:)))
            case .style: return ("스타일", "textformat", #selector(applyParagraphStyle(_:)))
            }
        }()
        item.label = spec.0
        item.toolTip = spec.0
        item.image = NSImage(systemSymbolName: spec.1, accessibilityDescription: spec.0)
        item.target = self
        item.action = spec.2
        return item
    }

    // MARK: Commands

    private func replace(_ range: NSRange, with s: NSAttributedString, in tv: NSTextView) {
        guard tv.shouldChangeText(in: range, replacementString: s.string) else { return }
        tv.textStorage?.replaceCharacters(in: range, with: s)
        tv.didChangeText()
    }

    /// Selection snapped to a paragraph boundary, inserting a break if needed.
    private func blockInsertionPoint(_ tv: NSTextView) -> (location: Int, prefix: Bool) {
        let storage = hwDocument.textStorage
        let sel = tv.selectedRange()
        let ns = storage.string as NSString
        let para = ns.paragraphRange(for: NSRange(location: sel.location, length: 0))
        return sel.location == para.location ? (sel.location, false) : (sel.location, true)
    }

    @objc func insertTable(_ sender: Any?) {
        let alert = NSAlert()
        alert.messageText = "표 만들기"
        alert.informativeText = "줄 수와 칸 수를 입력하세요."
        let rows = NSTextField(string: "3"), cols = NSTextField(string: "4")
        let grid = NSGridView(views: [[NSTextField(labelWithString: "줄 수"), rows], [NSTextField(labelWithString: "칸 수"), cols]])
        grid.frame = NSRect(x: 0, y: 0, width: 180, height: 54)
        alert.accessoryView = grid
        alert.addButton(withTitle: "만들기")
        alert.addButton(withTitle: "취소")
        alert.window.initialFirstResponder = rows
        guard let window else { return }
        alert.beginSheetModal(for: window) { [weak self] resp in
            guard resp == .alertFirstButtonReturn, let self else { return }
            let r = max(1, min(200, rows.integerValue)), c = max(1, min(40, cols.integerValue))
            let tv = self.activeTextView
            let (loc, prefix) = self.blockInsertionPoint(tv)
            let s = NSMutableAttributedString()
            let attrs = tv.typingAttributes
            if prefix { s.append(NSAttributedString(string: "\n", attributes: attrs)) }
            s.append(AttributedBridge.emptyTable(rows: r, cols: c, width: self.hwDocument.page.contentWidth, source: self.hwDocument.sourceFormat))
            if loc >= self.hwDocument.textStorage.length {
                var plain = attrs
                if let ps = attrs[.paragraphStyle] as? NSParagraphStyle, let m = ps.mutableCopy() as? NSMutableParagraphStyle {
                    m.textBlocks = []; plain[.paragraphStyle] = m
                }
                s.append(NSAttributedString(string: "\n", attributes: plain))
            }
            self.replace(NSRange(location: loc, length: tv.selectedRange().location == loc ? tv.selectedRange().length : 0), with: s, in: tv)
            tv.setSelectedRange(NSRange(location: loc + (prefix ? 1 : 0), length: 0))
        }
    }

    @objc func insertImage(_ sender: Any?) {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        guard let window else { return }
        panel.beginSheetModal(for: window) { [weak self] resp in
            guard resp == .OK, let url = panel.url, let data = try? Data(contentsOf: url), let self else { return }
            let tv = self.activeTextView
            let id = "insert/" + url.lastPathComponent
            var mark = AttributedBridge.charProps(tv.typingAttributes)
            mark.underline = .none
            var size = ImageProbe.size(data) ?? (width: 0, height: 0)
            if size.width <= 0, let img = NSImage(data: data) { size = (Double(img.size.width), Double(img.size.height)) }
            let s = AttributedBridge.image(id: id, width: size.width, height: size.height, maxWidth: self.hwDocument.page.contentWidth, mark: mark,
                                           ctx: .init(images: [id: ImageData(name: url.lastPathComponent, data: data)], source: self.hwDocument.sourceFormat))
            self.replace(tv.selectedRange(), with: s, in: tv)
        }
    }

    @objc func insertPageBreak(_ sender: Any?) {
        let tv = activeTextView
        replace(tv.selectedRange(), with: NSAttributedString(string: "\u{0C}", attributes: tv.typingAttributes), in: tv)
    }

    // MARK: 문단 스타일

    struct DocStyle {
        let name: String
        var size: Double? = nil, bold: Bool? = nil, italic: Bool? = nil, color: RGB? = nil
        var align: Alignment? = nil, before: Double = 0, after: Double = 0, indent: Double = 0
    }

    static let styles: [DocStyle] = [
        DocStyle(name: "바탕글", size: nil, bold: false, italic: false, color: .black),
        DocStyle(name: "제목", size: 26, bold: true, color: RGB(r: 31, g: 56, b: 100), align: .center, before: 12, after: 12),
        DocStyle(name: "부제목", size: 15, bold: false, color: RGB(r: 89, g: 89, b: 89), align: .center, after: 10),
        DocStyle(name: "제목 1", size: 16, bold: true, color: RGB(r: 31, g: 56, b: 100), align: .left, before: 14, after: 6),
        DocStyle(name: "제목 2", size: 13, bold: true, color: RGB(r: 47, g: 84, b: 150), align: .left, before: 10, after: 4),
        DocStyle(name: "제목 3", size: 11.5, bold: true, color: RGB(r: 64, g: 64, b: 64), align: .left, before: 8, after: 3),
        DocStyle(name: "본문", bold: false, italic: false, color: .black, indent: 15),
        DocStyle(name: "인용", italic: true, color: RGB(r: 89, g: 89, b: 89), before: 6, after: 6, indent: 36),
        DocStyle(name: "강조", bold: true, color: RGB(r: 192, g: 0, b: 0)),
    ]

    @objc func applyParagraphStyle(_ sender: NSMenuItem) {
        let style = EditorWindowController.styles[sender.tag]
        let tv = activeTextView
        guard let storage = tv.textStorage else { return }
        let range = (storage.string as NSString).paragraphRange(for: tv.selectedRange())
        let base = HWDocument.defaultCharProps(for: hwDocument.sourceFormat)
        guard range.length > 0, tv.shouldChangeText(in: range, replacementString: nil) else {
            var c = AttributedBridge.charProps(tv.typingAttributes)
            if let v = style.size { c.size = v } else { c.size = base.size }
            if let v = style.bold { c.bold = v }
            if let v = style.color { c.color = v }
            var a = AttributedBridge.charAttributes(c, eastAsian: true)
            a[.paragraphStyle] = tv.typingAttributes[.paragraphStyle]
            tv.typingAttributes = a
            return
        }
        storage.beginEditing()
        storage.enumerateAttributes(in: range) { attrs, r, _ in
            if attrs[.attachment] != nil || attrs[.hwField] != nil { return }
            var c = AttributedBridge.charProps(attrs)
            c.size = style.size ?? base.size
            if let v = style.bold { c.bold = v }
            if let v = style.italic { c.italic = v }
            if let v = style.color { c.color = v }
            let text = (storage.string as NSString).substring(with: r)
            var new = AttributedBridge.charAttributes(c, eastAsian: text.first?.isEastAsian ?? false)
            if let ps = attrs[.paragraphStyle] as? NSParagraphStyle, let m = ps.mutableCopy() as? NSMutableParagraphStyle {
                if let a = style.align { m.alignment = [.left: .left, .center: .center, .right: .right, .justify: .justified, .distribute: .justified][a]! }
                else if style.name == "바탕글" || style.name == "본문" { m.alignment = hwDocument.sourceFormat == .docx ? .left : .justified }
                m.paragraphSpacingBefore = CGFloat(style.before)
                m.paragraphSpacing = CGFloat(style.after)
                m.headIndent = CGFloat(style.indent)
                m.firstLineHeadIndent = CGFloat(style.indent)
                new[.paragraphStyle] = m
            }
            if let rule = attrs[.hwLineRule] { new[.hwLineRule] = rule }
            new[.hwStyle] = style.name
            storage.setAttributes(new, range: r)
        }
        storage.endEditing()
        tv.didChangeText()
        hwDocument.undoManager?.setActionName("스타일: \(style.name)")
    }

    // MARK: 머리말 / 꼬리말

    private var headerSheet: NSWindow?
    private var headerView: NSTextView?, footerView: NSTextView?
    private weak var lastHFView: NSTextView?

    func applyHeaderFooter(header: [Block]?, footer: [Block]?, name: String) {
        let old = (hwDocument.header, hwDocument.footer)
        hwDocument.header = header
        hwDocument.footer = footer
        pages.decorations = hwDocument.decorations()
        hwDocument.undoManager?.registerUndo(withTarget: self) { wc in wc.applyHeaderFooter(header: old.0, footer: old.1, name: name) }
        hwDocument.undoManager?.setActionName(name)
    }

    private func hfTextView(_ blocks: [Block]?) -> (NSScrollView, NSTextView) {
        let scroll = NSTextView.scrollableTextView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.borderType = .bezelBorder
        scroll.heightAnchor.constraint(equalToConstant: 96).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 560).isActive = true
        let tv = scroll.documentView as! NSTextView
        tv.isRichText = true
        tv.allowsUndo = true
        tv.usesFontPanel = true
        tv.delegate = self
        var c = HWDocument.defaultCharProps(for: hwDocument.sourceFormat)
        c.size = 9
        var defaults = AttributedBridge.charAttributes(c, eastAsian: true)
        let ps = NSMutableParagraphStyle(); ps.alignment = .center
        defaults[.paragraphStyle] = ps
        tv.typingAttributes = defaults
        if let blocks, !blocks.isEmpty {
            let ctx = AttributedBridge.Context(images: [:], source: hwDocument.sourceFormat)
            tv.textStorage?.setAttributedString(AttributedBridge.build(blocks, outer: [], width: hwDocument.page.contentWidth, ctx: ctx))
        }
        return (scroll, tv)
    }

    @objc func editHeaderFooter(_ sender: Any?) {
        guard let window else { return }
        let sheet = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 420), styleMask: [.titled], backing: .buffered, defer: false)
        let (hs, h) = hfTextView(hwDocument.header)
        let (fs, f) = hfTextView(hwDocument.footer)
        headerView = h; footerView = f; lastHFView = f
        func label(_ t: String) -> NSTextField { let l = NSTextField(labelWithString: t); l.font = .systemFont(ofSize: 13, weight: .semibold); return l }
        let page = NSButton(title: "쪽 번호 넣기", target: self, action: #selector(insertPageField(_:)))
        let count = NSButton(title: "전체 쪽수 넣기", target: self, action: #selector(insertPageCountField(_:)))
        count.tag = 1
        let note = NSTextField(labelWithString: "쪽 번호는 각 쪽에서 실제 번호로 바뀝니다. 비워 두면 머리말/꼬리말이 없어집니다.")
        note.font = .systemFont(ofSize: 11); note.textColor = .secondaryLabelColor
        let cancel = NSButton(title: "취소", target: self, action: #selector(closeHeaderSheet(_:)))
        cancel.keyEquivalent = "\u{1b}"
        let ok = NSButton(title: "확인", target: self, action: #selector(closeHeaderSheet(_:)))
        ok.keyEquivalent = "\r"; ok.tag = 1
        let buttons = NSStackView(views: [page, count, NSView(), cancel, ok])
        buttons.widthAnchor.constraint(equalToConstant: 560).isActive = true
        let stack = NSStackView(views: [label("머리말"), hs, label("꼬리말"), fs, note, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
        sheet.contentView = stack
        headerSheet = sheet
        window.beginSheet(sheet)
        sheet.makeFirstResponder(f)
    }

    func textDidBeginEditing(_ notification: Notification) {
        if let tv = notification.object as? NSTextView, tv === headerView || tv === footerView { lastHFView = tv }
    }

    @objc private func insertPageField(_ sender: NSButton) {
        guard let tv = lastHFView else { return }
        let c = AttributedBridge.charProps(tv.typingAttributes)
        let field = AttributedBridge.field(sender.tag == 1 ? .pageCount : .page, c)
        if tv.shouldChangeText(in: tv.selectedRange(), replacementString: field.string) {
            tv.textStorage?.replaceCharacters(in: tv.selectedRange(), with: field)
            tv.didChangeText()
        }
        tv.window?.makeFirstResponder(tv)
    }

    @objc private func insertPageCountField(_ sender: NSButton) { insertPageField(sender) }

    @objc private func closeHeaderSheet(_ sender: NSButton) {
        guard let sheet = headerSheet else { return }
        if sender.tag == 1 {
            func blocks(_ tv: NSTextView?) -> [Block]? {
                guard let s = tv?.textStorage, s.length > 0 else { return nil }
                var hasField = false
                s.enumerateAttribute(.hwField, in: NSRange(location: 0, length: s.length)) { v, _, _ in if v != nil { hasField = true } }
                if s.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasField { return nil }
                return AttributedBridge.document(from: s, base: UDocument(), page: hwDocument.page).sections.first?.blocks
            }
            applyHeaderFooter(header: blocks(headerView), footer: blocks(footerView), name: "머리말/꼬리말")
        }
        window?.endSheet(sheet)
        headerSheet = nil; headerView = nil; footerView = nil
    }

    /// 쪽 번호 매기기: tag 0 none, 1 bottom-centre "- 1 -", 2 bottom-right, 3 top-right "1 / N".
    @objc func setPageNumbering(_ sender: NSMenuItem) {
        func hasField(_ b: Block) -> Bool {
            if case .paragraph(let p) = b { return p.inlines.contains { if case .field = $0 { return true }; return false } }
            return false
        }
        var header = hwDocument.header?.filter { !hasField($0) }
        var footer = hwDocument.footer?.filter { !hasField($0) }
        var c = HWDocument.defaultCharProps(for: hwDocument.sourceFormat)
        c.size = 9
        var p = Paragraph()
        p.markProps = c
        switch sender.tag {
        case 1: p.props.alignment = .center; p.inlines = [.text("- ", c), .field(.page, c), .text(" -", c)]
        case 2: p.props.alignment = .right; p.inlines = [.field(.page, c)]
        case 3: p.props.alignment = .right; p.inlines = [.field(.page, c), .text(" / ", c), .field(.pageCount, c)]
        default: break
        }
        if sender.tag == 3 { header = (header ?? []) + [.paragraph(p)] }
        else if sender.tag > 0 { footer = (footer ?? []) + [.paragraph(p)] }
        applyHeaderFooter(header: header?.isEmpty == true ? nil : header, footer: footer?.isEmpty == true ? nil : footer, name: "쪽 번호")
    }

    @objc func zoomIn(_ sender: Any?) { setZoom(scrollView.magnification * 1.25) }
    @objc func zoomOut(_ sender: Any?) { setZoom(scrollView.magnification / 1.25) }
    @objc func zoomActual(_ sender: Any?) { setZoom(1) }
    @objc func zoomToFit(_ sender: Any?) {
        let w = scrollView.contentSize.width / scrollView.magnification
        setZoom(w / pages.frame.width * scrollView.magnification)
    }

    private func setZoom(_ z: CGFloat) {
        let target = max(scrollView.minMagnification, min(scrollView.maxMagnification, z))
        let center = NSPoint(x: scrollView.documentVisibleRect.midX, y: scrollView.documentVisibleRect.midY)
        scrollView.setMagnification(target, centeredAt: center)
        updateStatus()
    }

    @objc func toggleRulerVisibility(_ sender: Any?) {
        scrollView.rulersVisible.toggle()
    }

    @objc func showPageSetup(_ sender: Any?) {
        var p = hwDocument.page
        let alert = NSAlert()
        alert.messageText = "편집 용지"
        alert.informativeText = "단위: mm"
        func field(_ v: Double) -> NSTextField { NSTextField(string: String(format: "%.1f", v / 72 * 25.4)) }
        let w = field(p.width), h = field(p.height), t = field(p.marginTop), b = field(p.marginBottom), l = field(p.marginLeft), r = field(p.marginRight)
        let grid = NSGridView(views: [
            [NSTextField(labelWithString: "폭"), w, NSTextField(labelWithString: "길이"), h],
            [NSTextField(labelWithString: "위쪽"), t, NSTextField(labelWithString: "아래쪽"), b],
            [NSTextField(labelWithString: "왼쪽"), l, NSTextField(labelWithString: "오른쪽"), r],
        ])
        grid.frame = NSRect(x: 0, y: 0, width: 300, height: 84)
        alert.accessoryView = grid
        alert.addButton(withTitle: "확인")
        alert.addButton(withTitle: "취소")
        guard let window else { return }
        alert.beginSheetModal(for: window) { [weak self] resp in
            guard resp == .alertFirstButtonReturn, let self else { return }
            func pt(_ f: NSTextField) -> Double { f.doubleValue / 25.4 * 72 }
            p.width = max(72, pt(w)); p.height = max(72, pt(h))
            p.marginTop = pt(t); p.marginBottom = pt(b); p.marginLeft = pt(l); p.marginRight = pt(r)
            self.hwDocument.page = p
            self.pages.page = p
            self.hwDocument.updateChangeCount(.changeDone)
            self.updateStatus()
        }
    }
}

extension EditorWindowController {
    private func buildRibbon(in content:NSView) {
        typealias R=OfficeRibbon
        ribbon=R(tabs:[
            .init(title:"홈",groups:[R.clipboard,R.text,.init(title:"문단",items:[.menu("align","정렬",["왼쪽 정렬","가운데 정렬","오른쪽 정렬","양쪽 정렬"]),.menu("spacing","줄 간격",["줄 간격 1.0","줄 간격 1.15","줄 간격 1.5","줄 간격 2.0"]),.button("indent","들여쓰기","increase.indent"),.button("outdent","내어쓰기","decrease.indent")])]),
            .init(title:"글자 모양",groups:[.init(title:"강조",items:[.button("strike","취소선","strikethrough"),.button("super","위 첨자","textformat.superscript"),.button("sub","아래 첨자","textformat.subscript"),.menu("color","글자 색",R.colors),.menu("highlight","형광펜",["형광펜 없음"]+R.colors),.button("clearFormat","글자 모양 초기화","eraser")]),.init(title:"자간 장평",items:[.field("charSpacing","자간 (pt)",["0","-1","0.5","1","2","3"]),.field("widthRatio","장평 (%)",["100","80","90","110","120"])])]),
            .init(title:"삽입",groups:[.init(title:"문서 요소",items:[.button("table","표","tablecells"),.button("image","그림","photo"),.button("pageBreak","쪽 나누기","doc.badge.plus"),.button("headerFooter","머리말 꼬리말","rectangle.topthird.inset.filled"),.menu("pageNumber","쪽 번호",["쪽 번호 없음","아래 가운데","아래 오른쪽","위 오른쪽 / 전체"])])]),
            .init(title:"쪽 문단",groups:[.init(title:"용지",items:[.button("pageSetup","편집 용지 여백","doc"),.menu("orientation","용지 방향",["세로","가로"]),.menu("margins","여백",["여백 선택…","보통 (25.4mm)","좁게 (12.7mm)","넓게 (38.1mm)"])]),.init(title:"문단 간격",items:[.menu("before","문단 앞",["문단 앞 0pt","문단 앞 6pt","문단 앞 12pt","문단 앞 18pt"]),.menu("after","문단 뒤",["문단 뒤 0pt","문단 뒤 6pt","문단 뒤 12pt","문단 뒤 18pt"])])]),
            .init(title:"보기",groups:[.init(title:"확대 축소",items:[.button("zoomOut","축소","minus.magnifyingglass"),.button("fit","쪽 맞춤","arrow.up.left.and.down.right.magnifyingglass"),.button("zoomIn","확대","plus.magnifyingglass"),.button("ruler","눈금자","ruler"),.button("find","찾기 바꾸기","magnifyingglass")])])
        ],width:content.bounds.width)
        ribbon.frame.origin.y=content.bounds.height-R.height; ribbon.onCommand={ [weak self] id,value in self?.ribbonCommand(id,value) }; ribbon.onRefresh={ [weak self] in self?.reflectRibbon() }; content.addSubview(ribbon); reflectRibbon()
    }
    private var ribbonChar: CharProps {
        let tv=activeTextView
        if let st=tv.textStorage,st.length>0 { return AttributedBridge.charProps(st.attributes(at:min(st.length-1,tv.selectedRange().location),effectiveRange:nil)) }
        return AttributedBridge.charProps(tv.typingAttributes)
    }
    var debugRibbon:OfficeRibbon { ribbon }
    private func reflectRibbon() {
        guard ribbon != nil else { return }
        let c=ribbonChar, tv=activeTextView
        ribbon.reflect(font:c.eastAsianFontName ?? c.fontName,size:c.size,bold:c.bold,italic:c.italic,underline:c.underline != .none)
        let attrs: [NSAttributedString.Key:Any]
        if let storage=tv.textStorage,storage.length>0 { attrs=storage.attributes(at:min(storage.length-1,tv.selectedRange().location),effectiveRange:nil) } else { attrs=tv.typingAttributes }
        let ps=attrs[.paragraphStyle] as? NSParagraphStyle
        ribbon.reflectChoice("align",index:[NSTextAlignment.left,.center,.right,.justified].firstIndex(of:ps?.alignment ?? .left) ?? -1)
        let props=AttributedBridge.paraProps(ps,rule:attrs[.hwLineRule] as? String)
        var spacing = -1
        if case .multiple(let n)=props.lineSpacing { spacing=[1.0,1.15,1.5,2].firstIndex(where:{abs($0-n)<0.01}) ?? -1 }
        ribbon.reflectChoice("spacing",index:spacing)
        ribbon.reflectChoice("before",index:[0.0,6,12,18].firstIndex(where:{abs($0-Double(ps?.paragraphSpacingBefore ?? 0))<0.01}) ?? -1)
        ribbon.reflectChoice("after",index:[0.0,6,12,18].firstIndex(where:{abs($0-Double(ps?.paragraphSpacing ?? 0))<0.01}) ?? -1)
        ribbon.reflectChoice("color",index:OfficeRibbon.palette.firstIndex(of:c.color) ?? -1)
        ribbon.reflectChoice("highlight",index:c.highlight.flatMap { OfficeRibbon.palette.firstIndex(of:$0).map { $0+1 } } ?? (c.highlight == nil ? 0 : -1))
        ribbon.reflectText("charSpacing",value:String(format:"%g",c.spacing)); ribbon.reflectText("widthRatio",value:String(format:"%g",c.widthRatio))
        ribbon.reflectChoice("orientation",index:hwDocument.page.width>hwDocument.page.height ? 1 : 0)
    }

    private func changePage(_ page:PageSetup) {
        let old=hwDocument.page
        hwDocument.undoManager?.registerUndo(withTarget:self) { $0.changePage(old) }
        hwDocument.undoManager?.setActionName("편집 용지")
        hwDocument.page=page; pages.page=page; pages.decorations=hwDocument.decorations(); hwDocument.updateChangeCount(.changeDone); updateStatus()
    }
    @objc func toggleBoldface(_ sender:Any?) { ribbonCommand("bold","") }
    @objc func toggleItalics(_ sender:Any?) { ribbonCommand("italic","") }
    func ribbonCommand(_ id:String,_ value:String) {
        let tv=activeTextView, n=Int(value) ?? 0, c=ribbonChar
        if OfficeRibbon.clipboardCommand(id) { return }
        func chars(_ name:String,_ f:(inout CharProps)->Void) { RibbonText.character(tv,name:name,change:f) }
        func para(_ name:String,_ f:(NSMutableParagraphStyle)->Void) { RibbonText.paragraph(tv,name:name,change:f) }
        switch id {
        case "font": chars("글꼴") { $0.fontName=value; $0.eastAsianFontName=value }
        case "size": if let v=Double(value),v.isFinite,v>0 { chars("글자 크기") { $0.size=min(400,v) } }
        case "bold": chars("굵게") { $0.bold = !c.bold }
        case "italic": chars("기울임") { $0.italic = !c.italic }
        case "underline": chars("밑줄") { $0.underline=c.underline == .none ? .single : .none }
        case "strike": chars("취소선") { $0.strike = !c.strike }
        case "super": chars("위 첨자") { $0.verticalAlign=c.verticalAlign == .superscript ? .baseline : .superscript }
        case "sub": chars("아래 첨자") { $0.verticalAlign=c.verticalAlign == .subscript ? .baseline : .subscript }
        case "color": chars("글자 색") { $0.color=OfficeRibbon.palette[n] }
        case "highlight": chars("형광펜") { $0.highlight=n == 0 ? nil : OfficeRibbon.palette[n-1] }
        case "charSpacing": if let v=Double(value),v.isFinite { chars("자간") { $0.spacing=max(-20,min(100,v)) } }
        case "widthRatio": if let v=Double(value),v.isFinite,v>0 { chars("장평") { $0.widthRatio=max(20,min(500,v)) } }
        case "clearFormat": chars("글자 모양 초기화") { $0=HWDocument.defaultCharProps(for:self.hwDocument.sourceFormat) }
        case "align": para("정렬") { $0.alignment=[NSTextAlignment.left,.center,.right,.justified][n] }
        case "spacing": para("줄 간격") { $0.minimumLineHeight=0; $0.maximumLineHeight=0; $0.lineHeightMultiple=[1,1.15,1.5,2][n] }
        case "indent","outdent": para("들여쓰기") { let change:CGFloat=id == "indent" ? 18 : -18; $0.headIndent=max(0,$0.headIndent+change); $0.firstLineHeadIndent=max(0,$0.firstLineHeadIndent+change) }
        case "before": para("문단 앞 간격") { $0.paragraphSpacingBefore=CGFloat(n*6) }
        case "after": para("문단 뒤 간격") { $0.paragraphSpacing=CGFloat(n*6) }
        case "table": insertTable(nil)
        case "image": insertImage(nil)
        case "pageBreak": insertPageBreak(nil)
        case "headerFooter": editHeaderFooter(nil)
        case "pageNumber": let item=NSMenuItem(); item.tag=n; setPageNumbering(item)
        case "pageSetup": showPageSetup(nil)
        case "orientation": var p=hwDocument.page; let short=min(p.width,p.height),long=max(p.width,p.height); p.width=n == 0 ? short : long; p.height=n == 0 ? long : short; changePage(p)
        case "margins": if n>0 { var p=hwDocument.page; let m=[0.0,72,36,108][n]; p.marginLeft=m; p.marginRight=m; p.marginTop=m; p.marginBottom=m; changePage(p) }
        case "zoomOut": zoomOut(nil)
        case "zoomIn": zoomIn(nil)
        case "fit": zoomToFit(nil)
        case "ruler": toggleRulerVisibility(nil)
        case "find": let item=NSMenuItem(); item.tag=NSTextFinder.Action.showFindInterface.rawValue; tv.performFindPanelAction(item)
        default: break
        }
        reflectRibbon()
    }
}
