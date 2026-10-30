import Foundation
import CoreFoundation

/// Agent-facing spreadsheet operations share the GUI model and calculation engine.
/// All mutations happen before the caller atomically publishes a new file.
enum AgentSheets {
    static let maxCells=100_000
    static let operations=["set_cell","set_range","fill_formula","style_range","clear_range","add_sheet","delete_sheet","merge","unmerge","freeze","set_column_width","set_row_height","define_name"]
    static let warning="Spreadsheet model editing preserves supported cells, styles, merges, names and basic charts. Unsupported Excel objects, pivot tables, macros and connections can be omitted; use package patch to retain unrelated XML parts. Calculation uses HanX's engine, not Microsoft Excel."
    static func keys(_ value:[String:Any],_ allowed:Set<String>)throws {
        for k in value.keys where !allowed.contains(k) { throw AgentError("invalid_argument","Unknown spreadsheet property: \(k)") }
    }
    static func ref(_ value:Any?)throws->CellRef {
        let s=try AgentIO.string(value,"A1 cell address").uppercased()
        guard s.range(of:"^\\$?[A-Z]{1,3}\\$?[1-9][0-9]{0,6}$",options:.regularExpression) != nil,let r=CellRef(a1:s),r.row<1_048_576,r.col<16_384 else { throw AgentError("invalid_argument","Invalid Excel cell address: \(s.prefix(80))") }
        return r
    }
    static func range(_ value:Any?)throws->CellRange {
        let s=try AgentIO.string(value,"range"),parts=s.components(separatedBy:":")
        guard parts.count<=2 else { throw AgentError("invalid_argument","Expected A1 or A1:B10 range") }
        let a=try ref(parts[0]),b=try ref(parts.last!)
        let r=CellRange(a,b)
        guard (r.end.row-r.start.row+1)*(r.end.col-r.start.col+1)<=maxCells else { throw AgentError("invalid_argument","Range exceeds 100000 cells; request a smaller range") }
        return r
    }
    static func name(_ value:Any?)throws->String {
        let n=try AgentIO.string(value,"sheet name")
        guard !n.isEmpty,n.utf16.count<=31,n.rangeOfCharacter(from:CharacterSet(charactersIn:"[]:*?/\\")) == nil,!n.hasPrefix("'"),!n.hasSuffix("'"),!n.unicodeScalars.contains(where:{$0.value<32}) else { throw AgentError("invalid_argument","Invalid Excel sheet name") }
        return n
    }
    static func sheet(_ book:Workbook,_ selector:Any?)throws->Worksheet {
        if let n=selector as? String { guard let s=book.sheet(named:n) else { throw AgentError("invalid_index","Unknown worksheet: \(n)") }; return s }
        let i=try AgentIO.index(selector,"sheet",default:0)
        guard book.sheets.indices.contains(i) else { throw AgentError("invalid_index","Worksheet index out of range") }; return book.sheets[i]
    }
    static func input(_ value:Any,explicitValue:Bool=false)throws->String {
        if value is NSNull { return "" }
        if let s=value as? String {
            guard !s.contains("\0"),s.utf16.count<=32767 else { throw AgentError("invalid_argument","Cell text exceeds 32767 UTF-16 units or contains NUL") }
            return (!explicitValue && s.hasPrefix("=")) ? s : "'"+s
        }
        if let n=value as? NSNumber {
            if CFGetTypeID(n)==CFBooleanGetTypeID() { return n.boolValue ? "TRUE" : "FALSE" }
            guard n.doubleValue.isFinite else { throw AgentError("invalid_argument","Cell number must be finite") }; return n.stringValue
        }
        throw AgentError("invalid_argument","Cell value must be text, a number, boolean or null")
    }
    static func cell(_ value:Any,base:SheetCell=SheetCell())throws->SheetCell {
        var c=base
        if let d=value as? [String:Any] {
            try keys(d,["input","value","style"])
            guard !(d["input"] != nil && d["value"] != nil) else { throw AgentError("invalid_argument","Choose input or value, not both") }
            if let raw=d["input"] {
                c.input=try AgentIO.string(raw,"input")
                guard c.input.utf16.count<=32767 else { throw AgentError("invalid_argument","Cell input exceeds 32767 UTF-16 units") }
            } else if let v=d["value"] { c.input=try input(v,explicitValue:true) }
            if let s=d["style"] { c.style=try style(AgentIO.map(s,"cell style"),base:c.style) }
        } else { c.input=try input(value) }
        return c
    }
    static func style(_ d:[String:Any],base:CellStyle=CellStyle())throws->CellStyle {
        try keys(d,["bold","italic","underline","fontName","fontSize","color","fill","align","wrap","numberFormat","border"])
        var s=base
        if let v=d["bold"] { s.bold=try AgentIO.bool(v,"bold") }; if let v=d["italic"] { s.italic=try AgentIO.bool(v,"italic") }
        if let v=d["underline"] { s.underline=try AgentIO.bool(v,"underline") }; if let v=d["wrap"] { s.wrap=try AgentIO.bool(v,"wrap") }
        if let v=d["border"] { s.border=try AgentIO.bool(v,"border") }
        if let v=d["fontName"] { s.fontName=try AgentIO.string(v,"fontName"); try AgentValidation.string(s.fontName!,"fontName") }
        if let v=d["fontSize"] { let n=try AgentIO.number(v,"fontSize"); guard n>0,n<=409 else { throw AgentError("invalid_argument","fontSize must be >0 and <=409") }; s.fontSize=n }
        if let v=d["color"] { s.color=try AgentDocuments.color(v,"color") }; if let v=d["fill"] { s.fill=try AgentDocuments.color(v,"fill") }
        if let v=d["align"] { guard let a=HAlign(rawValue:try AgentIO.string(v,"align")) else { throw AgentError("invalid_argument","align must be general, left, center or right") }; s.align=a }
        if let v=d["numberFormat"] { s.numberFormat=try AgentIO.string(v,"numberFormat"); try AgentValidation.string(s.numberFormat!,"numberFormat") }
        return s
    }
    static func styleJSON(_ s:CellStyle)->[String:Any] {
        var d:[String:Any]=["bold":s.bold,"italic":s.italic,"underline":s.underline,"align":s.align.rawValue,"wrap":s.wrap,"border":s.border]
        if let n=s.fontName { d["fontName"]=n }; if let n=s.fontSize { d["fontSize"]=n }; if let n=s.numberFormat { d["numberFormat"]=n }
        if let c=s.color { d["color"]=c.hex }; if let c=s.fill { d["fill"]=c.hex }; return d
    }
    static func create(_ spec:[String:Any])throws->Workbook {
        let model=try spec["model"].map { try AgentIO.map($0,"spreadsheet model") } ?? spec
        try keys(model,["kind","sheets","definedNames","model"])
        guard let sheets=model["sheets"] as? [Any],!sheets.isEmpty,sheets.count<=256 else { throw AgentError("invalid_argument","sheets must contain 1...256 worksheets") }
        let b=Workbook(); b.sheets=[]
        for value in sheets {
            let d=try AgentIO.map(value,"worksheet"); try keys(d,["name","rows","cells","columnWidths","rowHeights","merges","frozenRows","frozenCols","legacyFormulas","charts"])
            let n=try name(d["name"] ?? "Sheet\(b.sheets.count+1)")
            guard b.sheet(named:n)==nil else { throw AgentError("invalid_argument","Duplicate worksheet name: \(n)") }
            let ws=Worksheet(name:n); b.sheets.append(ws)
            if let rows=d["rows"] {
                try setRange(ws,start:CellRef(row:0,col:0),values:rows)
            }
            if let cells=d["cells"] {
                for (a,v) in try AgentIO.map(cells,"cells") { let r=try ref(a); ws.cells[r]=try cell(v,base:ws.cells[r] ?? SheetCell()) }
            }
            for (a,v) in try AgentIO.map(d["columnWidths"] ?? [:],"columnWidths") { let r=try ref(a+"1"); let w=try AgentIO.number(v,"column width"); try AgentValidation.dimension(w,"column width"); ws.columnWidths[r.col]=w }
            for (a,v) in try AgentIO.map(d["rowHeights"] ?? [:],"rowHeights") { let r=try ref("A"+a); let h=try AgentIO.number(v,"row height"); try AgentValidation.dimension(h,"row height"); ws.rowHeights[r.row]=h }
            if let merges=d["merges"] { guard let a=merges as? [String] else { throw AgentError("invalid_argument","merges must be an array of A1 ranges") }; for r in a { try merge(ws,range:range(r)) } }
            ws.frozenRows=try AgentIO.index(d["frozenRows"],"frozenRows",default:0); ws.frozenCols=try AgentIO.index(d["frozenCols"],"frozenCols",default:0)
            if let legacy=d["legacyFormulas"] { guard let a=legacy as? [String] else { throw AgentError("invalid_argument","legacyFormulas must be an array") }; ws.legacyFormulas=Set(try a.map { try ref($0) }) }
            if let charts=d["charts"] {
                guard let a=charts as? [[String:Any]] else { throw AgentError("invalid_argument","charts must be an array") }
                for c in a {
                    try keys(c,["kind","title","range","x","y","width","height"])
                    guard let kind=ChartKind(rawValue:try AgentIO.string(c["kind"],"chart kind")) else { throw AgentError("invalid_argument","Unknown chart kind") }
                    let w=try AgentIO.number(c["width"],"chart width",default:420),h=try AgentIO.number(c["height"],"chart height",default:260)
                    try AgentValidation.dimension(w,"chart width"); try AgentValidation.dimension(h,"chart height")
                    let x=try AgentIO.number(c["x"],"chart x",default:0),y=try AgentIO.number(c["y"],"chart y",default:0)
                    guard x>=0,y>=0,x<=100000,y<=100000 else { throw AgentError("invalid_argument","Chart position exceeds supported bounds") }
                    ws.charts.append(SheetChart(kind:kind,title:try AgentIO.string(c["title"] ?? "","chart title"),data:try range(c["range"]),x:x,y:y,w:w,h:h))
                }
            }
        }
        for (n,f) in try AgentIO.map(model["definedNames"] ?? [:],"definedNames") { try define(b,name:n,formula:AgentIO.string(f,"defined name formula")) }
        try validate(b); return b
    }
    static func define(_ b:Workbook,name:String,formula:String)throws {
        guard name.range(of:"^[\\p{L}_\\\\][\\p{L}\\p{N}_.\\\\]{0,254}$",options:.regularExpression) != nil,CellRef(a1:name)==nil,!formula.isEmpty,formula.count<=8192 else { throw AgentError("invalid_argument","Invalid defined name or formula") }
        b.definedNames[name.uppercased()]=formula.hasPrefix("=") ? String(formula.dropFirst()) : formula
    }
    static func setRange(_ ws:Worksheet,start:CellRef,values:Any)throws {
        guard let rows=values as? [[Any]],!rows.isEmpty,rows.count<=maxCells else { throw AgentError("invalid_argument","values must be a nonempty two-dimensional array") }
        let width=rows.map(\.count).max() ?? 0
        guard width>0,rows.count*width<=maxCells,start.row+rows.count<=1_048_576,start.col+width<=16_384 else { throw AgentError("invalid_argument","values exceed worksheet bounds or 100000 cells") }
        for (ri,row) in rows.enumerated() { for (ci,v) in row.enumerated() { let r=CellRef(row:start.row+ri,col:start.col+ci); ws.cells[r]=try cell(v,base:ws.cells[r] ?? SheetCell())
            if let data=v as? [String:Any],data["input"] == nil,data["value"] == nil {} else { ws.legacyFormulas.remove(r) } } }
    }
    static func merge(_ ws:Worksheet,range r:CellRange)throws {
        guard !ws.merges.contains(where:{ m in m.start.row<=r.end.row && m.end.row>=r.start.row && m.start.col<=r.end.col && m.end.col>=r.start.col }) else { throw AgentError("invalid_argument","Merge overlaps an existing merged range") }
        ws.merges.append(r)
    }
    static func edit(_ b:Workbook,_ ops:[Any])throws {
        let fields:[String:Set<String>]=[
            "set_cell":["cell","input","value","style"],"set_range":["start","values"],"fill_formula":["range","formula"],"style_range":["range","style"],"clear_range":["range"],"add_sheet":["name"],"delete_sheet":[],"merge":["range"],"unmerge":["range"],"freeze":["rows","columns"],"set_column_width":["column","width"],"set_row_height":["row","height"],"define_name":["name","formula"]]
        for value in ops {
            let d=try AgentIO.map(value,"operation"),op=try AgentIO.string(d["op"],"op")
            guard let f=fields[op] else { throw AgentError("invalid_operation","Unknown spreadsheet operation: \(op)") }; try keys(d,f.union(["op","sheet"]))
            if op == "add_sheet" { let n=try name(d["name"]); guard b.sheet(named:n)==nil else { throw AgentError("invalid_argument","Duplicate worksheet name") }; b.sheets.append(Worksheet(name:n)); continue }
            if op == "define_name" { try define(b,name:AgentIO.string(d["name"],"name"),formula:AgentIO.string(d["formula"],"formula")); continue }
            let ws=try sheet(b,d["sheet"])
            switch op {
            case "delete_sheet": guard b.sheets.count>1 else { throw AgentError("invalid_operation","Cannot delete the last worksheet") }; b.sheets.removeAll {$0===ws}
            case "set_cell":
                let r=try ref(d["cell"]); var data=d; for k in ["op","sheet","cell"] { data.removeValue(forKey:k) }
                guard data["input"] != nil || data["value"] != nil || data["style"] != nil else { throw AgentError("invalid_argument","set_cell needs input, value or style") }
                ws.cells[r]=try cell(data,base:ws.cells[r] ?? SheetCell())
                if data["input"] != nil || data["value"] != nil { ws.legacyFormulas.remove(r) }
            case "set_range":try setRange(ws,start:ref(d["start"]),values:d["values"] as Any)
            case "fill_formula":
                let r=try range(d["range"]),formula=try AgentIO.string(d["formula"],"formula")
                guard formula.hasPrefix("="),formula.utf16.count<=8192 else { throw AgentError("invalid_argument","formula must start with = and fit 8192 UTF-16 units") }
                for c in r.cells { let text="="+XLSXReader.translate(String(formula.dropFirst()),rows:c.row-r.start.row,cols:c.col-r.start.col); ws.set(c,input:text) }
            case "style_range": let r=try range(d["range"]),s=try AgentIO.map(d["style"],"style"); for c in r.cells { var cell=ws.cells[c] ?? SheetCell(); cell.style=try style(s,base:cell.style); ws.cells[c]=cell }
            case "clear_range":for c in try range(d["range"]).cells { ws.set(c,input:""); ws.cachedValues[c]=nil }
            case "merge":try merge(ws,range:range(d["range"]))
            case "unmerge":let r=try range(d["range"]); ws.merges.removeAll {$0==r}
            case "freeze":ws.frozenRows=try AgentIO.index(d["rows"],"rows",default:0); ws.frozenCols=try AgentIO.index(d["columns"],"columns",default:0)
            case "set_column_width":let c=try AgentIO.string(d["column"],"column"),r=try ref(c+"1"),w=try AgentIO.number(d["width"],"width"); try AgentValidation.dimension(w,"column width"); ws.columnWidths[r.col]=w
            case "set_row_height":let r=try AgentIO.index(d["row"],"row"),h=try AgentIO.number(d["height"],"height"); guard r<1_048_576 else { throw AgentError("invalid_argument","Row exceeds worksheet bounds") }; try AgentValidation.dimension(h,"row height"); ws.rowHeights[r]=h
            default:break
            }
        }
        try validate(b)
    }
    static func validate(_ b:Workbook)throws {
        guard !b.sheets.isEmpty,b.sheets.count<=256,b.sheets.reduce(0,{$0+$1.cells.count})<=maxCells else { throw AgentError("invalid_argument","Workbook exceeds 256 sheets or 100000 stored cells") }
        var names=Set<String>()
        for ws in b.sheets {
            let n=try name(ws.name).uppercased(); guard names.insert(n).inserted else { throw AgentError("invalid_argument","Duplicate worksheet name") }
            guard ws.frozenRows<1_048_576,ws.frozenCols<16_384 else { throw AgentError("invalid_argument","Frozen pane exceeds worksheet bounds") }
            for (r,c) in ws.cells { _=try ref(r.a1); guard c.input.utf16.count<=32767 else { throw AgentError("invalid_argument","Cell input exceeds Excel's text limit") } }
        }
    }
    static func typed(_ value:SheetValue)->[String:Any] {
        switch value {
        case .empty:return ["type":"empty","value":NSNull()]
        case .number(let n):return n.isFinite ? ["type":"number","value":n] : ["type":"error","value":"#NUM!"]
        case .bool(let b):return ["type":"boolean","value":b]
        case .string(let s):return ["type":"string","value":s]
        case .error(let s):return ["type":"error","value":s]
        case .array(let m):return ["type":"array","value":m.grid.map {$0.map { typed($0)["value"]! }}]
        case .lambda:return ["type":"error","value":"#CALC!"]
        }
    }
    static func model(_ b:Workbook)->[String:Any] {
        ["sheets":b.sheets.map { ws -> [String:Any] in
            let cells=Dictionary(uniqueKeysWithValues:ws.cells.map { ($0.key.a1,["input":$0.value.input,"style":styleJSON($0.value.style)] as [String:Any]) })
            return ["name":ws.name,"cells":cells,"columnWidths":Dictionary(uniqueKeysWithValues:ws.columnWidths.map {(CellRef.columnName($0.key),$0.value)}),"rowHeights":Dictionary(uniqueKeysWithValues:ws.rowHeights.map {(String($0.key+1),$0.value)}),"merges":ws.merges.map(\.a1),"frozenRows":ws.frozenRows,"frozenCols":ws.frozenCols,"legacyFormulas":ws.legacyFormulas.sorted().map(\.a1),"charts":ws.charts.map { ["kind":$0.kind.rawValue,"title":$0.title,"range":$0.data.a1,"x":$0.x,"y":$0.y,"width":$0.w,"height":$0.h] as [String:Any] }]
        },"definedNames":b.definedNames]
    }
    static func summary(_ b:Workbook)->[[String:Any]] {
        b.sheets.enumerated().map { i,s in ["index":i,"name":s.name,"usedRange":s.usedRange?.a1 as Any? ?? NSNull(),"cells":s.cells.count,"formulas":s.cells.values.filter(\.isFormula).count] }
    }
    static func text(_ b:Workbook)->String {
        let e=FormulaEngine(book:b,allowExternalIO:false)
        return b.sheets.map { ws in "[\(ws.name)]\n"+ws.cells.keys.sorted().map { "\($0.a1)\t\(e.display(ws,$0))" }.joined(separator:"\n") }.joined(separator:"\n")
    }
    static func read(_ b:Workbook,selector:Any?,requestedRange:Any?)throws->[String:Any] {
        let ws=try sheet(b,selector),e=FormulaEngine(book:b,allowExternalIO:false)
        let r:CellRange?=try requestedRange.map { try range($0) } ?? effectiveRange(ws,engine:e).map { try range($0.a1) }
        let cells=(r?.cells ?? []).map { ref -> [String:Any] in
            var d=typed(e.value(ws,ref)); d["address"]=ref.a1; d["input"]=ws.cells[ref]?.input ?? ""; d["display"]=e.display(ws,ref); d["style"]=styleJSON(ws.cells[ref]?.style ?? CellStyle()); return d
        }
        return ["kind":"spreadsheet","sheet":ws.name,"range":r?.a1 as Any? ?? NSNull(),"cells":cells,"sheets":summary(b),"warnings":[warning]]
    }
    static func errors(_ b:Workbook)->[[String:Any]] {
        let e=FormulaEngine(book:b,allowExternalIO:false)
        return b.sheets.flatMap { ws in ws.cells.keys.sorted().compactMap { ref -> [String:Any]? in
            guard ws.cells[ref]?.isFormula == true else { return nil }; let v=e.value(ws,ref)
            return v.isError ? ["sheet":ws.name,"cell":ref.a1,"error":v.text] : nil
        } }
    }
    /// Include successful dynamic spills when choosing a default view/export.
    static func effectiveRange(_ ws:Worksheet,engine:FormulaEngine)throws->CellRange? {
        var used=ws.usedRange
        for ref in ws.cells.keys.sorted() where ws.cells[ref]?.isFormula == true && !ws.legacyFormulas.contains(ref) {
            guard let m=engine.spillArray(ws,ref) else { continue }
            guard m.rows>0,m.cols>0,ref.row+m.rows<=1_048_576,ref.col+m.cols<=16_384 else { throw AgentError("invalid_argument","Spill exceeds Excel worksheet bounds") }
            let end=CellRef(row:ref.row+m.rows-1,col:ref.col+m.cols-1)
            if let old=used { used=CellRange(CellRef(row:min(old.start.row,ref.row),col:min(old.start.col,ref.col)),CellRef(row:max(old.end.row,end.row),col:max(old.end.col,end.col))) }
            else { used=CellRange(ref,end) }
        }
        return used
    }
    /// Dense exports contain computed values, including spilled cells. Do not
    /// mutate the source workbook or turn strings beginning with = into code.
    static func exportValues(_ b:Workbook)throws->Workbook {
        let output=Workbook(),e=FormulaEngine(book:b,allowExternalIO:false); output.sheets=[]
        for ws in b.sheets {
            let copy=Worksheet(name:ws.name); copy.columnWidths=ws.columnWidths; copy.rowHeights=ws.rowHeights; copy.merges=ws.merges; copy.frozenRows=ws.frozenRows; copy.frozenCols=ws.frozenCols
            if let r=try effectiveRange(ws,engine:e) {
                guard (r.end.row+1)*(r.end.col+1)<=maxCells else { throw AgentError("invalid_argument","Dense export exceeds 100000 cells") }
                for ref in r.cells {
                    var cell=ws.cells[ref] ?? SheetCell()
                    switch e.value(ws,ref) {
                    case .empty:cell.input=""
                    case .string(let s):cell.input="'"+s
                    case .bool(let b):cell.input=b ? "TRUE" : "FALSE"
                    case .number(let n):cell.input=n.isFinite ? String(n) : "#NUM!"
                    default:cell.input=e.value(ws,ref).text
                    }
                    if !cell.input.isEmpty || cell.style != CellStyle() { copy.cells[ref]=cell }
                }
            }
            output.sheets.append(copy)
        }
        return output
    }
    static func data(_ b:Workbook,format:String)throws->Data {
        try validate(b)
        if format == "xlsx" { return XLSXWriter.write(b,allowExternalIO:false) }
        if format == "json" { return try AgentIO.json(["kind":"spreadsheet","model":model(b)],pretty:true) }
        if ["csv","tsv","txt","html","htm"].contains(format) {
            let values=try exportValues(b),e=FormulaEngine(book:values,allowExternalIO:false)
            if ["html","htm"].contains(format) { return Data(SheetHTML.html(values,engine:e).utf8) }
            return DelimitedText.write(values.sheets[0],engine:e,separator:format == "csv" ? "," : "\t")
        }
        throw AgentError("unsupported_format","Spreadsheet output supports XLSX, CSV, TSV, JSON or HTML")
    }
}
