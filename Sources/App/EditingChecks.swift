import AppKit

enum EditingChecks {
    static func require(_ condition:@autoclosure ()->Bool,_ message:String) throws {
        if !condition() { throw FormatError.invalid("Editing check: "+message) }
    }
    static func near(_ a:Double,_ b:Double)->Bool { abs(a-b)<0.01 }
    static func run(to folder:URL) throws {
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let d=SlideDocument(); d.undoManager?.groupsByEvent=false
        var sh=SlideShape(id:2,name:"회전과 비율",kind:.rightArrow,frame:Frame(x:150,y:120,w:200,h:100))
        sh.rotation=90; sh.lockAspect=true; sh.fill=RGB(r:40,g:100,b:210); sh.line = .black
        sh.paragraphs=[Presentation.textParagraph("HanX",size:24,bold:true,align:.center,color:RGB(r:255,g:255,b:255))]
        d.pres.slides=[Slide(shapes:[sh])]; d.makeWindowControllers()
        guard let wc=d.windowControllers.first as? SlideWindowController else { throw FormatError.invalid("slide window") }
        func action(_ fn:()->Void) { d.undoManager?.beginUndoGrouping(); fn(); d.undoManager?.endUndoGrouping() }
        let canvas=wc.debugCanvas
        canvas.selectedID=2
        func event(_ type:NSEvent.EventType,_ x:Double,_ y:Double,_ flags:NSEvent.ModifierFlags=[])->NSEvent {
            let p=canvas.convert(NSPoint(x:x,y:y),to:nil)
            return NSEvent.mouseEvent(with:type,location:p,modifierFlags:flags,timestamp:0,windowNumber:wc.window!.windowNumber,context:nil,eventNumber:0,clickCount:1,pressure:1)!
        }
        let corner=ShapeGeometry.world(x:sh.frame.maxX,y:sh.frame.maxY,frame:sh.frame,rotation:90)
        canvas.mouseDown(with:event(.leftMouseDown,corner.0,corner.1))
        canvas.mouseDragged(with:event(.leftMouseDragged,corner.0-50,corner.1+100))
        action { canvas.mouseUp(with:event(.leftMouseUp,corner.0-50,corner.1+100)) }
        try require(near(d.pres.slides[0].shapes[0].frame.w,300),"rotated canvas resize width")
        try require(near(d.pres.slides[0].shapes[0].frame.h,150),"rotated canvas aspect")
        d.undoManager?.undo(); try require(d.pres.slides[0].shapes[0].frame == sh.frame,"resize undo")
        d.undoManager?.redo(); try require(near(d.pres.slides[0].shapes[0].frame.w,300),"resize redo")
        let f=canvas.selected!.frame, k=canvas.bounds.width/canvas.frame.width
        let handle=ShapeGeometry.world(x:f.x+f.w/2,y:f.y-28*k,frame:f,rotation:90)
        let v=ShapeGeometry.rotated(handle.0-f.x-f.w/2,handle.1-f.y-f.h/2,44)
        let dest=(f.x+f.w/2+v.0,f.y+f.h/2+v.1)
        canvas.mouseDown(with:event(.leftMouseDown,handle.0,handle.1))
        canvas.mouseDragged(with:event(.leftMouseDragged,dest.0,dest.1,[.shift]))
        action { canvas.mouseUp(with:event(.leftMouseUp,dest.0,dest.1,[.shift])) }
        try require(near(d.pres.slides[0].shapes[0].rotation,135),"rotation handle 15 degree snap")
        action { canvas.beginEditing(canvas.selected!) }
        action { canvas.editor?.insertText("편집 중 입력",replacementRange:NSRange(location:0,length:canvas.editor?.textStorage?.length ?? 0)) }
        action { wc.newSlide(nil) }
        try require(d.pres.slides[0].shapes[0].paragraphs.first?.plainText == "편집 중 입력" && canvas.editor == nil,"commit before new slide")
        action { canvas.selectedID=2; canvas.beginEditing(canvas.selected!) }
        action { canvas.editor?.insertText("이동 전 편집",replacementRange:NSRange(location:0,length:canvas.editor?.textStorage?.length ?? 0)) }
        action { wc.debugSlideList.selectRowIndexes(IndexSet(integer:0),byExtendingSelection:false) }
        try require(wc.inspectedSlide.shapes[0].paragraphs.first?.plainText == "편집 중 입력","switch slides while editing")
        try require(d.pres.slides[1].shapes[0].paragraphs.first?.plainText == "이동 전 편집","switch commits source slide")
        wc.debugSelect(slide:1,shape:0,animationTab:false)
        action { wc.deleteSlide(nil) }
        action { wc.resizePresentation(width:720,height:540) }
        d.undoManager?.undo(); try require(d.pres.width == 960 && d.pres.height == 540,"slide size undo")
        d.undoManager?.redo(); try require(d.pres.width == 720,"slide size redo")
        let copy=Presentation(); copy.slides=d.pres.slides
        action { wc.canvasPaste(copy) }
        try require(Set(d.pres.slides[0].shapes.map(\.id)).count == 2,"paste IDs")
        canvas.selectAll(nil); action { wc.ribbonCommand("fill","3") }
        try require(d.pres.slides[0].shapes.allSatisfy {$0.fill == OfficeRibbon.palette[2]},"multiple selection fill")
        let id=canvas.selectedID!; action { wc.modifySlide("test animation") { $0.animations=[SlideAnimation(shapeID:id,effect:.fade)] } }
        action { canvas.deleteSelection(nil) }; try require(d.pres.slides[0].shapes.isEmpty && d.pres.slides[0].animations.isEmpty,"delete animation references")
        d.undoManager?.undo(); try require(d.pres.slides[0].shapes.count == 2,"delete undo")
        canvas.selectedID=d.pres.slides[0].shapes[0].id
        action { canvas.beginEditing(canvas.selected!) }
        action { canvas.editor?.insertText("저장 중인 텍스트",replacementRange:NSRange(location:0,length:canvas.editor?.textStorage?.length ?? 0)) }
        var liveData=Data()
        d.undoManager?.beginUndoGrouping(); liveData=try d.data(ofType:DocType.pptx); d.undoManager?.endUndoGrouping()
        let liveBack=try PPTXReader(zip:ZipReader(data:liveData)).read()
        try require(liveBack.plainText.contains("저장 중인 텍스트") && canvas.editor == nil,"save commits active slide text")
        print("PASS canvas rotate/resize, multi-selection, paste, delete, slide size undo/redo, live text save")

        action { wc.insertTable(nil) }
        let tableID=canvas.selectedID!
        func descendants(_ view:NSView)->[NSView] { view.subviews.flatMap { [$0]+descendants($0) } }
        func editTable(_ value:String,apply:Bool) throws {
            wc.canvasEditTable(tableID)
            guard let panel=wc.debugTableWindow,let content=panel.contentView,let controller=panel.windowController as? SlideTableEditor else { throw FormatError.invalid("table editor panel") }
            content.layoutSubtreeIfNeeded()
            for _ in 0..<5 { RunLoop.main.run(until:Date(timeIntervalSinceNow:0.02)) }
            let views=descendants(content)
            guard let field=views.compactMap({$0 as? HWTextField}).first(where:{$0.isEnabled}),let button=views.compactMap({$0 as? NSButton}).first(where:{$0.title == (apply ? "적용" : "취소")}) else { throw FormatError.invalid("table editor controls") }
            field.stringValue=value
            controller.controlTextDidChange(Notification(name:NSControl.textDidChangeNotification,object:field))
            action { button.performClick(nil) }
        }
        let originalTable=canvas.selected!.table!
        try editTable("취소할 입력",apply:false)
        try require(SlideTableEditing.text(canvas.selected!.table!.rows[0][0]) == SlideTableEditing.text(originalTable.rows[0][0]),"table editor cancel")
        try editTable("적용한 내용",apply:true)
        try require(SlideTableEditing.text(canvas.selected!.table!.rows[0][0]) == "적용한 내용","table editor apply")
        d.undoManager?.undo()
        try require(SlideTableEditing.text(canvas.selected!.table!.rows[0][0]) == SlideTableEditing.text(originalTable.rows[0][0]),"table editor undo")
        d.undoManager?.redo()
        try require(SlideTableEditing.text(canvas.selected!.table!.rows[0][0]) == "적용한 내용","table editor redo")
        print("PASS table editor Apply/Cancel and document undo/redo")

        let sheetDoc=SheetDocument(); sheetDoc.undoManager?.groupsByEvent=false; sheetDoc.makeWindowControllers()
        func sheetAction(_ fn:()->Void) { sheetDoc.undoManager?.beginUndoGrouping(); fn(); sheetDoc.undoManager?.endUndoGrouping() }
        let sheetWC=sheetDoc.windowControllers.first as! SheetWindowController
        sheetWC.debugGrid.select(CellRef(row:1,col:1)); sheetWC.debugGrid.anchor=CellRef(row:3,col:3)
        sheetAction { sheetWC.ribbonCommand("font","Arial"); sheetWC.ribbonCommand("size","17"); sheetWC.ribbonCommand("fill","6") }
        let ws=sheetDoc.book.sheets[0]
        try require(ws.cells.count == 9,"blank range formatting covers 9 cells")
        try require(ws.cells[CellRef(row:3,col:3)]?.style.fontSize == 17,"bottom-right blank cell styled")
        sheetAction { sheetWC.ribbonCommand("merge","") }
        try require(ws.merges.count == 1,"merge selected range")
        sheetDoc.undoManager?.undo(); try require(ws.merges.isEmpty,"merge undo")
        sheetDoc.undoManager?.redo(); try require(ws.merges.count == 1,"merge redo")
        sheetAction { sheetWC.ribbonCommand("merge","") }
        sheetAction { sheetWC.ribbonCommand("rowHeight","36") }
        try require(ws.height(3) == 36,"row height")
        sheetDoc.undoManager?.undo(); try require(ws.height(3) == 20,"row height undo")
        sheetDoc.undoManager?.redo(); try require(ws.height(3) == 36,"row height redo")
        let xlsx=folder.appendingPathComponent("editing-check.xlsx")
        sheetAction { sheetWC.debugGrid.beginEdit("저장 중인 셀") }
        sheetDoc.undoManager?.beginUndoGrouping(); let liveSheetData=try sheetDoc.data(ofType:DocType.xlsx); sheetDoc.undoManager?.endUndoGrouping()
        try liveSheetData.write(to:xlsx)
        let book=try SheetIO.load(url:xlsx)
        try require(book.sheets[0].cells[CellRef(row:3,col:3)]?.style.fontSize == 17,"xlsx format roundtrip")
        try require(book.sheets[0].cells[CellRef(row:1,col:1)]?.input == "저장 중인 셀","save commits active cell")
        sheetWC.debugRibbon.showTab("셀 서식")
        try require(sheetWC.debugRibbon.selectedTitle("fill") == "파랑","ribbon cell fill reflection")
        print("PASS blank sheet range format, merge and dimensions undo/redo, XLSX save/reopen, ribbon reflection")

        let doc=HWDocument(); doc.undoManager?.groupsByEvent=false; doc.makeWindowControllers()
        func docAction(_ fn:()->Void) { doc.undoManager?.beginUndoGrouping(); fn(); doc.undoManager?.endUndoGrouping() }
        let editor=doc.windowControllers.first as! EditorWindowController, tv=editor.pages.firstTextView
        docAction { tv.insertText("HanX 서식 시험\n다음 문단",replacementRange:NSRange(location:0,length:0)) }; tv.setSelectedRange(NSRange(location:0,length:3))
        docAction { editor.ribbonCommand("size","22") }
        docAction { editor.ribbonCommand("bold","") }
        docAction { editor.ribbonCommand("charSpacing","1.5") }
        let attrs=doc.textStorage.attributes(at:0,effectiveRange:nil), c=AttributedBridge.charProps(attrs)

        try require(c.size == 22 && c.bold && c.spacing == 1.5,"document text formatting")
        doc.undoManager?.undo()
        try require(AttributedBridge.charProps(doc.textStorage.attributes(at:0,effectiveRange:nil)).spacing == 0,"character spacing undo")
        doc.undoManager?.undo()
        try require(!AttributedBridge.charProps(doc.textStorage.attributes(at:0,effectiveRange:nil)).bold,"bold undo")
        doc.undoManager?.undo()
        try require(AttributedBridge.charProps(doc.textStorage.attributes(at:0,effectiveRange:nil)).size == 10,"font size undo")
        doc.undoManager?.redo(); doc.undoManager?.redo(); doc.undoManager?.redo()
        docAction { editor.ribbonCommand("orientation","1") }; try require(doc.page.width>doc.page.height,"landscape page")
        docAction { editor.ribbonCommand("spacing","2") }
        editor.debugRibbon.showTab("홈")
        try require(editor.debugRibbon.selectedTitle("spacing") == "줄 간격 1.5","ribbon paragraph spacing reflection")
        editor.debugRibbon.showTab("쪽 문단")
        try require(editor.debugRibbon.selectedTitle("orientation") == "가로","ribbon page direction reflection")
        let docx=folder.appendingPathComponent("editing-check.docx")
        try doc.data(ofType:DocType.docx).write(to:docx)
        let docBack=try DocumentIO.load(url:docx)
        try require(docBack.plainText.contains("HanX 서식 시험"),"docx text roundtrip")
        print("PASS document font, emphasis, character spacing, page orientation, DOCX save/reopen")

        let pdfURL=folder.appendingPathComponent("editing-check.pdf")
        try doc.pdfData().write(to:pdfURL)
        try require(HWDocument.readableTypes.contains(DocType.pdf),"app advertises PDF input")
        let pdfDoc=HWDocument()
        try pdfDoc.read(from:pdfURL,ofType:DocType.pdf)
        try require(pdfDoc.textStorage.string.contains("HanX 서식 시험"),"PDF selectable Korean text import")
        try require(near(pdfDoc.page.width,doc.page.width) && near(pdfDoc.page.height,doc.page.height),"PDF page dimensions import")
        try require(pdfDoc.model.warnings.contains(where:{$0.contains("OCR")}),"PDF extraction limits available")
        pdfDoc.makeWindowControllers()
        let pdfEditor=pdfDoc.windowControllers.first as! EditorWindowController
        pdfEditor.updateStatus()
        let pdfLabels=descendants(pdfEditor.window!.contentView!).compactMap({$0 as? NSTextField})
        try require(pdfLabels.contains(where:{$0.stringValue.contains("PDF 텍스트 가져오기") && ($0.toolTip?.contains("OCR") ?? false)}),"PDF extraction notice visible in editor status")
        let pdfDocx=folder.appendingPathComponent("editing-check-from-pdf.docx")
        try pdfDoc.data(ofType:DocType.docx).write(to:pdfDocx)
        let pdfBack=try DocumentIO.load(url:pdfDocx)
        try require(pdfBack.plainText.contains("HanX 서식 시험"),"PDF text saves as editable DOCX")
        pdfEditor.close()
        print("PASS app PDF import, Korean text, page dimensions, extraction notice, DOCX save/reopen")

        let demo=Presentation(); demo.slides=[]
        for (i,kind) in TransitionKind.allCases.enumerated() {
            var slide=Slide(); slide.background=i%2 == 0 ? RGB(r:20,g:43,b:76) : RGB(r:238,g:245,b:250)
            slide.transition.kind=kind; slide.transition.duration=1.2
            var title=SlideShape(id:2,name:"제목",kind:.text,frame:Frame(x:60,y:35,w:840,h:70))
            title.paragraphs=[Presentation.textParagraph("HanX, "+kind.title,size:34,bold:true,color:i%2 == 0 ? RGB(r:255,g:255,b:255) : RGB(r:20,g:43,b:76))]
            slide.shapes=[title]
            for (j,shape) in ShapeKind.allCases.filter({ ![.image,.table,.line,.text].contains($0) }).enumerated() {
                var s=SlideShape(id:j+3,name:shape.title,kind:shape,frame:Frame(x:65+Double(j%5)*174,y:140+Double(j/5)*94,w:128,h:65))
                s.fill=OfficeRibbon.palette[[2,4,5,6][j%4]]; s.line=RGB(r:255,g:255,b:255); s.lineWidth=1.5; s.rotation=Double(j%3-1)*8
                slide.shapes.append(s)
            }
            demo.slides.append(slide)
        }
        try PPTXWriter.write(demo).write(to:folder.appendingPathComponent("HanX-Demo.pptx"))
        for (i,kind) in TransitionKind.allCases.enumerated() where kind != .none {
            guard let image=TransitionFilmstrip.render(demo,to:i) else { throw FormatError.invalid("filmstrip") }
            try NSBitmapImageRep(cgImage:image).representation(using:.png,properties:[:])?.write(to:folder.appendingPathComponent("transition-"+kind.rawValue+".png"))
        }
        print("PASS 20 transition filmstrips rendered; demo PPTX saved")
        withExtendedLifetime([d,sheetDoc,doc]) {}
    }
}
