import AppKit

/// Print-layout view: one NSTextView per page, all sharing one layout
/// manager, so text flows from page to page while editing (Word's "인쇄 모양"
/// / HWP's 쪽 윤곽). Pages are added and removed as layout completes.
final class PageLayoutView: NSView, NSLayoutManagerDelegate {
    let layoutManager = NSLayoutManager()
    private(set) var textViews: [NSTextView] = []
    private var sheets: [PageSheetView] = []
    var page: PageSetup { didSet { relayoutPages() } }
    var decorations = PageDecorations() { didSet { sheets.forEach { $0.decorations = decorations } } }
    weak var textDelegate: NSTextViewDelegate?
    var onPagesChanged: (() -> Void)?

    static let gap: CGFloat = 28

    override var isFlipped: Bool { true }

    init(storage: NSTextStorage, page: PageSetup) {
        self.page = page
        super.init(frame: .zero)
        layoutManager.allowsNonContiguousLayout = false
        layoutManager.usesFontLeading = true
        layoutManager.delegate = self
        storage.addLayoutManager(layoutManager)
        addPage()
    }

    required init?(coder: NSCoder) { fatalError() }

    var pageCount: Int { textViews.count }
    var firstTextView: NSTextView { textViews[0] }

    private func pageRect(_ i: Int) -> NSRect {
        let g = PageLayoutView.gap
        return NSRect(x: g, y: g + CGFloat(i) * (CGFloat(page.height) + g), width: CGFloat(page.width), height: CGFloat(page.height))
    }

    private func contentRect() -> NSRect {
        NSRect(x: CGFloat(page.marginLeft), y: CGFloat(page.marginTop), width: CGFloat(page.contentWidth), height: CGFloat(page.contentHeight))
    }

    func addPage() {
        let index = textViews.count
        let sheet = PageSheetView(frame: pageRect(index))
        sheet.pageNumber = index + 1
        sheet.page = page
        sheet.decorations = decorations
        let rect = contentRect()
        let container = NSTextContainer(size: rect.size)
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        container.lineFragmentPadding = 0
        layoutManager.addTextContainer(container)

        let tv = EditorTextView(frame: rect, textContainer: container)
        tv.isRichText = true
        tv.importsGraphics = true
        tv.allowsUndo = true
        tv.usesFontPanel = true
        tv.usesRuler = true
        // OfficeRibbon owns formatting controls for every page.
        tv.usesInspectorBar = false
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.allowsImageEditing = true
        tv.isVerticallyResizable = false
        tv.isHorizontallyResizable = false
        tv.drawsBackground = false
        tv.textContainerInset = .zero
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        tv.isContinuousSpellCheckingEnabled = false
        tv.smartInsertDeleteEnabled = false
        tv.insertionPointColor = .black
        tv.selectedTextAttributes = [.backgroundColor: NSColor.selectedTextBackgroundColor]
        tv.delegate = textDelegate
        if let first = textViews.first { tv.typingAttributes = first.typingAttributes }
        sheet.addSubview(tv)
        addSubview(sheet)
        sheets.append(sheet)
        textViews.append(tv)
        updateFrame()
    }

    private func removePages(after index: Int) {
        guard index + 1 < textViews.count else { return }
        for i in stride(from: textViews.count - 1, to: index, by: -1) {
            let tv = textViews.remove(at: i)
            if tv.window?.firstResponder === tv { tv.window?.makeFirstResponder(textViews[index]) }
            layoutManager.removeTextContainer(at: i)
            sheets.remove(at: i).removeFromSuperview()
        }
        updateFrame()
    }

    private func relayoutPages() {
        let rect = contentRect()
        for (i, sheet) in sheets.enumerated() {
            sheet.frame = pageRect(i)
            textViews[i].frame = rect
            textViews[i].textContainer?.size = rect.size
        }
        updateFrame()
    }

    private func updateFrame() {
        for (i, sh) in sheets.enumerated() {
            sh.pageNumber = i + 1
            if sh.pageCount != sheets.count { sh.pageCount = sheets.count; sh.needsDisplay = true }
            sh.page = page
        }
        let g = PageLayoutView.gap
        let size = NSSize(width: CGFloat(page.width) + 2 * g, height: g + CGFloat(max(1, sheets.count)) * (CGFloat(page.height) + g))
        if frame.size != size { setFrameSize(size) }
        onPagesChanged?()
    }

