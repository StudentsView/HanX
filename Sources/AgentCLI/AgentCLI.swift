import Foundation

enum AgentCLI {
    static let commands:Set<String>=["--help","-h","help","--version","version","capabilities","schema","read","create","edit","convert","xml","package","spreadsheet","mcp","serve"]
    static let help="""
    HanWord CLI \(AgentIO.version)
    Local document tools for agents. JSON on stdout; errors have nonzero exit codes.

    hanword capabilities
    hanword create --spec document.json --output report.hwp
    hanword read report.hwp [--text | --no-model] [--pretty]
    hanword edit report.docx --ops edits.json --output updated.docx
    hanword convert report.hwp --output report.docx
    hanword xml read data.xml [--xpath '//*[local-name()="item"]']
    hanword xml edit data.xml --ops edits.json --output updated.xml
    hanword package list deck.pptx
    hanword package read deck.pptx --part ppt/slides/slide1.xml [--xpath ...]
    hanword package patch deck.pptx --part ppt/slides/slide1.xml --ops edits.json --output updated.pptx
    hanword spreadsheet read book.xlsx --sheet 매출 --range A1:D10
    hanword spreadsheet eval book.xlsx --sheet 매출 --formula '=SUM(D2:D10)'
    hanword spreadsheet recalculate book.xlsx --output calculated.xlsx
    hanword spreadsheet functions
    hanword mcp

    --spec - and --ops - read JSON from stdin. Output files are never overwritten
    unless --force is explicit. Indices are zero-based; dimensions are in points.
    DOCX/PPTX/HWPX -> .xml uses Flat OPC, preserving the complete package.
    HWP -> .xml and document creation as .hml/.xml use HWPML.
    Use --xml-format hwpml to convert DOCX/HWPX to HWPML instead.
    본 제품은 한컴의 HWP 문서 파일(.hwp) 공개 문서를 참고하여 개발하였습니다.
    Existing diagnostic commands (dump, sheet, slides, eval, formula-suite) remain.
    """
    static func capabilities()->[String:Any] {
        let exe=(Bundle.main.executableURL ?? AgentIO.url(CommandLine.arguments[0])).resolvingSymlinksInPath()
        let guides=[exe.deletingLastPathComponent().appendingPathComponent("README.md"),exe.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("docs/cli/README.md")]
        let guide=guides.first { FileManager.default.fileExists(atPath:$0.path) }
        return [
            "name":"HanWord","version":AgentIO.version,"notices":[LegalNotices.hwp,LegalNotices.independence],
            "guidePath":guide?.path ?? "",
            "formats":["document":["hwp","hwpx","docx","hml","txt","md","json"],"presentation":["pptx","json"],"spreadsheet":["xlsx","csv","tsv","json"],"xml":["generic XML with XPath","HWPML 2.x","Flat OPC","DOCX/PPTX/HWPX/XLSX package XML"]],
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
            "limits":[AgentSheets.warning,"Model-based HWP/DOCX/PPTX conversion supports the existing HanWord model; unsupported controls can be omitted. Read warnings and use package patch to preserve other OOXML parts.","HWPML model conversion supports text, basic styles, tables, page setup, headers/footers and embedded images. Other controls remain editable through xml edit.","XML DTD/external entity expansion and macros/scripts are not executed.","Generic XML has no automatic semantic conversion to office documents; use HWPML, Flat OPC, or a document specification.","ChatGPT web needs a local execution bridge or connector; installing this CLI alone does not grant cloud chats access to the Mac."]
        ]
    }
    static func parse(_ argv:[String])throws->(String,[String:Any]) {
        guard let first=argv.first else { throw AgentError("invalid_argument","Missing command. Run hanword --help.") }
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
        func input()throws->String { try AgentIO.string(args["input"],"input") }
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
            let warnings=["Model editing preserves supported HanWord properties. Use package patch for part-preserving OOXML edits."]
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
            return try save(file.data(for:ext),kind:file.kind,warnings:(try file.result()["warnings"]) as? [String] ?? [])
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
        if argv.isEmpty || ["--help","-h","help"].contains(argv[0]) { print(help); return 0 }
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
