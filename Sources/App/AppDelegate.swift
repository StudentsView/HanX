import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        FontResolver.shared.registerBundledFonts()
        NSApp.mainMenu = MainMenu.build()
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool { false }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Files opened from Finder arrive right after launch; only show the
        // start screen when nothing was opened.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            if NSDocumentController.shared.documents.isEmpty { StartWindowController.shared.showWindow(nil) }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { StartWindowController.shared.showWindow(nil) }
        return true
    }
}

enum MainMenu {
    static func build() -> NSMenu {
        let main = NSMenu()

        func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
            let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let m = NSMenu(title: title)
            items.forEach(m.addItem)
            item.submenu = m
            return item
        }
        func item(_ title: String, _ action: Selector?, _ key: String = "", _ mods: NSEvent.ModifierFlags = .command, tag: Int = 0) -> NSMenuItem {
            let i = NSMenuItem(title: title, action: action, keyEquivalent: mods.contains(.shift) ? key.uppercased() : key)
            i.keyEquivalentModifierMask = mods
            i.tag = tag
            return i
        }

        let appName = "한워드"
        main.addItem(submenu(appName, [
            item("\(appName) 정보", #selector(NSApplication.orderFrontStandardAboutPanel(_:))),
            .separator(),
            item("한워드를 기본 앱으로 설정…", #selector(HWDocumentController.setAsDefaultApp(_:))),
            .separator(),
            item("\(appName) 가리기", #selector(NSApplication.hide(_:)), "h"),
            item("기타 가리기", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option]),
            item("모두 보기", #selector(NSApplication.unhideAllApplications(_:))),
            .separator(),
            item("\(appName) 종료", #selector(NSApplication.terminate(_:)), "q"),
        ]))

        main.addItem(submenu("파일", [
            item("새로 만들기…", #selector(NSDocumentController.newDocument(_:)), "n"),
            item("새 문서", #selector(HWDocumentController.newTextDocument(_:)), "n", [.command, .option]),
            item("새 프레젠테이션", #selector(HWDocumentController.newPresentation(_:)), "p", [.command, .option]),
            item("새 도표", #selector(HWDocumentController.newSpreadsheet(_:)), "t", [.command, .option]),
            item("열기…", #selector(NSDocumentController.openDocument(_:)), "o"),
            .separator(),
            item("닫기", #selector(NSWindow.performClose(_:)), "w"),
            item("저장", #selector(NSDocument.save(_:)), "s"),
            item("다른 이름으로 저장…", #selector(NSDocument.saveAs(_:)), "s", [.command, .shift]),
            item("복사본으로 내보내기…", #selector(NSDocument.saveTo(_:)), "s", [.command, .option]),
            item("되돌리기", #selector(NSDocument.revertToSaved(_:))),
            .separator(),
            item("편집 용지…", #selector(EditorWindowController.showPageSetup(_:)), "p", [.command, .shift]),
            item("인쇄…", #selector(NSDocument.printDocument(_:)), "p"),
        ]))

        let find = submenu("찾기", [
            item("찾기…", #selector(NSTextView.performFindPanelAction(_:)), "f", tag: Int(NSFindPanelAction.showFindPanel.rawValue)),
            item("찾아 바꾸기…", #selector(NSTextView.performFindPanelAction(_:)), "f", [.command, .option], tag: 12),
            item("다음 찾기", #selector(NSTextView.performFindPanelAction(_:)), "g", tag: Int(NSFindPanelAction.next.rawValue)),
            item("이전 찾기", #selector(NSTextView.performFindPanelAction(_:)), "g", [.command, .shift], tag: Int(NSFindPanelAction.previous.rawValue)),
        ])
        main.addItem(submenu("편집", [
            item("실행 취소", Selector(("undo:")), "z"),
            item("다시 실행", Selector(("redo:")), "z", [.command, .shift]),
            .separator(),
            item("오려 두기", #selector(NSText.cut(_:)), "x"),
            item("복사하기", #selector(NSText.copy(_:)), "c"),
            item("붙이기", #selector(NSText.paste(_:)), "v"),
            item("복제", #selector(SlideWindowController.duplicate(_:)), "d"),
            item("모양 없이 붙이기", #selector(NSTextView.pasteAsPlainText(_:)), "v", [.command, .option, .shift]),
            item("지우기", #selector(NSText.delete(_:))),
            item("모두 선택", #selector(NSText.selectAll(_:)), "a"),
            .separator(),
            find,
        ]))

        let fontMenu = NSFontManager.shared.fontMenu(true) ?? NSMenu(title: "글꼴")
        let fontItem = NSMenuItem(title: "글꼴", action: nil, keyEquivalent: "")
        fontItem.submenu = fontMenu
        main.addItem(submenu("입력", [
            item("표 만들기…", #selector(EditorWindowController.insertTable(_:)), "t", [.command, .control]),
            item("그림 넣기…", #selector(EditorWindowController.insertImage(_:)), "i", [.command, .control]),
            item("쪽 나누기", #selector(EditorWindowController.insertPageBreak(_:)), "\r", [.command]),
        ]))
        let numbering = submenu("쪽 번호 매기기", [
            item("아래 가운데 (- 1 -)", #selector(EditorWindowController.setPageNumbering(_:)), tag: 1),
            item("아래 오른쪽 (1)", #selector(EditorWindowController.setPageNumbering(_:)), tag: 2),
            item("위 오른쪽 (1 / 전체)", #selector(EditorWindowController.setPageNumbering(_:)), tag: 3),
            .separator(),
            item("쪽 번호 없음", #selector(EditorWindowController.setPageNumbering(_:)), tag: 0),
        ])
        main.addItem(submenu("쪽", [
            item("머리말/꼬리말…", #selector(EditorWindowController.editHeaderFooter(_:)), "h", [.command, .control]),
            numbering,
            item("편집 용지…", #selector(EditorWindowController.showPageSetup(_:))),
            item("쪽 나누기", #selector(EditorWindowController.insertPageBreak(_:))),
        ]))
        main.addItem(submenu("서식", [
            item("굵게", Selector(("toggleBoldface:")), "b"),
            item("기울임", Selector(("toggleItalics:")), "i"),
            item("밑줄", #selector(NSTextView.underline(_:)), "u"),
            .separator(),
            fontItem,
            item("왼쪽 정렬", #selector(NSText.alignLeft(_:)), "{"),
            item("가운데 정렬", #selector(NSText.alignCenter(_:)), "|"),
            item("양쪽 정렬", #selector(NSTextView.alignJustified(_:))),
            item("오른쪽 정렬", #selector(NSText.alignRight(_:)), "}"),
            .separator(),
            item("눈금자 보기", #selector(EditorWindowController.toggleRulerVisibility(_:)), "r"),
            item("색상 보기", #selector(NSApplication.orderFrontColorPanel(_:)), "c", [.command, .shift]),
        ]))
        main.addItem(submenu("도표", [
            item("행 삽입", #selector(SheetWindowController.insertRow(_:))),
            item("행 삭제", #selector(SheetWindowController.deleteRow(_:))),
            item("열 삽입", #selector(SheetWindowController.insertColumn(_:))),
            item("열 삭제", #selector(SheetWindowController.deleteColumn(_:))),
            .separator(),
            item("오름차순 정렬", #selector(SheetWindowController.sortAscending(_:))),
            item("내림차순 정렬", #selector(SheetWindowController.sortDescending(_:))),
            item("아래로 채우기", #selector(SheetWindowController.fillDown(_:)), "d"),
            item("오른쪽으로 채우기", #selector(SheetWindowController.fillRight(_:)), "r", [.command, .control]),
            item("연속 데이터 채우기", #selector(SheetWindowController.fillSeries(_:)), "d", [.command, .option]),
            item("틀 고정 / 해제", #selector(SheetWindowController.toggleFreezePanes(_:))),
            .separator(),
            item("셀 병합 / 해제", #selector(SheetWindowController.mergeCells(_:)), "m", [.command, .control]),
            item("자동 합계", #selector(SheetWindowController.autoSum(_:)), "=", [.command, .option]),
            item("굵게", #selector(SheetWindowController.toggleBold(_:))),
            item("테두리", #selector(SheetWindowController.toggleBorder(_:))),
            item("텍스트 줄 바꿈", #selector(SheetWindowController.toggleWrap(_:))),
            .separator(),
            item("시트 추가", #selector(SheetWindowController.addSheet(_:))),
            item("시트 이름 바꾸기…", #selector(SheetWindowController.renameSheet(_:))),
        ]))
        main.addItem(submenu("슬라이드", [
            item("새 슬라이드", #selector(SlideWindowController.newSlide(_:)), "n", [.command, .shift]),
            item("슬라이드 복제", #selector(SlideWindowController.duplicateSlide(_:)), "d", [.command, .shift]),
            item("슬라이드 삭제", #selector(SlideWindowController.deleteSlide(_:))),
            .separator(),
            item("텍스트 상자", #selector(SlideWindowController.insertTextBox(_:))),
            item("사각형", #selector(SlideWindowController.insertRect(_:))),
            item("둥근 사각형", #selector(SlideWindowController.insertRoundRect(_:))),
            item("타원", #selector(SlideWindowController.insertEllipse(_:))),
            item("삼각형", #selector(SlideWindowController.insertTriangle(_:))),
            item("화살표", #selector(SlideWindowController.insertArrow(_:))),
            item("선", #selector(SlideWindowController.insertLine(_:))),
            item("표", #selector(SlideWindowController.insertTable(_:))),
            item("그림…", #selector(SlideWindowController.insertImage(_:))),
            .separator(),
            item("화면 전환", #selector(SlideWindowController.showTransitions(_:))),
            item("전환 미리 보기", #selector(SlideWindowController.previewSelectedTransition(_:))),
            .separator(),
            item("처음부터 슬라이드 쇼", #selector(SlideWindowController.playSlideShow(_:)), "\r", [.command, .shift]),
            item("현재 슬라이드부터 쇼", #selector(SlideWindowController.playFromCurrent(_:)), "\r", [.command, .option]),
        ]))
        main.addItem(submenu("보기", [
            item("확대", #selector(EditorWindowController.zoomIn(_:)), "+"),
            item("축소", #selector(EditorWindowController.zoomOut(_:)), "-"),
            item("실제 크기", #selector(EditorWindowController.zoomActual(_:)), "0"),
            item("쪽 맞춤", #selector(EditorWindowController.zoomToFit(_:)), "9"),
        ]))
        let window = submenu("윈도우", [
            item("최소화", #selector(NSWindow.performMiniaturize(_:)), "m"),
            item("확대/축소", #selector(NSWindow.performZoom(_:))),
            .separator(),
            item("모두 앞으로 가져오기", #selector(NSApplication.arrangeInFront(_:))),
        ])
        main.addItem(window)
        NSApp.windowsMenu = window.submenu
        return main
    }
}