    func layoutManager(_ lm: NSLayoutManager, didCompleteLayoutFor container: NSTextContainer?, atEnd: Bool) {
        if !atEnd {
            if container == nil || container === lm.textContainers.last {
                // Defer: mutating the container list inside the layout
                // callback re-enters layout. Re-check, since an edit may have
                // shortened the text meanwhile.
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.needsMorePages() else { return }
                    self.addPage()
                }
            }
        } else if let container, let idx = lm.textContainers.firstIndex(where: { $0 === container }), idx < lm.textContainers.count - 1 {
            DispatchQueue.main.async { [weak self] in self?.removePages(after: idx) }
        }
    }

    func layoutManager(_ layoutManager: NSLayoutManager, shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<NSRect>,
                       lineFragmentUsedRect: UnsafeMutablePointer<NSRect>, baselineOffset: UnsafeMutablePointer<CGFloat>,
                       in textContainer: NSTextContainer, forGlyphRange glyphRange: NSRange) -> Bool {
        TableRowSizer.adjust(layoutManager, lineRect: lineFragmentRect, usedRect: lineFragmentUsedRect, baseline: baselineOffset, glyphRange: glyphRange)
        return true
    }

    func needsMorePages() -> Bool {
        let total = layoutManager.numberOfGlyphs
        guard total > 0, let last = layoutManager.textContainers.last else { return false }
        let r = layoutManager.glyphRange(for: last)
        return NSMaxRange(r) < total
    }

    /// Index of the page holding a character position.
    func pageIndex(forCharacter loc: Int) -> Int {
        guard layoutManager.numberOfGlyphs > 0 else { return 0 }
        let g = layoutManager.glyphIndexForCharacter(at: min(loc, max(0, (layoutManager.textStorage?.length ?? 1) - 1)))
        guard let c = layoutManager.textContainer(forGlyphAt: g, effectiveRange: nil) else { return textViews.count - 1 }
        return layoutManager.textContainers.firstIndex(where: { $0 === c }) ?? 0
    }

    // Printing: one printed page per sheet, at the document's paper size.
    override func knowsPageRange(_ range: NSRangePointer) -> Bool {
        range.pointee = NSRange(location: 1, length: sheets.count)
        return true
    }

    override func rectForPage(_ page: Int) -> NSRect { sheets[max(0, min(sheets.count - 1, page - 1))].frame }

    var sheetFrames: [NSRect] { sheets.map(\.frame) }

    func scrollToPage(_ i: Int) {
        guard i < sheets.count else { return }
        scrollToVisible(sheets[i].frame)
    }
}

/// Header/footer content shared by all pages; fields resolve per page.
struct PageDecorations {
    var header: NSAttributedString?
    var footer: NSAttributedString?
    /// HWP measures the header/footer boxes inside the margins; Word
    /// measures distances from the paper edge.
    var hancomGeometry = true

    static func make(header: [Block]?, footer: [Block]?, page: PageSetup, images: [String: ImageData], source: SourceFormat) -> PageDecorations {
        let ctx = AttributedBridge.Context(images: images, source: source)
        func text(_ b: [Block]?) -> NSAttributedString? {
            guard let b, !b.isEmpty else { return nil }
            let s = AttributedBridge.build(b, outer: [], width: page.contentWidth, ctx: ctx)
            var hasField = false
            s.enumerateAttribute(.hwField, in: NSRange(location: 0, length: s.length)) { v, _, _ in if v != nil { hasField = true } }
            return s.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !hasField ? nil : s
        }
        return PageDecorations(header: text(header), footer: text(footer), hancomGeometry: source != .docx)
    }
}

final class PageSheetView: NSView {
    var pageNumber = 1 { didSet { needsDisplay = true } }
    var pageCount = 1
    var page = PageSetup()
    var decorations = PageDecorations() { didSet { needsDisplay = true } }

    override var isFlipped: Bool { true }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.white.cgColor
        layer?.shadowOpacity = 0.35
        layer?.shadowRadius = 4
        layer?.shadowOffset = CGSize(width: 0, height: -2)
        layer?.masksToBounds = false
    }

    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.white.setFill()
        bounds.fill()
        let x = CGFloat(page.marginLeft), w = CGFloat(page.contentWidth)
        let opts: NSString.DrawingOptions = [.usesLineFragmentOrigin, .usesFontLeading]
        if let h = decorations.header {
            let text = AttributedBridge.resolveFields(h, page: pageNumber, pages: pageCount)
            let top = decorations.hancomGeometry ? CGFloat(page.marginTop - page.header) : CGFloat(page.header)
            text.draw(with: NSRect(x: x, y: max(4, top), width: w, height: CGFloat(page.marginTop) - max(4, top)), options: opts)
        }
        if let f = decorations.footer {
            let text = AttributedBridge.resolveFields(f, page: pageNumber, pages: pageCount)
            let height = text.boundingRect(with: NSSize(width: w, height: 1000), options: opts).height
            let top = decorations.hancomGeometry ? bounds.height - CGFloat(page.marginBottom) + 2
                                                 : bounds.height - CGFloat(page.footer) - height
            text.draw(with: NSRect(x: x, y: top, width: w, height: height + 2), options: opts)
        }
    }
}

/// Keeps the pages horizontally centred when the window is wider than a page.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var r = super.constrainBoundsRect(proposedBounds)
        if let dv = documentView, r.width > dv.frame.width { r.origin.x = (dv.frame.width - r.width) / 2 }
        return r
    }
}

final class EditorTextView: NSTextView {
    override func insertTab(_ sender: Any?) {
        // Tab inside a table cell moves to the next cell, as in Word and HWP.
        if let block = currentCellBlock(), let next = cellStart(after: block) {
            setSelectedRange(NSRange(location: next, length: 0))
            return
        }
        super.insertTab(sender)
    }

    private func currentCellBlock() -> NSTextTableBlock? {
        guard let storage = textStorage, storage.length > 0 else { return nil }
        let loc = min(selectedRange().location, storage.length - 1)
        let ps = storage.attribute(.paragraphStyle, at: loc, effectiveRange: nil) as? NSParagraphStyle
        return ps?.textBlocks.last as? NSTextTableBlock
    }

    private func cellStart(after block: NSTextTableBlock) -> Int? {
        guard let storage = textStorage else { return nil }
        let blockRange = storage.range(of: block, at: selectedRange().location)
        let next = NSMaxRange(blockRange)
        guard next < storage.length,
              let ps = storage.attribute(.paragraphStyle, at: next, effectiveRange: nil) as? NSParagraphStyle,
              let nb = ps.textBlocks.last as? NSTextTableBlock, nb.table === block.table else { return nil }
        return next
    }
}
