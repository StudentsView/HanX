import AppKit
import UniformTypeIdentifiers

protocol SlideInspectorHost: AnyObject {
    var inspectedSlide: Slide { get }
    var inspectedShape: SlideShape? { get }
    var activeTextView: NSTextView? { get }
    var presentation: Presentation { get }
    func modifyShape(_ name: String, _ change: (inout SlideShape) -> Void)
    func modifySlide(_ name: String, _ change: (inout Slide) -> Void)
    func resizePresentation(width: Double, height: Double)
    func modifyAllSlides(_ name: String, _ change: (inout Slide) -> Void)
    func selectShape(_ id: Int)
    func previewFromCurrent()
    func addImageBackground()
    func commitTextEditing()
    func previewTransition()
}

/// Right-hand inspector: 서식 (text/shape/arrange/slide), 애니메이션, 전환.
final class SlideInspector: NSView, NSTableViewDataSource, NSTableViewDelegate, NSComboBoxDelegate, NSTextFieldDelegate {
    weak var host: SlideInspectorHost?
    private let tabs = HWTabControl(labels: ["서식", "애니메이션", "전환"], trackingMode: .selectOne, target: nil, action: nil)
    private let formatPane = NSStackView(), animPane = NSStackView(), transPane = NSStackView()
    private var updating = false

    // 서식
    private let fontPopup = HWPopupButton()
    private let sizeBox = HWComboBox()
    private let styleSeg = HWTabControl()
    private let textColor = NSColorWell(style: .minimal)
    private let highlight = NSColorWell(style: .minimal)
    private let alignSeg = HWTabControl()
    private let anchorSeg = HWTabControl()
    private let spacingPopup = HWPopupButton()
    private let bulletSeg = HWTabControl(labels: ["없음", "•", "1."], trackingMode: .selectOne, target: nil, action: nil)
    private let fillWell = NSColorWell(style: .minimal)
    private let noFill = NSButton(checkboxWithTitle: "채우기 없음", target: nil, action: nil)
    private let lineWell = NSColorWell(style: .minimal)
    private let noLine = NSButton(checkboxWithTitle: "선 없음", target: nil, action: nil)
    private let lineWidth = HWPopupButton()
    private let kindPopup = HWPopupButton()
    private let xField = HWTextField(), yField = HWTextField(), wField = HWTextField(), hField = HWTextField(), rotField = HWTextField()
    private let aspectLock = NSButton(checkboxWithTitle:"가로 세로 비율 고정",target:nil,action:nil)
    private let bgWell = NSColorWell(style: .minimal)
    private let sizePopup = HWPopupButton()
    private var shapeSections: [NSView] = []

    // 애니메이션
    private let addEffect = HWPopupButton(frame: .zero, pullsDown: true)
    private let animTable = NSTableView()
    private let effectPopup = HWPopupButton()
    private let triggerPopup = HWPopupButton()
    private let directionPopup = HWPopupButton()
    private let durationField = HWTextField()
    private let delayField = HWTextField()
    private var animDetail: NSView!

    // 전환
    private let transPopup = HWPopupButton()
    private let transDir = HWPopupButton()
    private let transDuration = HWTextField()
    private let clickAdvance = NSButton(checkboxWithTitle:"마우스를 클릭할 때",target:nil,action:nil)
    private let verticalTransition = NSButton(checkboxWithTitle:"세로 방향",target:nil,action:nil)
    private let inwardTransition = NSButton(checkboxWithTitle:"안쪽으로",target:nil,action:nil)
    private let autoAdvance = NSButton(checkboxWithTitle: "자동으로 넘기기", target: nil, action: nil)
    private let autoSeconds = HWTextField()

    static let kinds: [(ShapeKind,String)] = ShapeKind.allCases.filter { ![.image,.table,.line].contains($0) }.map { ($0,$0.title) }
    static let spacings: [Double] = [0.8, 0.9, 1.0, 1.15, 1.5, 2.0, 2.5, 3.0]
    static let widths: [Double] = [0.25, 0.5, 0.75, 1, 1.5, 2.25, 3, 4.5, 6]

