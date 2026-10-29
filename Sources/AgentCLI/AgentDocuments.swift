import Foundation

enum AgentDocuments {
    static let documentOps=["replace_text","append_paragraph","append_block","insert_block","delete_block","set_paragraph","style_paragraph","set_cell","set_page"]
    static let slideOps=["replace_text","add_slide","duplicate_slide","delete_slide","move_slide","set_notes","set_transition","add_shape","update_shape","delete_shape"]

    static func color(_ value:Any?,_ label:String)throws->RGB? {
        guard let value,!(value is NSNull) else { return nil }
        guard let s=value as? String,let c=RGB(hex:s) else { throw AgentError("invalid_argument","\(label) must be a six-digit RGB hex string") }; return c
    }
    static func style(_ value:[String:Any],base:CharProps=CharProps())throws->CharProps {
        var c=base
        if let v=value["font"] { c.fontName=try AgentIO.string(v,"font"); c.eastAsianFontName=c.fontName }
        if let v=value["size"] { c.size=try AgentIO.number(v,"size"); guard c.size>0,c.size<=4000 else { throw AgentError("invalid_argument","size must be 0 < size <= 4000 points") } }
        for name in ["bold","italic","strike"] where value[name] != nil {
            let v=try AgentIO.bool(value[name],name)
            if name == "bold" { c.bold=v }; if name == "italic" { c.italic=v }; if name == "strike" { c.strike=v }
        }
        if let v=value["underline"] {
            if let s=v as? String,let u=UnderlineStyle(rawValue:s) { c.underline=u }
            else { c.underline=try AgentIO.bool(v,"underline") ? .single : .none }
        }
        if value["color"] != nil { c.color=try color(value["color"],"color") ?? .black }
        if value["highlight"] != nil { c.highlight=try color(value["highlight"],"highlight") }
        return c
    }
    static func paragraph(_ value:Any,base:CharProps=CharProps())throws->Paragraph {
        let spec:[String:Any]
        if let text=value as? String { spec=["text":text] } else { spec=try AgentIO.map(value,"paragraph") }
        var p=Paragraph(); p.markProps=try style(spec["style"] as? [String:Any] ?? [:],base:base)
        p.props.alignment = .left
        if let name=spec["alignment"] as? String { guard let a=Alignment(rawValue:name) else { throw AgentError("invalid_argument","Unknown alignment: \(name)") }; p.props.alignment=a }
        if let s=spec["styleName"] as? String { p.props.styleName=s }
        if let runs=spec["runs"] as? [Any] {
            for value in runs { let run=try AgentIO.map(value,"run"); let text=try AgentIO.string(run["text"],"run.text"); p.inlines.append(.text(text,try style(run,base:p.markProps))) }
        } else { p.inlines=[.text(try AgentIO.string(spec["text"] ?? "","text"),p.markProps)] }
        return p
    }
    static func table(_ spec:[String:Any])throws->Table {
        guard let rows=spec["rows"] as? [[Any]],!rows.isEmpty,rows.count<=10_000 else { throw AgentError("invalid_argument","table.rows must be a nonempty array of rows") }
        let columns=rows.map(\.count).max() ?? 0
        guard columns>0,columns<=1000,rows.count*columns<=100_000 else { throw AgentError("invalid_argument","Table dimensions exceed 100000 cells") }
        var t=Table()
        t.columnWidths=try (spec["columnWidths"] as? [Any] ?? Array(repeating:100,count:columns)).map { try AgentIO.number($0,"columnWidths") }
        guard t.columnWidths.count == columns,t.columnWidths.allSatisfy({$0>0}) else { throw AgentError("invalid_argument","columnWidths must match the table columns and be positive") }
        t.rows=try rows.map { row in
            try (0..<columns).map { i in
                var cell=TableCell()
                if i>=row.count { cell.blocks=[.paragraph(Paragraph())] }
                else if let text=row[i] as? String { cell.blocks=[.paragraph(try paragraph(text))] }
                else {
                    let s=try AgentIO.map(row[i],"cell")
                    cell.blocks=try (s["blocks"] as? [Any] ?? [["type":"paragraph","text":s["text"] ?? ""]]).map { try block($0) }
                    cell.colSpan=try AgentIO.index(s["colSpan"],"colSpan",default:1); cell.rowSpan=try AgentIO.index(s["rowSpan"],"rowSpan",default:1)
                    guard cell.colSpan>0,cell.rowSpan>0,i+cell.colSpan<=columns else { throw AgentError("invalid_argument","Invalid cell span") }
                }
                return cell
            }
        }
        for r in t.rows.indices { for c in t.rows[r].indices {
            guard !t.rows[r][c].isMergedAway else { continue }
            let cell=t.rows[r][c]
            guard r+cell.rowSpan<=t.rows.count else { throw AgentError("invalid_argument","rowSpan exceeds table") }
            if cell.rowSpan>1 || cell.colSpan>1 {
                for rr in r..<(r+cell.rowSpan) { for cc in c..<(c+cell.colSpan) where rr != r || cc != c { t.rows[rr][cc].isMergedAway=true } }
            }
        } }
        return t
    }
    static func block(_ value:Any)throws->Block {
        if let text=value as? String { return .paragraph(try paragraph(text)) }
        let spec=try AgentIO.map(value,"block"),type=spec["type"] as? String ?? "paragraph"
        switch type {
        case "paragraph":return .paragraph(try paragraph(spec))
        case "table":return .table(try table(spec))
        default:throw AgentError("invalid_argument","Unknown block type: \(type)")
        }
    }
    static func transition(_ spec:[String:Any],base:SlideTransition=SlideTransition())throws->SlideTransition {
        var t=base
        if let value=spec["kind"] { let s=try AgentIO.string(value,"transition.kind"); guard let k=TransitionKind(rawValue:s) else { throw AgentError("invalid_argument","Unknown transition: \(s)") }; t.kind=k }
        if let value=spec["duration"] { t.duration=try AgentIO.number(value,"duration"); guard t.duration>0,t.duration<=60 else { throw AgentError("invalid_argument","duration must be 0 < duration <= 60 seconds") } }
        if let value=spec["direction"] { let s=try AgentIO.string(value,"direction"); guard let k=AnimDirection(rawValue:s) else { throw AgentError("invalid_argument","Unknown direction: \(s)") }; t.direction=k }
        if let v=spec["advanceAfter"] { t.advanceAfter=v is NSNull ? nil : try AgentIO.number(v,"advanceAfter"); if let n=t.advanceAfter,n<0 { throw AgentError("invalid_argument","advanceAfter cannot be negative") } }
        if spec["advanceOnClick"] != nil { t.advanceOnClick=try AgentIO.bool(spec["advanceOnClick"],"advanceOnClick") }
        if spec["vertical"] != nil { t.vertical=try AgentIO.bool(spec["vertical"],"vertical") }
        if spec["inward"] != nil { t.inward=try AgentIO.bool(spec["inward"],"inward") }
        return t
    }
    static func shape(_ spec:[String:Any],base:SlideShape?=nil,id:Int,images:inout [String:ImageData],directory:URL)throws->SlideShape {
        var s=base ?? SlideShape(id:id,kind:.text,frame:Frame(x:60,y:60,w:300,h:100))
        if let v=spec["kind"] { let text=try AgentIO.string(v,"shape.kind"); guard let k=ShapeKind(rawValue:text) else { throw AgentError("invalid_argument","Unknown shape: \(text)") }; s.kind=k }
        if let v=spec["name"] { s.name=try AgentIO.string(v,"name") }
        for key in ["x","y","width","height","rotation"] where spec[key] != nil {
            let n=try AgentIO.number(spec[key],key)
            switch key { case "x":s.frame.x=n; case "y":s.frame.y=n; case "width":s.frame.w=n; case "height":s.frame.h=n; default:s.rotation=n }
        }
        guard s.frame.w>0,s.frame.h>0 else { throw AgentError("invalid_argument","Shape width and height must be positive") }
        if spec["fill"] != nil { s.fill=try color(spec["fill"],"fill") }
        if spec["line"] != nil { s.line=try color(spec["line"],"line") }
        if spec["lineWidth"] != nil { s.lineWidth=try AgentIO.number(spec["lineWidth"],"lineWidth"); guard s.lineWidth>=0 else { throw AgentError("invalid_argument","Negative lineWidth") } }
        if spec["lockAspect"] != nil { s.lockAspect=try AgentIO.bool(spec["lockAspect"],"lockAspect") }
        if spec["flipH"] != nil { s.flipH=try AgentIO.bool(spec["flipH"],"flipH") }
        if spec["flipV"] != nil { s.flipV=try AgentIO.bool(spec["flipV"],"flipV") }
        if spec["text"] != nil || spec["runs"] != nil || spec["paragraphs"] != nil {
            var c=CharProps(); c.size=24
            s.paragraphs=try (spec["paragraphs"] as? [Any] ?? [spec]).map { try paragraph($0,base:c) }
        } else if let styleSpec=spec["style"] as? [String:Any] { s.paragraphs=try s.paragraphs.map { try styling($0,styleSpec) } }
        if let t=spec["table"] { s.kind = .table; s.table=try table(AgentIO.map(t,"table")) }
        if let path=spec["imagePath"] as? String {
            let u=path.hasPrefix("/") || path.hasPrefix("~") ? AgentIO.url(path) : directory.appendingPathComponent(path)
            let data=try AgentIO.read(u.path),key="agent/\(UUID().uuidString)"
            images[key]=ImageData(name:u.lastPathComponent,data:data); s.kind = .image; s.imageID=key; s.lockAspect=true
        }
        return s
    }
    static func slide(_ spec:[String:Any],pres:Presentation,directory:URL)throws->Slide {
        var s=pres.contentSlide()
        s.shapes[0].paragraphs=[try paragraph(["text":spec["title"] ?? "","style":["bold":true,"size":36]])]
        var c=CharProps(); c.size=24
        s.shapes[1].paragraphs=try (spec["body"] as? [Any] ?? [""]).map { try paragraph($0,base:c) }
        if let notes=spec["notes"] { s.notes=try AgentIO.string(notes,"notes") }
        if let bg=spec["background"] { s.background=try color(bg,"background") }
        if let t=spec["transition"] { s.transition=try transition(AgentIO.map(t,"transition")) }
        for value in spec["shapes"] as? [Any] ?? [] {
            s.shapes.append(try shape(AgentIO.map(value,"shape"),id:pres.nextID(s),images:&pres.images,directory:directory))
        }
        return s
    }
    static func create(_ spec:[String:Any],base:URL)throws->AgentFile {
        if spec["kind"] as? String == "spreadsheet" { return .spreadsheet(try AgentSheets.create(spec)) }
        try AgentIO.validateNumbers(spec)
        let kind=try AgentIO.string(spec["kind"],"kind")
        switch kind {
        case "document":
            if let model=spec["model"] { return .document(try AgentIO.decode(AgentDocumentModel.self,model).document()) }
            let d=UDocument(); d.title=spec["title"] as? String
            let sections=spec["sections"] as? [Any] ?? [spec]
            guard !sections.isEmpty else { throw AgentError("invalid_argument","A document needs at least one section") }
            for value in sections {
                let section=try AgentIO.map(value,"section")
                var s=Section()
                if let page=section["page"] as? [String:Any] { s.page=try pageSetup(page,base:s.page) }
                let blocks=section["blocks"] as? [Any] ?? (section["text"] as? String).map { $0.components(separatedBy:"\n").map { ["type":"paragraph","text":$0] } } ?? [["type":"paragraph","text":""]]
                s.blocks=try blocks.map { value in
                    if let image=value as? [String:Any],image["type"] as? String == "image" {
                        let path=try AgentIO.string(image["path"],"image.path")
                        let url=path.hasPrefix("/") || path.hasPrefix("~") ? AgentIO.url(path) : base.appendingPathComponent(path)
                        let key="agent/\(UUID().uuidString)",bytes=try AgentIO.read(url.path)
                        let w=try AgentIO.number(image["width"],"image.width",default:200),h=try AgentIO.number(image["height"],"image.height",default:150)
                        guard w>0,h>0 else { throw AgentError("invalid_argument","Image dimensions must be positive") }
                        d.images[key]=ImageData(name:url.lastPathComponent,data:bytes)
                        var p=Paragraph(); p.inlines=[.image(id:key,width:w,height:h)]; return .paragraph(p)
                    }
                    return try block(value)
                }
                if let header=section["header"] as? [Any] { s.header=try header.map { try block($0) } }
                if let footer=section["footer"] as? [Any] { s.footer=try footer.map { try block($0) } }
                d.sections.append(s)
            }
            return .document(d)
        case "presentation":
            if let model=spec["model"] { return .presentation(try AgentIO.decode(AgentPresentationModel.self,model).presentation()) }
            let p=Presentation(); p.width=try AgentIO.number(spec["width"],"width",default:960); p.height=try AgentIO.number(spec["height"],"height",default:540)
            guard p.width>0,p.height>0 else { throw AgentError("invalid_argument","Slide dimensions must be positive") }
            guard let slides=spec["slides"] as? [Any] else { throw AgentError("invalid_argument","presentation.slides must be an array") }
            for value in slides { p.slides.append(try slide(AgentIO.map(value,"slide"),pres:p,directory:base)) }
            return .presentation(p)
        case "xml":return .xml(try AgentXML.parse(Data(AgentIO.string(spec["xml"],"xml").utf8)))
        default:throw AgentError("invalid_argument","kind must be document, presentation or xml")
        }
    }
    static func pageSetup(_ spec:[String:Any],base:PageSetup)throws->PageSetup {
        var p=base
        for key in ["width","height","marginTop","marginBottom","marginLeft","marginRight","header","footer"] where spec[key] != nil {
            let n=try AgentIO.number(spec[key],key); guard n>=0,n<=100_000 else { throw AgentError("invalid_argument","Page dimensions/margins must be 0...100000 points") }
            switch key { case "width":p.width=n; case "height":p.height=n; case "marginTop":p.marginTop=n; case "marginBottom":p.marginBottom=n; case "marginLeft":p.marginLeft=n; case "marginRight":p.marginRight=n; case "header":p.header=n; default:p.footer=n }
        }
        guard p.width>p.marginLeft+p.marginRight,p.height>p.marginTop+p.marginBottom else { throw AgentError("invalid_argument","Margins must leave a positive content area") }; return p
    }
    static func styling(_ paragraph:Paragraph,_ spec:[String:Any])throws->Paragraph {
        var p=paragraph; p.markProps=try style(spec,base:p.markProps)
        p.inlines=try p.inlines.map { inline in
            switch inline {
            case .text(let t,let c):return .text(t,try style(spec,base:c))
            case .tab(let c):return .tab(try style(spec,base:c))
            case .lineBreak(let c):return .lineBreak(try style(spec,base:c))
            case .field(let f,let c):return .field(f,try style(spec,base:c))
            default:return inline
            }
        }
        return p
    }
    /// Replace one range at a time, from the end, retaining all unaffected
    /// inline objects and run attributes, including matches spanning runs.
    static func replacing(_ original:Paragraph,find:String,replacement:String)->Paragraph {
        var p=original
        let text=original.plainText as NSString
        var ranges:[NSRange]=[],offset=0
        while offset<text.length {
            let r=text.range(of:find,range:NSRange(location:offset,length:text.length-offset))
            if r.location == NSNotFound { break }; ranges.append(r); offset=r.location+r.length
        }
        for range in ranges.reversed() {
            var result:[Inline]=[],pos=0,inserted=false
            for inline in p.inlines {
                let value=Paragraph(inlines:[inline]).plainText as NSString
                let end=pos+value.length
                if end<=range.location || pos>=NSMaxRange(range) { result.append(inline) }
                else {
                    let c:CharProps
                    switch inline { case .text(_,let s),.tab(let s),.lineBreak(let s),.field(_,let s):c=s; default:c=p.markProps }
                    let prefix=max(0,range.location-pos),suffix=max(0,end-NSMaxRange(range))
                    if prefix>0 { result.append(.text(value.substring(to:prefix),c)) }
                    if !inserted { if !replacement.isEmpty { result.append(.text(replacement,c)) }; inserted=true }
                    if suffix>0 { result.append(.text(value.substring(from:value.length-suffix),c)) }
                }
                pos=end
            }
            p.inlines=result
        }
        return p
    }
    static func transform(_ blocks:[Block],_ body:(Paragraph)throws->Paragraph)rethrows->[Block] {
        try blocks.map { block in
            switch block {
            case .paragraph(let p):return .paragraph(try body(p))
            case .table(var t):
                for r in t.rows.indices { for c in t.rows[r].indices { t.rows[r][c].blocks=try transform(t.rows[r][c].blocks,body) } }
                return .table(t)
            }
        }
    }
    static func edit(_ file:AgentFile,operations:[Any],directory:URL)throws->AgentFile {
        if case .spreadsheet(let b)=file { try AgentSheets.edit(b,operations); return file }
        try AgentIO.validateNumbers(operations)
        for value in operations {
            let op=try AgentIO.map(value,"operation"),name=try AgentIO.string(op["op"],"op")
            let common:Set<String>=["op"]
            let shapeKeys:Set<String>=["kind","name","x","y","width","height","rotation","fill","line","lineWidth","lockAspect","flipH","flipV","text","runs","paragraphs","style","table","imagePath"]
            let keys:[String:Set<String>]=[
                "replace_text":["find","replace"],"append_paragraph":["section","text","runs","style","alignment","styleName"],
                "append_block":["section","block"],"insert_block":["section","block","value"],"delete_block":["section","block"],
                "set_paragraph":["section","block","text","runs","style","alignment","styleName"],"style_paragraph":["section","block","style"],
                "set_cell":["section","block","row","column","text"],"set_page":["section","page"],
                "add_slide":["at","value"],"duplicate_slide":["slide"],"delete_slide":["slide"],"move_slide":["slide","to"],
                "set_notes":["slide","text"],"set_transition":["slide","kind","duration","direction","advanceAfter","advanceOnClick","vertical","inward"],
                "add_shape":["slide","value"],"delete_shape":["slide","shapeId"],"update_shape":shapeKeys.union(["slide","shapeId"])
            ]
            guard let allowed=keys[name] else { throw AgentError("invalid_operation","Unknown operation: \(name)") }
            for key in op.keys where !allowed.union(common).contains(key) { throw AgentError("invalid_argument","Unknown property \(key) in \(name)") }
            if name == "replace_text" {
                let find=try AgentIO.string(op["find"],"find"),replace=try AgentIO.string(op["replace"],"replace")
                guard !find.isEmpty else { throw AgentError("invalid_argument","find must not be empty") }
                let f:(Paragraph)->Paragraph={ replacing($0,find:find,replacement:replace) }
                switch file {
                case .document(let d):
                    for i in d.sections.indices {
                        d.sections[i].blocks=transform(d.sections[i].blocks,f)
                        if let b=d.sections[i].header { d.sections[i].header=transform(b,f) }; if let b=d.sections[i].footer { d.sections[i].footer=transform(b,f) }
                    }
                case .presentation(let p):
                    for i in p.slides.indices {
                        p.slides[i].notes=p.slides[i].notes.replacingOccurrences(of:find,with:replace)
                        for j in p.slides[i].shapes.indices {
                            p.slides[i].shapes[j].paragraphs=p.slides[i].shapes[j].paragraphs.map(f)
                            if var t=p.slides[i].shapes[j].table {
                                for r in t.rows.indices { for c in t.rows[r].indices { t.rows[r][c].blocks=transform(t.rows[r][c].blocks,f) } }; p.slides[i].shapes[j].table=t
                            }
                        }
                    }
                case .spreadsheet:throw AgentError("invalid_operation","Use spreadsheet operations")
                case .xml:throw AgentError("invalid_operation","Use xml edit with XPath for XML")
                }
                continue
            }
            switch file {
            case .document(let d):
                guard documentOps.contains(name) else { throw AgentError("invalid_operation","Unknown document operation: \(name)") }
                let si=try AgentIO.index(op["section"],"section",default:0)
                guard d.sections.indices.contains(si) else { throw AgentError("invalid_index","section out of range") }
                if name == "set_page" { d.sections[si].page=try pageSetup(AgentIO.map(op["page"],"page"),base:d.sections[si].page); continue }
                if name == "append_paragraph" { d.sections[si].blocks.append(.paragraph(try paragraph(op))); continue }
                if name == "append_block" { d.sections[si].blocks.append(try block(op["block"] as Any)); continue }
                let bi=try AgentIO.index(op["block"],"block")
                if name == "insert_block" {
                    guard bi<=d.sections[si].blocks.count else { throw AgentError("invalid_index","block out of range") }
                    d.sections[si].blocks.insert(try block(op["value"] as Any),at:bi); continue
                }
                guard d.sections[si].blocks.indices.contains(bi) else { throw AgentError("invalid_index","block out of range") }
                switch name {
                case "delete_block":d.sections[si].blocks.remove(at:bi)
                case "set_paragraph","style_paragraph":
                    guard case .paragraph(let p)=d.sections[si].blocks[bi] else { throw AgentError("invalid_operation","block is not a paragraph") }
                    if name == "style_paragraph" { d.sections[si].blocks[bi] = .paragraph(try styling(p,AgentIO.map(op["style"],"style"))) }
                    else { d.sections[si].blocks[bi] = .paragraph(try paragraph(op,base:p.markProps)) }
                case "set_cell":
                    guard case .table(var t)=d.sections[si].blocks[bi] else { throw AgentError("invalid_operation","block is not a table") }
                    let r=try AgentIO.index(op["row"],"row"),c=try AgentIO.index(op["column"],"column")
                    guard t.rows.indices.contains(r),t.rows[r].indices.contains(c),!t.rows[r][c].isMergedAway else { throw AgentError("invalid_index","cell is absent or merged away") }
                    t=SlideTableEditing.settingText(t,row:r,column:c,text:try AgentIO.string(op["text"],"text")); d.sections[si].blocks[bi] = .table(t)
                default:break
                }
            case .presentation(let p):
                guard slideOps.contains(name) else { throw AgentError("invalid_operation","Unknown presentation operation: \(name)") }
                if name == "add_slide" {
                    let at=try AgentIO.index(op["at"],"at",default:p.slides.count); guard at<=p.slides.count else { throw AgentError("invalid_index","at out of range") }
                    p.slides.insert(try slide(AgentIO.map(op["value"],"slide"),pres:p,directory:directory),at:at); continue
                }
                let i=try AgentIO.index(op["slide"],"slide")
                guard p.slides.indices.contains(i) else { throw AgentError("invalid_index","slide out of range") }
                switch name {
                case "duplicate_slide":p.slides.insert(p.slides[i],at:i+1)
                case "delete_slide":p.slides.remove(at:i)
                case "move_slide":
                    let to=try AgentIO.index(op["to"],"to"); guard p.slides.indices.contains(to) else { throw AgentError("invalid_index","to out of range") }; let s=p.slides.remove(at:i); p.slides.insert(s,at:to)
                case "set_notes":p.slides[i].notes=try AgentIO.string(op["text"],"text")
                case "set_transition":p.slides[i].transition=try transition(op,base:p.slides[i].transition)
                case "add_shape":p.slides[i].shapes.append(try shape(AgentIO.map(op["value"],"shape"),id:p.nextID(p.slides[i]),images:&p.images,directory:directory))
                case "update_shape","delete_shape":
                    let id=try AgentIO.index(op["shapeId"],"shapeId")
                    guard let j=p.slides[i].shapes.firstIndex(where:{$0.id == id}) else { throw AgentError("invalid_index","shapeId not found") }
                    if name == "delete_shape" { p.slides[i].shapes.remove(at:j); p.slides[i].animations.removeAll {$0.shapeID == id} }
                    else { p.slides[i].shapes[j]=try shape(op,base:p.slides[i].shapes[j],id:id,images:&p.images,directory:directory) }
                default:break
                }
            case .spreadsheet:throw AgentError("invalid_operation","Use spreadsheet operations")
            case .xml:throw AgentError("invalid_operation","Use xml edit with XPath for XML")
            }
        }
        return file
    }
}
