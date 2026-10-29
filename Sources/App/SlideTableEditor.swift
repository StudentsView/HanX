import AppKit

final class SlideTableEditor:NSWindowController,NSTableViewDataSource,NSTableViewDelegate,NSTextFieldDelegate {
    private var table:Table
    private let grid=NSTableView()
    private let completion:(Table?)->Void
    private weak var parent:NSWindow?
    private var fields:[ObjectIdentifier:(Int,Int)]=[:]
    init(table:Table,parent:NSWindow,completion:@escaping (Table?)->Void) {
        self.table=table; self.parent=parent; self.completion=completion
        let panel=NSPanel(contentRect:NSRect(x:0,y:0,width:700,height:450),styleMask:[.titled],backing:.buffered,defer:false)
        panel.title="표 편집"; HWTheme.style(panel)
        super.init(window:panel)
        guard let content=panel.contentView else { return }
        let heading=NSTextField(labelWithString:"표 내용"); heading.font=HWTheme.font(22,weight:.semibold); heading.textColor=HWTheme.ink
        heading.frame=NSRect(x:24,y:393,width:652,height:32); content.addSubview(heading)
        let info=NSTextField(labelWithString:"셀을 선택해 내용을 입력하세요."); info.font=HWTheme.font(12); info.textColor=HWTheme.secondary
        info.frame=NSRect(x:24,y:368,width:652,height:20); content.addSubview(info)
        for i in 0..<table.columnCount {
            let col=NSTableColumn(identifier:.init(String(i))); col.title=CellRef.columnName(i); col.headerCell.font=HWTheme.font(11); col.width=max(130,652/CGFloat(max(1,table.columnCount))); grid.addTableColumn(col)
        }
        grid.rowHeight=36; grid.intercellSpacing=NSSize(width:1,height:1); grid.backgroundColor=HWTheme.toolbar
        grid.dataSource=self; grid.delegate=self; grid.selectionHighlightStyle = .none
        let scroll=NSScrollView(frame:NSRect(x:24,y:72,width:652,height:282)); scroll.hasVerticalScroller=true; scroll.hasHorizontalScroller=true; scroll.borderType = .noBorder; scroll.documentView=grid; content.addSubview(scroll)
        let cancel=HWActionButton(title:"취소",target:self,action:#selector(cancel(_:))); cancel.frame=NSRect(x:520,y:22,width:68,height:32); cancel.keyEquivalent="\u{1b}"
        let apply=HWActionButton(title:"적용",target:self,action:#selector(apply(_:))); apply.frame=NSRect(x:600,y:22,width:76,height:32); apply.state = .on; apply.keyEquivalent="\r"
        content.addSubview(cancel); content.addSubview(apply)
    }
    required init?(coder:NSCoder) { fatalError() }
    func present() { if let window { parent?.beginSheet(window) } }
    func numberOfRows(in tableView:NSTableView)->Int { table.rows.count }
    func tableView(_ tableView:NSTableView,viewFor tableColumn:NSTableColumn?,row:Int)->NSView? {
        guard let key=tableColumn?.identifier.rawValue,let column=Int(key),table.rows[row].indices.contains(column) else { return nil }
        let identifier=NSUserInterfaceItemIdentifier("cell")
        let field=(tableView.makeView(withIdentifier:identifier,owner:self) as? HWTextField) ?? HWTextField()
        field.identifier=identifier; field.stringValue=SlideTableEditing.text(table.rows[row][column]); field.isEnabled = !table.rows[row][column].isMergedAway
        field.delegate=self; field.target=self; field.action=#selector(fieldChanged(_:)); fields[ObjectIdentifier(field)]=(row,column)
        field.setAccessibilityLabel("\(row+1)행 \(CellRef.columnName(column))열")
        return field
    }
    @objc private func fieldChanged(_ field:NSTextField) {
        guard let (r,c)=fields[ObjectIdentifier(field)] else { return }
        table=SlideTableEditing.settingText(table,row:r,column:c,text:field.currentEditor()?.string ?? field.stringValue)
    }
    func controlTextDidChange(_ notification:Notification) { if let field=notification.object as? NSTextField { fieldChanged(field) } }
    func controlTextDidEndEditing(_ notification:Notification) { if let field=notification.object as? NSTextField { fieldChanged(field) } }
    @objc private func cancel(_ sender:Any?) { finish(nil) }
    @objc private func apply(_ sender:Any?) { window?.makeFirstResponder(nil); finish(table) }
    private func finish(_ result:Table?) { if let window { parent?.endSheet(window); window.orderOut(nil) }; completion(result) }
}
