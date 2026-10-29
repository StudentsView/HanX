import Foundation

/// HWPML 2.x adapter. Generic XML editing remains available for controls that
/// the unified model cannot represent; conversion reports these explicitly.
enum HWPML {
    static func read(_ xml:XMLDocument)throws->UDocument {
        guard let root=xml.rootElement(),root.local.uppercased() == "HWPML",let body=root.child("BODY") else { throw AgentError("invalid_format","Expected HWPML with BODY") }
        let d=UDocument(); d.source = .hwp; d.title=root.first("TITLE")?.stringValue
        // Validate cardinalities before any span arithmetic or array growth.
        for table in body.all("TABLE") {
            guard table.children("ROW").count<=10_000 else { throw AgentError("invalid_format","HWPML table has too many rows") }
            for cell in table.children("ROW").flatMap({$0.children("CELL")}) {
                guard let col=Int(cell.attr("ColAddr") ?? "0"),col>=0,col<1000,
                      let span=Int(cell.attr("ColSpan") ?? "1"),span>0,span<=1000-col,
                      let rows=Int(cell.attr("RowSpan") ?? "1"),rows>0,rows<=10_000 else { throw AgentError("invalid_format","Invalid HWPML table cell span") }
            }
        }
        var fonts:[String:[Int:String]]=[:],chars:[Int:CharProps]=[:],paras:[Int:ParaProps]=[:],binary:[String:String]=[:]
        for face in root.all("FONTFACE") {
            var map:[Int:String]=[:]
            for font in face.children("FONT") { if let id=font.attrInt("Id"),let name=font.attr("Name") { map[id]=name } }
            fonts[face.attr("Lang") ?? "Hangul"]=map
        }
        func rgb(_ value:String?)->RGB? {
            guard let value else { return nil }
            if value.hasPrefix("#") { return RGB(hex:value) }
            guard let n=UInt32(value),n<=0xFFFFFF else { return nil }
            return RGB(colorref:n)
        }
        for shape in root.all("CHARSHAPE") {
            guard let id=shape.attrInt("Id") else { continue }
            var c=CharProps(); c.size=(shape.attrDouble("Height") ?? 1000)/100
            if let ids=shape.child("FONTID") {
                c.fontName=fonts["Latin"]?[ids.attrInt("Latin") ?? 0] ?? c.fontName
                c.eastAsianFontName=fonts["Hangul"]?[ids.attrInt("Hangul") ?? 0]
            }
            c.bold=shape.child("BOLD") != nil; c.italic=shape.child("ITALIC") != nil
            c.underline=shape.child("UNDERLINE") == nil ? .none : .single
            c.strike=shape.child("STRIKEOUT") != nil
            c.color=rgb(shape.attr("TextColor")) ?? .black; c.highlight=rgb(shape.attr("ShadeColor"))
            if shape.child("SUPERSCRIPT") != nil { c.verticalAlign = .superscript }
            if shape.child("SUBSCRIPT") != nil { c.verticalAlign = .subscript }
            c.widthRatio=shape.child("RATIO")?.attrDouble("Hangul") ?? 100
            chars[id]=c
        }
        for shape in root.all("PARASHAPE") {
            guard let id=shape.attrInt("Id") else { continue }
            var p=ParaProps(); p.alignment=Alignment(rawValue:(shape.attr("Align") ?? "Justify").lowercased()) ?? .justify
            if let margin=shape.child("PARAMARGIN") {
                p.indentLeft=(margin.attrDouble("Left") ?? 0)/100; p.indentRight=(margin.attrDouble("Right") ?? 0)/100
                p.firstLine=(margin.attrDouble("Indent") ?? 0)/100
                p.spaceBefore=(margin.attrDouble("Prev") ?? 0)/100; p.spaceAfter=(margin.attrDouble("Next") ?? 0)/100
            }
            let margin=shape.child("PARAMARGIN")
            let spacing=margin?.attrDouble("LineSpacing") ?? 160
            switch margin?.attr("LineSpacingType") ?? "Percent" {
            case "Fixed":p.lineSpacing = .exact(spacing/100)
            case "AtLeast":p.lineSpacing = .atLeast(spacing/100)
            default:p.lineSpacing = .percentOfSize(spacing)
            }
            paras[id]=p
        }
        for item in root.all("BINITEM") { if let id=item.attr("BinData") ?? item.attr("Id") { binary[id]=item.attr("Format") ?? "bin" } }
        for item in root.all("BINDATA") {
            guard let id=item.attr("Id"),let text=item.stringValue,let bytes=Data(base64Encoded:text,options:.ignoreUnknownCharacters) else { continue }
            var data=bytes
            if item.attr("Compress")?.lowercased() == "true" {
                guard let inflated=try? Deflate.inflate(Array(bytes)) else { d.warnings.append("HWPML binary \(id) could not be decompressed"); continue }; data=Data(inflated)
            }
            d.images[id]=ImageData(name:"image\(id).\(binary[id] ?? "bin")",data:data)
        }
        var unsupported=Set<String>()
        func charNodes(_ nodes:[XMLNode],_ c:CharProps)->[Inline] {
            var result:[Inline]=[]
            for node in nodes {
                if node.kind == .text { if let s=node.stringValue,!s.isEmpty { result.append(.text(s,c)) }; continue }
                guard let e=node as? XMLElement else { continue }
                switch e.local {
                case "TAB":result.append(.tab(c))
                case "LINEBREAK":result.append(.lineBreak(c))
                case "NBSPACE":result.append(.text("\u{00A0}",c))
                case "FWSPACE":result.append(.text("\u{3000}",c))
                case "HYPHEN":result.append(.text("-",c))
                default:result += charNodes(e.children ?? [],c)
                }
            }
            return result
        }
        func blocks(_ parent:XMLElement)->[Block] {
            var result:[Block]=[]
            for pe in parent.children("P") {
                var p=Paragraph(); p.props=paras[pe.attrInt("ParaShape") ?? 0] ?? ParaProps(); p.props.pageBreakBefore=pe.attr("PageBreak") == "true"
                var objects:[Block]=[]
                for text in pe.children("TEXT") {
                    let c=chars[text.attrInt("CharShape") ?? 0] ?? CharProps(); if p.inlines.isEmpty { p.markProps=c }
                    for child in text.elementChildren {
                        switch child.local {
                        case "CHAR":p.inlines += charNodes(child.children ?? [],c)
                        case "TABLE":
                            var t=Table(); var widths:[Double]=[]
                            for row in child.children("ROW") {
                                var cells:[TableCell]=[]
                                for ce in row.children("CELL") {
                                    let col=ce.attrInt("ColAddr") ?? cells.count
                                    guard col>=0,col<1000 else { continue }
                                    while cells.count<=col { var empty=TableCell(); empty.isMergedAway=true; cells.append(empty) }
                                    var cell=TableCell(); cell.colSpan=ce.attrInt("ColSpan") ?? 1; cell.rowSpan=ce.attrInt("RowSpan") ?? 1
                                    guard cell.colSpan>0,cell.colSpan<=1000-col,cell.rowSpan>0,cell.rowSpan<=10_000 else { unsupported.insert("invalid TABLE span"); continue }
                                    cell.width=ce.attrDouble("Width").map {$0/100}; cell.height=ce.attrDouble("Height").map {$0/100}
                                    cell.blocks=ce.child("PARALIST").map(blocks) ?? [.paragraph(Paragraph())]
                                    if let margin=ce.child("CELLMARGIN") { cell.padding=Insets(left:(margin.attrDouble("Left") ?? 0)/100,right:(margin.attrDouble("Right") ?? 0)/100,top:(margin.attrDouble("Top") ?? 0)/100,bottom:(margin.attrDouble("Bottom") ?? 0)/100) }
                                    cells[col]=cell
                                    while widths.count<col+cell.colSpan { widths.append(100) }
                                    if let width=cell.width { for i in col..<(col+min(cell.colSpan,1000-col)) { widths[i]=width/Double(cell.colSpan) } }
                                }
                                t.rows.append(cells)
                            }
                            let count=max(child.attrInt("ColCount") ?? 0,t.rows.map(\.count).max() ?? 0)
                            guard count<=1000,t.rows.count<=10_000 else { unsupported.insert("oversized TABLE"); continue }
                            while widths.count<count { widths.append(100) }; t.columnWidths=Array(widths.prefix(count))
                            for r in t.rows.indices { while t.rows[r].count<count { var empty=TableCell(); empty.isMergedAway=true; t.rows[r].append(empty) } }
                            if !t.rows.isEmpty { objects.append(.table(t)) }
                        case "PICTURE":
                            if let id=child.first("IMAGE")?.attr("BinItem"),d.images[id] != nil {
                                let size=child.first("SIZE")
                                p.inlines.append(.image(id:id,width:(size?.attrDouble("Width") ?? 10000)/100,height:(size?.attrDouble("Height") ?? 10000)/100))
                            } else { unsupported.insert("PICTURE without embedded data") }
                        case "SECDEF","COLDEF","HEADER","FOOTER":break
                        default:unsupported.insert(child.local)
                        }
                    }
                }
                let contentParagraph=pe.children("TEXT").allSatisfy { $0.elementChildren.isEmpty || $0.child("CHAR") != nil }
                if !p.inlines.isEmpty || (objects.isEmpty && contentParagraph) { result.append(.paragraph(p)) }
                result += objects
            }
            return result
        }
        for section in body.children("SECTION") {
            var s=Section(); s.blocks=blocks(section)
            if let page=section.first("PAGEDEF") {
                s.page.width=(page.attrDouble("Width") ?? 59530)/100; s.page.height=(page.attrDouble("Height") ?? 84190)/100
                if let m=page.child("PAGEMARGIN") {
                    s.page.marginLeft=(m.attrDouble("Left") ?? 8500)/100; s.page.marginRight=(m.attrDouble("Right") ?? 8500)/100
                    s.page.marginTop=(m.attrDouble("Top") ?? 5670)/100; s.page.marginBottom=(m.attrDouble("Bottom") ?? 4250)/100
                    s.page.header=(m.attrDouble("Header") ?? 4250)/100; s.page.footer=(m.attrDouble("Footer") ?? 4250)/100
                }
                if page.attrInt("Landscape") == 1,s.page.width<s.page.height { swap(&s.page.width,&s.page.height) }
            }
            if let header=section.first("HEADER")?.child("PARALIST") { s.header=blocks(header) }
            if let footer=section.first("FOOTER")?.child("PARALIST") { s.footer=blocks(footer) }
            d.sections.append(s)
        }
        guard !d.sections.isEmpty else { throw AgentError("invalid_format","HWPML contains no sections") }
        if !unsupported.isEmpty { d.warnings.append("HWPML model conversion omits controls: \(unsupported.sorted().joined(separator:", ")). Use xml edit to retain the original tree.") }
        return d
    }

