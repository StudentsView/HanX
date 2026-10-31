import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum AgentCLI {
    static let commands:Set<String>=["--convert","--help","-h","help","--version","version","capabilities","schema","read","create","edit","convert","xml","package","spreadsheet","mcp","serve"]
    static var help: String {
        let rows: [(String, String)] = [
            ("시작 화면", "hanx"),
            ("파일 변환", "hanx --convert  (드롭 → ↑ ↓ 선택 → Enter)"),
            ("도움말", "hanx --help"),
            ("버전", "hanx --version"),
            ("지원 기능", "hanx capabilities --pretty"),
            ("변환", "hanx convert 원본.hwp --output 결과.docx"),
            ("본문 읽기", "hanx read 문서.docx --text"),
            ("문서 생성", "hanx create --spec 문서.json --output 결과.hwp"),
            ("문서 수정", "hanx edit 원본.docx --ops 수정.json --output 결과.docx"),
            ("셀 조회", "hanx spreadsheet read 매출.xlsx --sheet 매출 --range A1:D10"),
            ("수식 계산", "hanx spreadsheet eval 매출.xlsx --formula '=SUM(D2:D10)'"),
            ("재계산", "hanx spreadsheet recalculate 원본.xlsx --output 결과.xlsx"),
            ("함수 목록", "hanx spreadsheet functions"),
            ("XML 조회", "hanx xml read 원본.xml"),
            ("XML 수정", "hanx xml edit 원본.xml --ops 수정.json --output 결과.xml"),
            ("내부 파일", "hanx package list 발표.pptx"),
            ("내부 조회", "hanx package read 발표.pptx --part ppt/slides/slide1.xml"),
            ("내부 수정", "hanx package patch 원본.docx --part word/document.xml"),
            ("수정 옵션", "  --ops 수정.json --output 결과.docx"),
            ("MCP 연결", "hanx mcp")
        ]
        let options: [(String, String)] = [
            ("입력 경로", "원본.hwp 또는 /Users/me/Documents/원본.hwp"),
            ("공백 경로", "hanx convert \"원본 문서.hwp\" --output \"결과 문서.docx\""),
            ("저장 경로", "--output 결과.docx  (파일명과 확장자 포함)"),
            ("덮어쓰기", "--force"),
            ("JSON 정렬", "--pretty"),
            ("표준 입력", "--spec - / --ops -"),
            ("HWPML 출력", "--xml-format hwpml"),
            ("PDF 입력", "텍스트 추출 / 배치 복원 / OCR 미지원"),
            ("문서 형식", "HWP / DOCX / HWPX / HWPML / PDF / TXT / MD / JSON"),
            ("엑셀 형식", "XLSX / CSV / TSV / PDF / JSON"),
            ("슬라이드", "PPTX / PDF / JSON"),
            ("XML 형식", "일반 XML / HWPML / Flat OPC"),
            ("변환 범위", "같은 문서 종류의 지원 형식 간 변환"),
            ("상대 경로", "현재 터미널 폴더 기준"),
            ("출력", "JSON / 본문 읽기: --text / 오류: 종료 코드 != 0")
        ]
        func width(_ text: String) -> Int {
            text.unicodeScalars.reduce(0) { total, scalar in
                let v = scalar.value
                let wide = (0x1100...0x115f).contains(v) || (0x2e80...0xa4cf).contains(v) || (0xac00...0xd7a3).contains(v) || (0xf900...0xfaff).contains(v) || (0xff01...0xff60).contains(v)
                return total + (wide ? 2 : 1)
            }
        }
        let left = 12
        let right = (rows + options).map { width($0.1) }.max() ?? 60
        func pad(_ text: String, _ count: Int) -> String {
            text + String(repeating: " ", count: max(0, count - width(text)))
        }
        func rule(_ start: String, _ middle: String, _ end: String) -> String {
            start + String(repeating: "─", count: left + 2) + middle + String(repeating: "─", count: right + 2) + end
        }
        func row(_ label: String, _ value: String) -> String {
            "│ " + pad(label, left) + " │ " + pad(value, right) + " │"
        }
        var lines = ["HanX CLI \(AgentIO.version)", "", rule("┌", "┬", "┐"), row("기능", "실행 예시"), rule("├", "┼", "┤")]
        lines += rows.map { row($0.0, $0.1) }
        lines += [rule("├", "┼", "┤"), row("옵션 / 형식", "값 / 사용법"), rule("├", "┼", "┤")]
        lines += options.map { row($0.0, $0.1) }
        lines += [rule("└", "┴", "┘")]
        return lines.joined(separator: "\n")
    }
    static func pdfCapabilities() -> [String:Any] {
#if HANX_PORTABLE || !canImport(AppKit)
        return ["input":"Selectable text using local Poppler; no layout reconstruction or OCR", "output":"Local LibreOffice renderer; pagination and fonts can differ from macOS", "inputAvailable":PortableTool.find("pdfinfo") != nil && PortableTool.find("pdftotext") != nil, "outputAvailable":PortableTool.find("soffice") != nil, "dependencies":["input":["pdfinfo","pdftotext"], "output":["soffice"]]]
#else
        return ["input":"Selectable text as document; no layout reconstruction or OCR", "output":"Documents, spreadsheets, presentations using HanX renderers", "inputAvailable":true, "outputAvailable":true]
#endif
    }
    static func capabilities()->[String:Any] {
        let exe=(Bundle.main.executableURL ?? AgentIO.url(CommandLine.arguments[0])).resolvingSymlinksInPath()
        let guides=[exe.deletingLastPathComponent().appendingPathComponent("README.md"),exe.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("docs/cli/README.md")]
        let guide=guides.first { FileManager.default.fileExists(atPath:$0.path) }
        return [
            "name":"HanX","version":AgentIO.version,"notices":[LegalNotices.independence],
            "guidePath":guide?.path ?? "",
            "formats":["document":["pdf","hwp","hwpx","docx","hml","txt","md","json"],"presentation":["pptx","json","pdf"],"spreadsheet":["xlsx","csv","tsv","json","pdf"],"xml":["generic XML with XPath","HWPML 2.x","Flat OPC","DOCX/PPTX/HWPX/XLSX package XML"]],
            "pdf":pdfCapabilities(),
            "spreadsheetFunctions":FunctionLibrary.table.keys.sorted(),
            "operations":["spreadsheet":AgentSheets.operations,"document":AgentDocuments.documentOps,"presentation":AgentDocuments.slideOps,"xml":["set_text","set_attribute","append_xml","replace_xml","delete"]],
            "commands":["read","create","edit","convert","xml read","xml edit","package list","package read","package patch","spreadsheet read","spreadsheet eval","spreadsheet recalculate","spreadsheet functions","mcp"],
            "conventions":["indices":"zero-based","length":"points (1/72 inch)","duration":"seconds","color":"six-digit RGB hex","save":"explicit output, --force to overwrite","stdout":"JSON envelope, except --help and read --text"],
            "examples":[
                "document":["kind":"document","blocks":[["type":"paragraph","text":"보고서","style":["bold":true,"size":20]],["type":"table","rows":[["항목","값"],["합계","100"]]]]],
                "presentation":["kind":"presentation","slides":[["title":"제목","body":["내용"],"notes":"발표 노트","transition":["kind":"cut"]]]],
                "documentEdits":[["op":"replace_text","find":"원문","replace":"새 내용"],["op":"set_cell","section":0,"block":1,"row":1,"column":1,"text":"200"]],
                "slideEdits":[["op":"duplicate_slide","slide":0],["op":"set_transition","slide":1,"kind":"push","duration":0.8]],
                "xmlEdits":[["op":"set_text","xpath":"//*[local-name()='title']","text":"새 제목"]]
            ],
            "limits":[AgentSheets.warning,"Model-based HWP/DOCX/PPTX conversion supports the existing HanX model; unsupported controls can be omitted. Read warnings and use package patch to preserve other OOXML parts.","HWPML model conversion supports text, basic styles, tables, page setup, headers/footers and embedded images. Other controls remain editable through xml edit.","XML DTD/external entity expansion and macros/scripts are not executed.","Generic XML has no automatic semantic conversion to office documents; use HWPML, Flat OPC, or a document specification.","ChatGPT web needs a local execution bridge or connector; installing this CLI alone does not grant cloud chats access to the Mac."]
        ]
    }
    static func parse(_ argv:[String])throws->(String,[String:Any]) {
        guard let first=argv.first else { throw AgentError("invalid_argument","Missing command. Run hanx --help.") }
        var args=Array(argv.dropFirst()),command=first,options:[String:Any]=[:],positionals:[String]=[]
        if ["xml","package","spreadsheet"].contains(first) {
            guard !args.isEmpty else { throw AgentError("invalid_argument","Missing \(first) subcommand") }
            command=(first == "spreadsheet" ? "sheet" : first)+"_"+args.removeFirst()
        }
        let valueFlags=["--spec":"specFile","--spec-file":"specFile","--ops":"opsFile","--ops-file":"opsFile","--output":"output","-o":"output","--part":"part","--xpath":"xpath","--xml-format":"xmlFormat","--sheet":"sheet","--range":"range","--formula":"formula","--cell":"cell"]
        let boolFlags=["--force":"force","--pretty":"pretty","--text":"textOutput","--no-model":"noModel","--json":"json"]
        var i=0
        while i<args.count {
            let a=args[i]
            if a == "--" { positionals += Array(args.dropFirst(i+1)); break }
            if let key=valueFlags[a] {
                guard i+1<args.count,options[key] == nil else { throw AgentError("invalid_argument","Missing or duplicate \(a)") }
                options[key]=args[i+1]; i += 2; continue
            }
            if let key=boolFlags[a] { options[key]=true; i += 1; continue }
            if a.hasPrefix("-"),a != "-" { throw AgentError("invalid_argument","Unknown flag: \(a)") }
            positionals.append(a); i += 1
        }
        if command == "convert",positionals.count == 2,options["output"] == nil { options["output"]=positionals.removeLast() }
        guard positionals.count<=1 else { throw AgentError("invalid_argument","Too many input paths") }
        if let input=positionals.first { options["input"]=input }
        let common:Set<String>=["pretty","json"]
        let allowed:[String:Set<String>]=[
            "capabilities":[],"schema":[],"version":[],
            "sheet_functions":[],"sheet_read":["input","sheet","range"],"sheet_eval":["input","sheet","formula","cell"],"sheet_recalculate":["input","output","force"],
            "read":["input","textOutput","noModel"],
            "create":["specFile","output","force"],
            "edit":["input","opsFile","output","force"],
            "convert":["input","output","force","xmlFormat"],
            "xml_read":["input","xpath"],"xml_edit":["input","opsFile","output","force"],
            "package_list":["input"],"package_read":["input","part","xpath"],"package_patch":["input","part","opsFile","output","force"]
        ]
        guard let keys=allowed[command] else { throw AgentError("invalid_argument","Unknown command: \(command)") }
        for key in options.keys where !keys.union(common).contains(key) { throw AgentError("invalid_argument","Option \(key) does not apply to \(command)") }
        if let path=options["specFile"] as? String {
            options["spec"]=try AgentIO.map(AgentIO.readJSON(path),"spec")
            options["baseDirectory"]=path == "-" ? FileManager.default.currentDirectoryPath : AgentIO.url(path).deletingLastPathComponent().path
        }
        if let path=options["opsFile"] as? String {
            let value=try AgentIO.readJSON(path)
            options["operations"]=(value as? [String:Any])?["operations"] ?? value
            options["baseDirectory"]=path == "-" ? FileManager.default.currentDirectoryPath : AgentIO.url(path).deletingLastPathComponent().path
        }
        return (command,options)
    }
    static func execute(_ command:String,_ args:[String:Any])throws->[String:Any] {
        if command == "capabilities" || command == "schema" { return capabilities() }
        if command == "version" { return ["version":AgentIO.version] }
        if command == "sheet_functions" { return ["functions":FunctionLibrary.table.keys.sorted(),"blockedExternalIO":["WEBSERVICE","IMPORTCSV","IMPORTTEXT"],"note":"Registered function names include offline/external stubs. No guarantee of complete Excel parity."] }
        let directory=AgentIO.url(args["baseDirectory"] as? String ?? FileManager.default.currentDirectoryPath)
        let force=try AgentIO.bool(args["force"],"force")
        func input()throws->String {
            let path = try AgentIO.string(args["input"],"input")
            return path == "-" ? path : AgentPath.inputURL(path).path
        }
        func operations()throws->[Any] {
            guard let ops=args["operations"] as? [Any],!ops.isEmpty else { throw AgentError("invalid_argument","operations must be a nonempty JSON array") }; return ops
        }
        func save(_ data:Data,kind:String,warnings:[String]=[])throws->[String:Any] {
            let output=try AgentIO.string(args["output"],"output")
            try AgentIO.write(data,to:output,force:force)
            return ["path":AgentIO.url(output).path,"kind":kind,"bytes":data.count,"warnings":warnings]
        }
        switch command {
        case "sheet_read","sheet_eval","sheet_recalculate":
            guard case .spreadsheet(let b)=try AgentFile.load(input()) else { throw AgentError("unsupported_format","Expected an XLSX, CSV, TSV or spreadsheet JSON file") }
            if command == "sheet_read" { return try AgentSheets.read(b,selector:args["sheet"],requestedRange:args["range"]) }
            if command == "sheet_eval" {
                let ws=try AgentSheets.sheet(b,args["sheet"]),e=FormulaEngine(book:b,allowExternalIO:false),formula=try AgentIO.string(args["formula"],"formula")
                guard formula.hasPrefix("="),formula.utf16.count<=8192 else { throw AgentError("invalid_argument","formula must start with = and fit 8192 UTF-16 units") }
                let at=try args["cell"].map { try AgentSheets.ref($0) }
                var result=AgentSheets.typed(e.evaluateFormula(String(formula.dropFirst()),sheet:ws,cell:at)); result["sheet"]=ws.name; result["formula"]=formula; return result
            }
            let output=try AgentIO.string(args["output"],"output"),ext=AgentIO.url(output).pathExtension.lowercased()
            var result=try save(AgentSheets.data(b,format:ext),kind:"spreadsheet",warnings:[AgentSheets.warning]); result["formulaErrors"]=AgentSheets.errors(b); return result
        case "read":
            let file=try AgentFile.load(input()); var value=try file.result(); value["path"]=AgentIO.url(try input()).path
            if try AgentIO.bool(args["noModel"],"noModel") { value.removeValue(forKey:"model") }
            return value
        case "create":
            let file=try AgentDocuments.create(AgentIO.map(args["spec"],"spec"),base:directory)
            let ext=AgentIO.url(try AgentIO.string(args["output"],"output")).pathExtension.lowercased()
            if case .spreadsheet(let b)=file { var r=try save(file.data(for:ext),kind:file.kind,warnings:[AgentSheets.warning]); r["formulaErrors"]=AgentSheets.errors(b); return r }
            return try save(file.data(for:ext),kind:file.kind)
        case "edit":
            let file=try AgentFile.load(input())
            let edited=try AgentDocuments.edit(file,operations:operations(),directory:directory)
            let ext=AgentIO.url(try AgentIO.string(args["output"],"output")).pathExtension.lowercased()
            let warnings=["Model editing preserves supported HanX properties. Use package patch for part-preserving OOXML edits."]
            if case .spreadsheet(let b)=edited { var r=try save(edited.data(for:ext),kind:edited.kind,warnings:[AgentSheets.warning]); r["formulaErrors"]=AgentSheets.errors(b); return r }
            return try save(edited.data(for:ext),kind:edited.kind,warnings:warnings)
        case "convert":
            let path=try input(),output=try AgentIO.string(args["output"],"output"),ext=AgentIO.url(output).pathExtension.lowercased()
            let data=try AgentIO.read(path)
            if let format=args["xmlFormat"] as? String,format != "hwpml" { throw AgentError("invalid_argument","xmlFormat must be hwpml") }
            if ext == "xml",ZipReader.isZip(data),args["xmlFormat"] == nil { return try save(AgentXML.flatten(path),kind:"flat-opc") }
            let file=try AgentFile.load(path)
            if case .xml(let xml)=file,xml.rootElement()?.local == "package",["pptx","docx","hwpx","xlsx"].contains(ext) { return try save(AgentXML.unflatten(xml,extension:ext),kind:"package") }
            if AgentIO.url(path).pathExtension.lowercased() == ext { return try save(data,kind:file.kind) }
            var warnings = (try file.result()["warnings"]) as? [String] ?? []
            if ext == "pdf" {
#if HANX_PORTABLE || !canImport(AppKit)
                warnings.append("PDF uses local LibreOffice; font metrics, pagination and supported drawing features can differ from the macOS renderer. Animations are static.")
#else
                warnings.append("PDF는 HanX의 지원 개체를 기준으로 렌더링합니다. 슬라이드 전환과 애니메이션은 정지된 페이지로 저장합니다.")
#endif
            }
            return try save(file.data(for:ext),kind:file.kind,warnings:warnings)
        case "xml_read":return try AgentXML.query(AgentXML.parse(AgentIO.read(input())),xpath:args["xpath"] as? String)
        case "xml_edit":
            let doc=try AgentXML.patch(AgentXML.parse(AgentIO.read(input())),operations:operations())
            return try save(doc.xmlData,kind:"xml")
        case "package_list":return try AgentXML.packageList(input())
        case "package_read":return try AgentXML.packageRead(input(),part:AgentIO.string(args["part"],"part"),xpath:args["xpath"] as? String)
        case "package_patch":
            return try save(AgentXML.packagePatch(input(),part:AgentIO.string(args["part"],"part"),operations:operations()),kind:"package")
        default:throw AgentError("invalid_argument","Unknown command: \(command)")
        }
    }
    static func run(_ argv:[String])->Int32 {
        if argv.isEmpty { print(AgentInteractive.welcome); return 0 }
        if ["--help","-h","help"].contains(argv[0]) || argv.contains("--help") || argv.contains("-h") { print(help); return 0 }
        if argv[0] == "--convert" { return AgentInteractive.run(Array(argv.dropFirst())) }
        if ["mcp","serve"].contains(argv[0]) {
            if argv.count != 1 { print("{\"ok\":false,\"error\":{\"code\":\"invalid_argument\",\"message\":\"mcp takes no arguments\"}}"); return 2 }
            return AgentMCP.serve()
        }
        do {
            var normalized=argv
            if normalized[0] == "--version" { normalized[0]="version" }
            let (command,args)=try parse(normalized),result=try execute(command,args)
            if args["textOutput"] as? Bool == true,let text=result["text"] as? String { print(text) }
            else { let data=try AgentIO.json(["ok":true,"version":AgentIO.version,"data":result],pretty:args["pretty"] as? Bool == true); FileHandle.standardOutput.write(data); print("") }
            return 0
        } catch {
            let e=AgentIO.error(error)
            let data=(try? AgentIO.json(["ok":false,"error":["code":e.code,"message":e.message]])) ?? Data("{\"ok\":false}".utf8)
            FileHandle.standardOutput.write(data); print("")
            return e.status
        }
    }
}