    override init(frame: NSRect) {
        super.init(frame: frame)
        build()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: Layout helpers

    private func header(_ t: String) -> NSTextField {
        let l = NSTextField(labelWithString: t)
        l.font = HWTheme.font(11,weight:.semibold)
        l.textColor = HWTheme.secondary
        return l
    }

    private func row(_ label: String, _ views: NSView...) -> NSView {
        let l = NSTextField(labelWithString: label)
        l.font = .systemFont(ofSize: 12)
        l.setContentHuggingPriority(.required, for: .horizontal)
        l.widthAnchor.constraint(equalToConstant: 58).isActive = true
        let s = NSStackView(views: [l] + views)
        s.spacing = 6
        return s
    }

    private func section(_ title: String, _ rows: [NSView]) -> NSView {
        let s = NSStackView(views: [header(title)] + rows)
        s.orientation = .vertical
        s.alignment = .leading
        s.spacing = 9
        return s
    }

    private func numberField(_ f: NSTextField, width: CGFloat = 56) -> NSTextField {
        f.alignment = .right
        f.font = HWTheme.font(12)
        f.widthAnchor.constraint(equalToConstant: width).isActive = true
        f.delegate = self
        f.target = self
        f.action = #selector(fieldCommitted(_:))
        return f
    }

    private func pane(_ p: NSStackView, _ views: [NSView]) {
        p.orientation = .vertical
        p.alignment = .leading
        p.spacing = 22
        p.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        views.forEach(p.addArrangedSubview)
    }

    private func build() {
        wantsLayer = true
        tabs.selectedSegment = 0
        tabs.target = self
        tabs.action = #selector(tabChanged(_:))
        tabs.translatesAutoresizingMaskIntoConstraints = false
        addSubview(tabs)

        // Text
        let families = NSFontManager.shared.availableFontFamilies
        let preferred = ["맑은 고딕", "Malgun Gothic", "함초롬바탕", "함초롬돋움", "HCR Batang", "HCR Dotum", "나눔고딕", "NanumGothic",
                         "Apple SD Gothic Neo", "AppleMyungjo", "HYHeadLine M", "Calibri", "Arial", "Helvetica Neue", "Times New Roman"]
        let top = preferred.filter { families.contains($0) }
        fontPopup.addItems(withTitles: top)
        fontPopup.menu?.addItem(.separator())
        fontPopup.addItems(withTitles: families.filter { !top.contains($0) })
        fontPopup.target = self; fontPopup.action = #selector(fontChanged(_:))
        fontPopup.widthAnchor.constraint(equalToConstant: 178).isActive = true

        sizeBox.addItems(withObjectValues: [8, 9, 10, 10.5, 11, 12, 14, 16, 18, 20, 24, 28, 32, 36, 40, 44, 48, 54, 60, 66, 72, 80, 88, 96].map { "\($0)".replacingOccurrences(of: ".0", with: "") })
        sizeBox.numberOfVisibleItems = 14
        sizeBox.delegate = self
        sizeBox.target = self; sizeBox.action = #selector(sizeChanged(_:))
        sizeBox.widthAnchor.constraint(equalToConstant: 64).isActive = true
        let grow = HWActionButton(image: NSImage(systemSymbolName: "textformat.size.larger", accessibilityDescription: "크게")!, target: self, action: #selector(growText(_:)))
        let shrink = HWActionButton(image: NSImage(systemSymbolName: "textformat.size.smaller", accessibilityDescription: "작게")!, target: self, action: #selector(shrinkText(_:)))
        [grow, shrink].forEach { $0.bezelStyle = .texturedRounded }

        styleSeg.segmentCount = 4
        for (i, sym) in ["bold", "italic", "underline", "strikethrough"].enumerated() {
            styleSeg.setImage(NSImage(systemSymbolName: sym, accessibilityDescription: sym), forSegment: i)
            styleSeg.setWidth(32, forSegment: i)
        }
        styleSeg.trackingMode = .selectAny
        styleSeg.target = self; styleSeg.action = #selector(styleChanged(_:))

        textColor.color = .black
        textColor.target = self; textColor.action = #selector(textColorChanged(_:))
        highlight.color = .clear
        highlight.target = self; highlight.action = #selector(highlightChanged(_:))
        let clearHighlight = HWActionButton(title: "없음", target: self, action: #selector(clearHighlight(_:)))
        clearHighlight.bezelStyle = .texturedRounded

        alignSeg.segmentCount = 4
        for (i, sym) in ["text.alignleft", "text.aligncenter", "text.alignright", "text.justify"].enumerated() {
            alignSeg.setImage(NSImage(systemSymbolName: sym, accessibilityDescription: sym), forSegment: i)
            alignSeg.setWidth(32, forSegment: i)
        }
        alignSeg.target = self; alignSeg.action = #selector(alignChanged(_:))
        anchorSeg.segmentCount = 3
        for (i, sym) in ["arrow.up.to.line", "arrow.up.and.down", "arrow.down.to.line"].enumerated() {
            anchorSeg.setImage(NSImage(systemSymbolName: sym, accessibilityDescription: sym), forSegment: i)
            anchorSeg.setWidth(32, forSegment: i)
        }
        anchorSeg.target = self; anchorSeg.action = #selector(anchorChanged(_:))
        spacingPopup.addItems(withTitles: SlideInspector.spacings.map { String(format: "%.2g", $0) })
        spacingPopup.target = self; spacingPopup.action = #selector(spacingChanged(_:))
        bulletSeg.target = self; bulletSeg.action = #selector(bulletChanged(_:))

        let textSection = section("텍스트", [
            row("글꼴", fontPopup),
            row("크기", sizeBox, grow, shrink),
            row("스타일", styleSeg),
            row("글자 색", textColor, NSTextField(labelWithString: "형광펜"), highlight, clearHighlight),
            row("정렬", alignSeg),
            row("세로", anchorSeg),
            row("줄 간격", spacingPopup),
            row("글머리", bulletSeg),
        ])

        // Shape
        fillWell.target = self; fillWell.action = #selector(fillChanged(_:))
        noFill.target = self; noFill.action = #selector(noFillChanged(_:))
        lineWell.target = self; lineWell.action = #selector(lineChanged(_:))
        noLine.target = self; noLine.action = #selector(noLineChanged(_:))
        lineWidth.addItems(withTitles: SlideInspector.widths.map { "\($0.formatted())pt" })
        lineWidth.target = self; lineWidth.action = #selector(lineWidthChanged(_:))
        kindPopup.addItems(withTitles: SlideInspector.kinds.map(\.1))
        kindPopup.target = self; kindPopup.action = #selector(kindChanged(_:))
        let shapeSection = section("도형", [row("모양", kindPopup), row("채우기", fillWell, noFill), row("선", lineWell, noLine), row("선 굵기", lineWidth)])

        let posGrid = NSGridView(views: [
            [NSTextField(labelWithString: "X"), numberField(xField), NSTextField(labelWithString: "Y"), numberField(yField)],
            [NSTextField(labelWithString: "너비"), numberField(wField), NSTextField(labelWithString: "높이"), numberField(hField)],
            [NSTextField(labelWithString: "회전"), numberField(rotField), NSTextField(labelWithString: "°"), NSView()],
        ])
        posGrid.columnSpacing = 6; posGrid.rowSpacing = 6
        aspectLock.target=self; aspectLock.action=#selector(aspectChanged(_:))
        let arrange = section("배치 (cm)", [posGrid,aspectLock])

        bgWell.target = self; bgWell.action = #selector(backgroundChanged(_:))
        let bgImage = HWActionButton(title: "그림…", target: self, action: #selector(backgroundImage(_:)))
        bgImage.bezelStyle = .texturedRounded
        sizePopup.addItems(withTitles: ["와이드스크린 (16:9)", "표준 (4:3)", "A4 가로"])
        sizePopup.target = self; sizePopup.action = #selector(slideSizeChanged(_:))
        let slideSection = section("슬라이드", [row("배경", bgWell, bgImage), row("크기", sizePopup)])

        shapeSections = [textSection, shapeSection, arrange]
        pane(formatPane, [textSection, shapeSection, arrange, slideSection])

        // Animation
        addEffect.addItem(withTitle: "+ 효과 추가")
        for cls in AnimClass.allCases {
            let h = NSMenuItem(title: ["entr": "나타내기", "emph": "강조", "exit": "끝내기"][cls.rawValue]!, action: nil, keyEquivalent: "")
            h.isEnabled = false
            addEffect.menu?.addItem(h)
            for e in AnimEffect.allCases where e.animClass == cls {
                let mi = NSMenuItem(title: "    " + e.title, action: #selector(addAnimation(_:)), keyEquivalent: "")
                mi.target = self
                mi.representedObject = e.rawValue
                addEffect.menu?.addItem(mi)
            }
        }
        let col = NSTableColumn(identifier: .init("a")); col.width = 230
        animTable.addTableColumn(col)
        animTable.headerView = nil
        animTable.rowHeight = 26
        animTable.dataSource = self; animTable.delegate = self
        animTable.style = .inset
        let scroll = NSScrollView()
        scroll.documentView = animTable
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.heightAnchor.constraint(equalToConstant: 220).isActive = true
        scroll.widthAnchor.constraint(equalToConstant: 244).isActive = true
        let up = HWActionButton(image: NSImage(systemSymbolName: "chevron.up", accessibilityDescription: "위로")!, target: self, action: #selector(moveAnimUp(_:)))
        let down = HWActionButton(image: NSImage(systemSymbolName: "chevron.down", accessibilityDescription: "아래로")!, target: self, action: #selector(moveAnimDown(_:)))
        let del = HWActionButton(image: NSImage(systemSymbolName: "trash", accessibilityDescription: "삭제")!, target: self, action: #selector(removeAnimation(_:)))
        let play = HWActionButton(title: "미리 보기", target: self, action: #selector(preview(_:)))
        play.image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)
        play.imagePosition = .imageLeading
        [up, down, del, play].forEach { $0.bezelStyle = .texturedRounded }
        let controls = NSStackView(views: [up, down, del, NSView(), play])

        effectPopup.target = self; effectPopup.action = #selector(animEdited(_:))
        triggerPopup.addItems(withTitles: AnimTrigger.allCases.map(\.title))
        triggerPopup.target = self; triggerPopup.action = #selector(animEdited(_:))
        directionPopup.addItems(withTitles: AnimDirection.allCases.map(\.title))
        directionPopup.target = self; directionPopup.action = #selector(animEdited(_:))
        animDetail = section("선택한 효과", [
            row("효과", effectPopup), row("시작", triggerPopup), row("방향", directionPopup),
            row("재생 시간", numberField(durationField), NSTextField(labelWithString: "초")),
            row("지연", numberField(delayField), NSTextField(labelWithString: "초")),
        ])
        let hint = NSTextField(wrappingLabelWithString: "슬라이드에서 개체를 선택한 뒤 효과를 추가하세요. 슬라이드 쇼에서는 클릭할 때마다 다음 효과가 재생됩니다.")
        hint.font = .systemFont(ofSize: 11)
        hint.textColor = .secondaryLabelColor
        hint.widthAnchor.constraint(equalToConstant: 240).isActive = true
        pane(animPane, [addEffect, scroll, controls, animDetail, hint])

        // Transition
        transPopup.addItems(withTitles: TransitionKind.allCases.map(\.title))
        transPopup.target = self; transPopup.action = #selector(transitionEdited(_:))
        transDir.addItems(withTitles: AnimDirection.allCases.map(\.title))
        transDir.target = self; transDir.action = #selector(transitionEdited(_:))
        for button in [clickAdvance,verticalTransition,inwardTransition] { button.target=self; button.action=#selector(transitionEdited(_:)) }
        autoAdvance.target = self; autoAdvance.action = #selector(transitionEdited(_:))
        let applyAll = HWActionButton(title: "모든 슬라이드에 적용", target: self, action: #selector(applyTransitionToAll(_:)))
        applyAll.bezelStyle = .rounded
        let playT = HWActionButton(title: "미리 보기", target: self, action: #selector(previewTransitionOnly(_:)))
        playT.bezelStyle = .rounded
        pane(transPane, [section("이 슬라이드로 전환", [
            row("효과", transPopup), row("방향", transDir),
            row("재생 시간", numberField(transDuration), NSTextField(labelWithString: "초")),
            row("",verticalTransition), row("",inwardTransition), row("",clickAdvance),
            row("", autoAdvance), row("", numberField(autoSeconds), NSTextField(labelWithString: "초 후")),
        ]), applyAll, playT])

        for p in [formatPane, animPane, transPane] {
            let sv = NSScrollView()
            sv.drawsBackground = false
            sv.hasVerticalScroller = true
            sv.documentView = FlippedClip(content: p)
            sv.translatesAutoresizingMaskIntoConstraints = false
            addSubview(sv)
            NSLayoutConstraint.activate([
                sv.topAnchor.constraint(equalTo: tabs.bottomAnchor, constant: 8), sv.bottomAnchor.constraint(equalTo: bottomAnchor),
                sv.leadingAnchor.constraint(equalTo: leadingAnchor), sv.trailingAnchor.constraint(equalTo: trailingAnchor),
            ])
            sv.identifier = NSUserInterfaceItemIdentifier(p === formatPane ? "0" : p === animPane ? "1" : "2")
        }
        NSLayoutConstraint.activate([
            tabs.topAnchor.constraint(equalTo: topAnchor, constant: 12), tabs.heightAnchor.constraint(equalToConstant:32), tabs.centerXAnchor.constraint(equalTo: centerXAnchor),
        ])
        tabChanged(tabs)
    }

    override func draw(_ dirtyRect: NSRect) {
        HWTheme.paper.setFill(); bounds.fill()
        HWTheme.border.setFill(); NSRect(x: 0, y: 0, width: 1, height: bounds.height).fill()
    }

    @objc private func tabChanged(_ s: NSSegmentedControl) {
        for v in subviews where v is NSScrollView { v.isHidden = v.identifier?.rawValue != "\(s.selectedSegment)" }
        refresh()
    }

    func showFormatTab() { tabs.selectedSegment=0; tabChanged(tabs) }
    func showTransitionTab() { tabs.selectedSegment=2; tabChanged(tabs) }
    func showAnimationTab() { tabs.selectedSegment = 1; tabChanged(tabs) }

    // MARK: Reflect state

    var currentChar: CharProps? {
        if let tv = host?.activeTextView, let storage = tv.textStorage {
            let loc = tv.selectedRange().location
            let attrs = storage.length > 0 ? storage.attributes(at: min(loc, storage.length - 1), effectiveRange: nil) : tv.typingAttributes
            return AttributedBridge.charProps(attrs)
        }
        guard let s = host?.inspectedShape else { return nil }
        for p in s.paragraphs { for i in p.inlines { if case .text(_, let c) = i { return c } } }
        return s.paragraphs.first?.markProps
    }

    func refresh() {
        guard let host else { return }
        updating = true
        defer { updating = false }
        let shape = host.inspectedShape
        shapeSections.forEach { $0.isHidden = shape == nil }
        if let c = currentChar {
            let family = FontResolver.shared.font(name: c.eastAsianFontName ?? c.fontName, size: 12, bold: false, italic: false).font.familyName ?? c.fontName
            if fontPopup.itemTitles.contains(c.eastAsianFontName ?? c.fontName) { fontPopup.selectItem(withTitle: c.eastAsianFontName ?? c.fontName) }
            else if fontPopup.itemTitles.contains(family) { fontPopup.selectItem(withTitle: family) }
            sizeBox.stringValue = c.size.formatted(.number.precision(.fractionLength(0...1)))
            styleSeg.setSelected(c.bold, forSegment: 0)
            styleSeg.setSelected(c.italic, forSegment: 1)
            styleSeg.setSelected(c.underline != .none, forSegment: 2)
            styleSeg.setSelected(c.strike, forSegment: 3)
            textColor.color = AttributedBridge.nsColor(c.color)
            highlight.color = c.highlight.map(AttributedBridge.nsColor) ?? .clear
        }
        if let s = shape {
            let p = s.paragraphs.first?.props ?? ParaProps()
            alignSeg.selectedSegment = [.left: 0, .center: 1, .right: 2, .justify: 3, .distribute: 3][p.alignment]!
            anchorSeg.selectedSegment = [.top: 0, .center: 1, .bottom: 2][s.anchor]!
            if case .multiple(let m) = p.lineSpacing, let i = SlideInspector.spacings.firstIndex(where: { abs($0 - m) < 0.01 }) { spacingPopup.selectItem(at: i) }
            bulletSeg.selectedSegment = p.listLabel == nil ? 0 : p.listLabel == "#" ? 2 : 1
            fillWell.color = s.fill.map(AttributedBridge.nsColor) ?? .white
            noFill.state = s.fill == nil ? .on : .off
            lineWell.color = s.line.map(AttributedBridge.nsColor) ?? .black
            noLine.state = s.line == nil ? .on : .off
            if let i = SlideInspector.widths.firstIndex(where: { abs($0 - s.lineWidth) < 0.13 }) { lineWidth.selectItem(at: i) }
            if let i = SlideInspector.kinds.firstIndex(where: { $0.0 == s.kind }) { kindPopup.selectItem(at: i) }
            kindPopup.isEnabled = s.kind != .image && s.kind != .table && s.kind != .line
            func cm(_ v: Double) -> String { String(format: "%.2f", v / 72 * 2.54) }
            xField.stringValue = cm(s.frame.x); yField.stringValue = cm(s.frame.y)
            wField.stringValue = cm(s.frame.w); hField.stringValue = cm(s.frame.h)
            aspectLock.state=s.lockAspect ? .on : .off
            rotField.stringValue = String(format: "%.0f", s.rotation)
        }
        let slide = host.inspectedSlide
        bgWell.color = slide.background.map(AttributedBridge.nsColor) ?? .white
        let ratio = host.presentation.width / host.presentation.height
        sizePopup.selectItem(at: abs(ratio - 16.0 / 9) < 0.02 ? 0 : abs(ratio - 4.0 / 3) < 0.02 ? 1 : 2)

        animTable.reloadData()
        addEffect.isEnabled = shape != nil
        if let id = shape?.id, let i = slide.animations.firstIndex(where: { $0.shapeID == id }), animTable.selectedRow < 0 || slide.animations[safe: animTable.selectedRow]?.shapeID != id {
            animTable.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
        }
        refreshAnimDetail()

        let t = slide.transition
        transPopup.selectItem(at: TransitionKind.allCases.firstIndex(of: t.kind) ?? 0)
        transDir.selectItem(at: AnimDirection.allCases.firstIndex(of: t.direction) ?? 0)
        clickAdvance.state=t.advanceOnClick ? .on : .off
        verticalTransition.state=t.vertical ? .on : .off
        verticalTransition.isEnabled=[.split,.blinds,.checker,.comb,.randomBar].contains(t.kind)
        inwardTransition.state=t.inward ? .on : .off
        inwardTransition.isEnabled=[.split,.zoom].contains(t.kind)
        transDuration.stringValue = String(format: "%.2f", t.duration)
        autoAdvance.state = t.advanceAfter == nil ? .off : .on
        autoSeconds.stringValue = String(format: "%.1f", t.advanceAfter ?? 5)
        autoSeconds.isEnabled = t.advanceAfter != nil
    }

    private var selectedAnim: Int? {
        let r = animTable.selectedRow
        return r >= 0 && r < (host?.inspectedSlide.animations.count ?? 0) ? r : nil
    }

    private func refreshAnimDetail() {
        guard let i = selectedAnim, let a = host?.inspectedSlide.animations[i] else { animDetail.isHidden = true; return }
        animDetail.isHidden = false
        effectPopup.removeAllItems()
        let options = AnimEffect.allCases.filter { $0.animClass == a.effect.animClass }
        effectPopup.addItems(withTitles: options.map(\.title))
        effectPopup.selectItem(at: options.firstIndex(of: a.effect) ?? 0)
        triggerPopup.selectItem(at: AnimTrigger.allCases.firstIndex(of: a.trigger) ?? 0)
        directionPopup.selectItem(at: AnimDirection.allCases.firstIndex(of: a.direction) ?? 0)
        directionPopup.isEnabled = [.flyIn, .flyOut, .wipe, .wipeOut].contains(a.effect)
        durationField.stringValue = String(format: "%.2f", a.duration)
        delayField.stringValue = String(format: "%.2f", a.delay)
    }

    // MARK: Text formatting

    /// Applies a character change to the selection while editing, else to
    /// every run of the selected shape.
    func changeText(_ name: String, _ f: @escaping (inout CharProps) -> Void) {
        guard !updating else { return }
        if let tv=host?.activeTextView { RibbonText.character(tv,name:name,change:f); return }
        host?.modifyShape(name) { s in
            s.paragraphs = s.paragraphs.map { p in
                var p = p
                f(&p.markProps)
                p.inlines = p.inlines.map {
                    switch $0 {
                    case .text(let t, var c): f(&c); return .text(t, c)
                    case .tab(var c): f(&c); return .tab(c)
                    case .lineBreak(var c): f(&c); return .lineBreak(c)
                    default: return $0
                    }
                }
                return p
            }
        }
    }

    func changeParagraphs(_ name: String, _ f: @escaping (inout ParaProps) -> Void) {
        guard !updating else { return }
        // Paragraph changes go through the model so bullets and spacing round-trip.
        host?.commitTextEditing()
        host?.modifyShape(name) { s in
            if s.paragraphs.isEmpty { s.paragraphs = [Paragraph()] }
            s.paragraphs = s.paragraphs.map { var p = $0; f(&p.props); return p }
        }
    }

    @objc private func fontChanged(_ s: NSPopUpButton) {
        guard let family = s.titleOfSelectedItem else { return }
        changeText("글꼴") { $0.fontName = family; $0.eastAsianFontName = family }
    }

    @objc private func sizeChanged(_ s: Any?) {
        guard let v = Double(sizeBox.stringValue.replacingOccurrences(of: "pt", with: "")), v > 0 else { return }
        changeText("글자 크기") { $0.size = min(400, v) }
    }

    func comboBoxSelectionDidChange(_ notification: Notification) {
        DispatchQueue.main.async { self.sizeChanged(nil) }
    }

    @objc private func growText(_ s: Any?) { changeText("크게") { $0.size = ($0.size * 1.15).rounded() } }
    @objc private func shrinkText(_ s: Any?) { changeText("작게") { $0.size = max(4, ($0.size / 1.15).rounded()) } }

    @objc private func styleChanged(_ s: NSSegmentedControl) {
        let b = s.isSelected(forSegment: 0), i = s.isSelected(forSegment: 1), u = s.isSelected(forSegment: 2), st = s.isSelected(forSegment: 3)
        changeText("글자 모양") { $0.bold = b; $0.italic = i; $0.underline = u ? ($0.underline == .none ? .single : $0.underline) : .none; $0.strike = st }
    }

    private func rgb(_ c: NSColor) -> RGB {
        let s = c.usingColorSpace(.sRGB) ?? c
        return RGB(r: UInt8(max(0, min(255, s.redComponent * 255))), g: UInt8(max(0, min(255, s.greenComponent * 255))), b: UInt8(max(0, min(255, s.blueComponent * 255))))
    }

    @objc private func textColorChanged(_ w: NSColorWell) { let c = rgb(w.color); changeText("글자 색") { $0.color = c } }
    @objc private func highlightChanged(_ w: NSColorWell) { let c = rgb(w.color); changeText("형광펜") { $0.highlight = c } }
    @objc private func clearHighlight(_ s: Any?) { changeText("형광펜 없음") { $0.highlight = nil } }

    @objc private func alignChanged(_ s: NSSegmentedControl) {
        let a: Alignment = [.left, .center, .right, .justify][s.selectedSegment]
        if let tv = host?.activeTextView {
            tv.setAlignment([.left, .center, .right, .justified][s.selectedSegment], range: tv.rangeForUserParagraphAttributeChange)
            return
        }
        changeParagraphs("정렬") { $0.alignment = a }
    }

    @objc private func anchorChanged(_ s: NSSegmentedControl) {
        let v: CellVAlign = [.top, .center, .bottom][s.selectedSegment]
        host?.modifyShape("세로 맞춤") { $0.anchor = v }
    }

    @objc private func spacingChanged(_ s: NSPopUpButton) {
        let m = SlideInspector.spacings[s.indexOfSelectedItem]
        changeParagraphs("줄 간격") { $0.lineSpacing = .multiple(m) }
    }

    @objc private func bulletChanged(_ s: NSSegmentedControl) {
        let label: String? = [nil, "•", "#"][s.selectedSegment]
        changeParagraphs("글머리 기호") { p in
            p.listLabel = label
            if label != nil && p.indentLeft < 1 { p.indentLeft = 27; p.firstLine = -27 }
            if label == nil { p.indentLeft = 0; p.firstLine = 0 }
        }
    }

    // MARK: Shape

    @objc private func fillChanged(_ w: NSColorWell) {
        let c = rgb(w.color)
        host?.modifyShape("채우기") { s in s.fill = c; if s.kind == .text { s.kind = .rect } }
    }
    @objc private func noFillChanged(_ b: NSButton) {
        let on = b.state == .on, c = rgb(fillWell.color)
        host?.modifyShape("채우기") { $0.fill = on ? nil : c }
    }
    @objc private func lineChanged(_ w: NSColorWell) {
        let c = rgb(w.color)
        host?.modifyShape("선 색") { s in s.line = c; if s.kind == .text { s.kind = .rect } }
    }
    @objc private func noLineChanged(_ b: NSButton) {
        let on = b.state == .on, c = rgb(lineWell.color)
        host?.modifyShape("선") { $0.line = on ? nil : c }
    }
    @objc private func lineWidthChanged(_ p: NSPopUpButton) {
        let w = SlideInspector.widths[p.indexOfSelectedItem]
        host?.modifyShape("선 굵기") { s in s.lineWidth = w; if s.line == nil { s.line = .black } }
    }
    @objc private func kindChanged(_ p: NSPopUpButton) {
        let k = SlideInspector.kinds[p.indexOfSelectedItem].0
        host?.modifyShape("모양 변경") { $0.kind = k }
    }

    @objc private func aspectChanged(_ b: NSButton) { let on=b.state == .on; host?.modifyShape("비율 고정") { $0.lockAspect=on } }

    @objc private func fieldCommitted(_ f: NSTextField) {
        guard !updating else { return }
        if [durationField, delayField].contains(f) { animEdited(f); return }
        if [transDuration, autoSeconds].contains(f) { transitionEdited(f); return }
        guard let v = Double(f.stringValue), v.isFinite else { return }
        let pt = v / 2.54 * 72
        host?.modifyShape("배치") { s in
            switch f {
            case self.xField: s.frame.x = pt
            case self.yField: s.frame.y = pt
            case self.wField: if s.lockAspect { s.frame.h *= max(1,pt)/max(1,s.frame.w) }; s.frame.w = max(1,pt)
            case self.hField: if s.lockAspect { s.frame.w *= max(1,pt)/max(1,s.frame.h) }; s.frame.h = max(1,pt)
            case self.rotField: s.rotation = v.truncatingRemainder(dividingBy: 360)
            default: break
            }
        }
    }

    func controlTextDidEndEditing(_ obj: Notification) {
        if let f = obj.object as? NSTextField, f !== sizeBox { fieldCommitted(f) }
        if obj.object as? NSComboBox === sizeBox { sizeChanged(nil) }
    }

    // MARK: Slide

    @objc private func backgroundChanged(_ w: NSColorWell) {
        let c = rgb(w.color)
        host?.modifySlide("배경") { $0.background = c; $0.backgroundImage = nil }
    }
    @objc private func backgroundImage(_ s: Any?) { host?.addImageBackground() }

    @objc private func slideSizeChanged(_ p: NSPopUpButton) {
        guard let host else { return }
        let size: (Double,Double)=[(960,540),(720,540),(841.9,595.3)][p.indexOfSelectedItem]
        host.resizePresentation(width:size.0,height:size.1)
    }

    // MARK: Animations

    func numberOfRows(in tableView: NSTableView) -> Int { host?.inspectedSlide.animations.count ?? 0 }

    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard let slide = host?.inspectedSlide, row < slide.animations.count else { return nil }
        let a = slide.animations[row]
        // Click number as PowerPoint shows it; with/after effects show no number.
        let step = slide.animations[...row].filter { $0.trigger == .onClick }.count
        let num = NSTextField(labelWithString: a.trigger == .onClick ? "\(step)" : (a.trigger == .withPrevious ? "∥" : "↳"))
        num.font = .monospacedDigitSystemFont(ofSize: 11, weight: .semibold)
        num.alignment = .center
        num.widthAnchor.constraint(equalToConstant: 18).isActive = true
        let star = NSImageView(image: NSImage(systemSymbolName: "star.fill", accessibilityDescription: nil)!)
        star.contentTintColor = [.entrance: NSColor.systemGreen, .emphasis: .systemYellow, .exit: .systemRed][a.effect.animClass]!
        let name = slide.shapes.first { $0.id == a.shapeID }.map { s -> String in
            let t = s.paragraphs.map(\.plainText).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            return t.isEmpty ? (s.name.isEmpty ? "개체" : s.name) : String(t.prefix(14))
        } ?? "?"
        let label = NSTextField(labelWithString: "\(a.effect.title), \(name)")
        label.lineBreakMode = .byTruncatingTail
        label.font = .systemFont(ofSize: 12)
        let s = NSStackView(views: [num, star, label])
        s.spacing = 5
        return s
    }

    func tableViewSelectionDidChange(_ notification: Notification) {
        refreshAnimDetail()
        if let i = selectedAnim, let a = host?.inspectedSlide.animations[i], host?.inspectedShape?.id != a.shapeID { host?.selectShape(a.shapeID) }
    }

    @objc private func addAnimation(_ mi: NSMenuItem) {
        guard let raw = mi.representedObject as? String, let e = AnimEffect(rawValue: raw), let id = host?.inspectedShape?.id else { return }
        var a = SlideAnimation(shapeID: id, effect: e)
        a.duration = e.defaultDuration
        host?.modifySlide("애니메이션 추가") { $0.animations.append(a) }
        let n = (host?.inspectedSlide.animations.count ?? 1) - 1
        animTable.reloadData()
        animTable.selectRowIndexes(IndexSet(integer: n), byExtendingSelection: false)
    }

    @objc private func removeAnimation(_ s: Any?) {
        guard let i = selectedAnim else { return }
        host?.modifySlide("애니메이션 삭제") { $0.animations.remove(at: i) }
    }

    private func move(_ d: Int) {
        guard let i = selectedAnim, let n = host?.inspectedSlide.animations.count, i + d >= 0, i + d < n else { return }
        host?.modifySlide("애니메이션 순서") { $0.animations.swapAt(i, i + d) }
        animTable.selectRowIndexes(IndexSet(integer: i + d), byExtendingSelection: false)
    }

    @objc private func moveAnimUp(_ s: Any?) { move(-1) }
    @objc private func moveAnimDown(_ s: Any?) { move(1) }
    @objc private func preview(_ s: Any?) { host?.previewFromCurrent() }
    @objc private func previewTransitionOnly(_ s: Any?) { host?.previewTransition() }

    @objc private func animEdited(_ s: Any?) {
        guard !updating, let i = selectedAnim, let a = host?.inspectedSlide.animations[i] else { return }
        let options = AnimEffect.allCases.filter { $0.animClass == a.effect.animClass }
        let effect = options[safe: effectPopup.indexOfSelectedItem] ?? a.effect
        let trigger = AnimTrigger.allCases[max(0, triggerPopup.indexOfSelectedItem)]
        let dir = AnimDirection.allCases[max(0, directionPopup.indexOfSelectedItem)]
        let dur = max(0, Double(durationField.stringValue) ?? a.duration)
        let delay = max(0, Double(delayField.stringValue) ?? a.delay)
        host?.modifySlide("애니메이션") { slide in
            slide.animations[i].effect = effect
            slide.animations[i].trigger = trigger
            slide.animations[i].direction = dir
            slide.animations[i].duration = effect == .appear || effect == .disappear ? 0 : dur
            slide.animations[i].delay = delay
        }
        animTable.selectRowIndexes(IndexSet(integer: i), byExtendingSelection: false)
    }

    // MARK: Transitions

    private var editedTransition: SlideTransition {
        var t = host?.inspectedSlide.transition ?? SlideTransition()
        t.kind = TransitionKind.allCases[max(0, transPopup.indexOfSelectedItem)]
        t.direction = AnimDirection.allCases[max(0, transDir.indexOfSelectedItem)]
        t.advanceOnClick=clickAdvance.state == .on
        t.vertical=verticalTransition.state == .on
        t.inward=inwardTransition.state == .on
        t.duration = max(0.1, Double(transDuration.stringValue) ?? t.duration)
        t.advanceAfter = autoAdvance.state == .on ? max(0, Double(autoSeconds.stringValue) ?? 5) : nil
        return t
    }

    @objc private func transitionEdited(_ s: Any?) {
        guard !updating else { return }
        let t = editedTransition
        host?.modifySlide("화면 전환") { $0.transition = t }
        if s as? NSButton !== autoAdvance { host?.previewTransition() }
    }

    @objc private func applyTransitionToAll(_ s: Any?) {
        let t = editedTransition
        host?.modifyAllSlides("모든 슬라이드에 전환 적용") { $0.transition = t }
    }
}

/// Document view for the inspector scroll views (top-aligned content).
final class FlippedClip: NSView {
    override var isFlipped: Bool { true }
    init(content: NSView) {
        super.init(frame: NSRect(x: 0, y: 0, width: 272, height: 900))
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: topAnchor), content.leadingAnchor.constraint(equalTo: leadingAnchor),
            widthAnchor.constraint(equalToConstant: 272), bottomAnchor.constraint(equalTo: content.bottomAnchor),
        ])
    }
    required init?(coder: NSCoder) { fatalError() }
}