    static func write(_ d:UDocument)throws->Data {
        let tables=HancomTables(d)
        var missing=Set<String>()
        func gather(_ blocks:[Block]) {
            for block in blocks { switch block {
            case .paragraph(let p):
                _=tables.paraShape(p.props); _=tables.charShape(p.markProps)
                for inline in p.inlines { switch inline { case .text(_,let c),.tab(let c),.lineBreak(let c),.field(_,let c):_=tables.charShape(c); case .image(let id,_,_):if tables.image(id,d) == nil { missing.insert(id) }; default:break } }
            case .table(let t):for row in t.rows { for cell in row { gather(cell.blocks) } }
            } }
        }
        for s in d.sections { gather(s.blocks); gather(s.header ?? []); gather(s.footer ?? []) }
        guard missing.isEmpty else { throw AgentError("invalid_argument","Missing embedded image data: \(missing.sorted().joined(separator:", "))") }
        let lang=["Hangul","Latin","Hanja","Japanese","Other","Symbol","User"]
        let fonts=lang.map { l in "<FONTFACE Lang=\"\(l)\" Count=\"\(tables.fonts.count)\">"+tables.fonts.enumerated().map { "<FONT Id=\"\($0.offset)\" Name=\"\(XMLEscape.text($0.element))\" Type=\"ttf\"/>" }.joined()+"</FONTFACE>" }.joined()
        let chars=tables.charShapes.enumerated().map { i,c -> String in
            let font=tables.font(c.eastAsianFontName ?? c.fontName),latin=tables.font(c.fontName)
            let ids=lang.map { "\($0)=\"\($0 == "Latin" ? latin : font)\"" }.joined(separator:" ")
            let ratio=lang.map { "\($0)=\"\(Int(c.widthRatio))\"" }.joined(separator:" ")
            var flags=(c.bold ? "<BOLD/>" : "")+(c.italic ? "<ITALIC/>" : "")
            if c.underline != .none { flags += "<UNDERLINE Type=\"Bottom\" Shape=\"Solid\" Color=\"\(c.color.colorref)\"/>" }
            if c.strike { flags += "<STRIKEOUT Type=\"Continuous\"/>" }
            if c.verticalAlign == .superscript { flags += "<SUPERSCRIPT/>" }; if c.verticalAlign == .subscript { flags += "<SUBSCRIPT/>" }
            return "<CHARSHAPE Id=\"\(i)\" Height=\"\(Int(c.size*100))\" TextColor=\"\(c.color.colorref)\" ShadeColor=\"\(c.highlight?.colorref ?? UInt32.max)\"><FONTID \(ids)/><RATIO \(ratio)/>\(flags)</CHARSHAPE>"
        }.joined()
        let paras=tables.paraShapes.enumerated().map { i,p -> String in
            let spacing:Double,type:String
            switch p.lineSpacing { case .multiple(let n):spacing=n*100; type="Percent"; case .percentOfSize(let n):spacing=n; type="Percent"; case .exact(let n):spacing=n*100; type="Fixed"; case .atLeast(let n):spacing=n*100; type="AtLeast" }
            return "<PARASHAPE Id=\"\(i)\" Align=\"\(p.alignment.rawValue.capitalized)\" TabDef=\"0\"><PARAMARGIN Indent=\"\(Int(p.firstLine*100))\" Left=\"\(Int(p.indentLeft*100))\" Right=\"\(Int(p.indentRight*100))\" Prev=\"\(Int(p.spaceBefore*100))\" Next=\"\(Int(p.spaceAfter*100))\" LineSpacingType=\"\(type)\" LineSpacing=\"\(Int(spacing))\"/></PARASHAPE>"
        }.joined()
        func text(_ text:String)->String { XMLEscape.text(text).replacingOccurrences(of:"\t",with:"<TAB/>").replacingOccurrences(of:"\n",with:"<LINEBREAK/>") }
        var instance=0
        func shapeObject(_ width:Double,_ height:Double)->String {
            instance += 1
            return "<SHAPEOBJECT InstId=\"\(instance)\" ZOrder=\"\(instance)\"><SIZE Width=\"\(Int(width*100))\" Height=\"\(Int(height*100))\" WidthRelTo=\"Absolute\" HeightRelTo=\"Absolute\"/><POSITION TreatAsChar=\"true\" VertRelTo=\"Para\" HorzRelTo=\"Para\" VertAlign=\"Top\" HorzAlign=\"Left\" VertOffset=\"0\" HorzOffset=\"0\"/><OUTSIDEMARGIN Left=\"0\" Right=\"0\" Top=\"0\" Bottom=\"0\"/></SHAPEOBJECT>"
        }
        func blocks(_ values:[Block])->String {
            values.map { block in
                switch block {
                case .paragraph(let p):
                    var runs=""
                    for inline in p.inlines {
                        let value:String,c:CharProps
                        switch inline {
                        case .text(let s,let style):value="<CHAR>\(text(s))</CHAR>"; c=style
                        case .tab(let style):value="<CHAR><TAB/></CHAR>"; c=style
                        case .lineBreak(let style):value="<CHAR><LINEBREAK/></CHAR>"; c=style
                        case .pageBreak:value="<CHAR><LINEBREAK/></CHAR>"; c=p.markProps
                        case .field(let kind,let style):value="<CHAR>\(kind == .page ? "#" : "##")</CHAR>"; c=style
                        case .image(let id,let w,let h):
                            let index=tables.image(id,d)!
                            value="<PICTURE>\(shapeObject(w,h))<IMAGE BinItem=\"\(index)\" Bright=\"0\" Contrast=\"0\" Effect=\"RealPic\"/></PICTURE>"; c=p.markProps
                        }
                        runs += "<TEXT CharShape=\"\(tables.charShape(c))\">\(value)</TEXT>"
                    }
                    if runs.isEmpty { runs="<TEXT CharShape=\"\(tables.charShape(p.markProps))\"><CHAR/></TEXT>" }
                    return "<P ParaShape=\"\(tables.paraShape(p.props))\" Style=\"0\" PageBreak=\"\(p.props.pageBreakBefore)\">\(runs)</P>"
                case .table(let t):
                    var rows=""
                    for (r,row) in t.rows.enumerated() {
                        var cells=""
                        for (c,cell) in row.enumerated() where !cell.isMergedAway {
                            let width=cell.width ?? t.columnWidths.dropFirst(c).prefix(cell.colSpan).reduce(0,+)
                            cells += "<CELL ColAddr=\"\(c)\" RowAddr=\"\(r)\" ColSpan=\"\(cell.colSpan)\" RowSpan=\"\(cell.rowSpan)\" Width=\"\(Int(width*100))\" Height=\"\(Int((cell.height ?? 24)*100))\" BorderFill=\"1\"><PARALIST>\(blocks(cell.blocks))</PARALIST></CELL>"
                        }
                        rows += "<ROW>\(cells)</ROW>"
                    }
                    return "<P ParaShape=\"0\" Style=\"0\"><TEXT CharShape=\"0\"><TABLE RowCount=\"\(t.rows.count)\" ColCount=\"\(t.columnCount)\" CellSpacing=\"0\" BorderFill=\"1\" PageBreak=\"Cell\">\(shapeObject(t.columnWidths.reduce(0,+),Double(t.rows.count)*24))<INSIDEMARGIN Left=\"360\" Right=\"360\" Top=\"180\" Bottom=\"180\"/>\(rows)</TABLE></TEXT></P>"
                }
            }.joined()
        }
        var sections=""
        for (i,s) in d.sections.enumerated() {
            let p=s.page
            let def="<SECDEF><PAGEDEF Width=\"\(Int(p.width*100))\" Height=\"\(Int(p.height*100))\" Landscape=\"0\"><PAGEMARGIN Left=\"\(Int(p.marginLeft*100))\" Right=\"\(Int(p.marginRight*100))\" Top=\"\(Int(p.marginTop*100))\" Bottom=\"\(Int(p.marginBottom*100))\" Header=\"\(Int(p.header*100))\" Footer=\"\(Int(p.footer*100))\" Gutter=\"0\"/></PAGEDEF></SECDEF>"
            let header=s.header.map { "<HEADER ApplyPageType=\"Both\"><PARALIST>\(blocks($0))</PARALIST></HEADER>" } ?? ""
            let footer=s.footer.map { "<FOOTER ApplyPageType=\"Both\"><PARALIST>\(blocks($0))</PARALIST></FOOTER>" } ?? ""
            sections += "<SECTION Id=\"\(i)\"><P ParaShape=\"0\" Style=\"0\"><TEXT CharShape=\"0\">\(def)\(header)\(footer)</TEXT></P>\(blocks(s.blocks))</SECTION>"
        }
        let bins=tables.images.map { "<BINITEM BinData=\"\($0.index)\" Format=\"\($0.data.ext)\" Type=\"Embedding\"/>" }.joined()
        let storage=tables.images.map { "<BINDATA Id=\"\($0.index)\" Size=\"\($0.data.data.count)\" Encoding=\"Base64\" Compress=\"false\">\($0.data.data.base64EncodedString())</BINDATA>" }.joined()
        let xml="<?xml version=\"1.0\" encoding=\"UTF-8\"?><HWPML Version=\"2.8\" SubVersion=\"8.0.0.0\" Style2=\"embed\"><HEAD SecCnt=\"\(d.sections.count)\"><DOCSUMMARY><TITLE>\(XMLEscape.text(d.title ?? ""))</TITLE></DOCSUMMARY><MAPPINGTABLE><BINDATALIST Count=\"\(tables.images.count)\">\(bins)</BINDATALIST><FACENAMELIST>\(fonts)</FACENAMELIST><BORDERFILLLIST Count=\"1\"><BORDERFILL Id=\"1\"/></BORDERFILLLIST><CHARSHAPELIST Count=\"\(tables.charShapes.count)\">\(chars)</CHARSHAPELIST><TABDEFLIST Count=\"1\"><TABDEF Id=\"0\"/></TABDEFLIST><PARASHAPELIST Count=\"\(tables.paraShapes.count)\">\(paras)</PARASHAPELIST><STYLELIST Count=\"1\"><STYLE Id=\"0\" Type=\"Para\" Name=\"바탕글\" EngName=\"Normal\" ParaShape=\"0\" CharShape=\"0\" NextStyle=\"0\"/></STYLELIST></MAPPINGTABLE></HEAD><BODY>\(sections)</BODY><TAIL><BINDATASTORAGE>\(storage)</BINDATASTORAGE></TAIL></HWPML>"
        _ = try AgentXML.parse(Data(xml.utf8))
        return Data(xml.utf8)
    }
}
