import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(CoreFoundation)
import CoreFoundation
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif os(Windows)
import WinSDK
import ucrt
#endif

struct AgentError: Error {
    let code:String
    let message:String
    var status:Int32 { code == "output_exists" ? 3 : code == "io_error" ? 1 : 2 }
    init(_ code:String,_ message:String) { self.code=code; self.message=message }
}

enum AgentIO {
    static let version="2.9.1"
    static func isBoolean(_ number: NSNumber) -> Bool {
        #if canImport(CoreFoundation)
        return CFGetTypeID(number) == CFBooleanGetTypeID()
        #else
        // Windows Foundation has no public CoreFoundation module. JSON number
        // tokens use integer/double encodings; Boolean NSNumber uses c or B.
        let type = String(cString: number.objCType)
        return type == "c" || type == "B"
        #endif
    }
    static func object(_ data:Data)->Any? { try? JSONSerialization.jsonObject(with:data,options:[.fragmentsAllowed]) }
    static func json(_ value:Any,pretty:Bool=false)throws->Data {
        try JSONSerialization.data(withJSONObject:value,options:pretty ? [.sortedKeys,.prettyPrinted,.fragmentsAllowed] : [.sortedKeys,.fragmentsAllowed])
    }
    static func encode<T:Encodable>(_ value:T)throws->Any { try JSONSerialization.jsonObject(with:JSONEncoder().encode(value)) }
    static func decode<T:Decodable>(_ type:T.Type,_ value:Any)throws->T { try JSONDecoder().decode(type,from:json(value)) }
    static func validateNumbers(_ value:Any)throws {
        if let n=value as? NSNumber,!isBoolean(n) {
            guard n.doubleValue.isFinite,abs(n.doubleValue)<=10_000_000 else { throw AgentError("invalid_argument","Numeric value exceeds supported bounds (absolute maximum 10000000)") }
        } else if let a=value as? [Any] { for item in a { try validateNumbers(item) } }
        else if let d=value as? [String:Any] { for item in d.values { try validateNumbers(item) } }
    }
    static func map(_ value:Any?,_ label:String="object")throws->[String:Any] {
        guard let value=value as? [String:Any] else { throw AgentError("invalid_argument","Expected \(label) object") }; return value
    }
    static func string(_ value:Any?,_ label:String)throws->String {
        guard let value=value as? String,!value.contains("\0") else { throw AgentError("invalid_argument","Expected \(label) string") }; return value
    }
    static func index(_ value:Any?,_ label:String,default fallback:Int?=nil)throws->Int {
        if value == nil,let fallback { return fallback }
        guard let n=value as? NSNumber,!isBoolean(n),n.doubleValue.isFinite,n.doubleValue.rounded() == n.doubleValue,n.doubleValue>=0,n.doubleValue<=10_000_000 else { throw AgentError("invalid_argument","Invalid zero-based \(label)") }
        return n.intValue
    }
    static func number(_ value:Any?,_ label:String,default fallback:Double?=nil)throws->Double {
        if value == nil,let fallback { return fallback }
        guard let n=value as? NSNumber,!isBoolean(n),n.doubleValue.isFinite,abs(n.doubleValue)<=10_000_000 else { throw AgentError("invalid_argument","Invalid \(label) number") }; return n.doubleValue
    }
    static func bool(_ value:Any?,_ label:String,default fallback:Bool=false)throws->Bool {
        guard let value else { return fallback }
        guard let n=value as? NSNumber,isBoolean(n) else { throw AgentError("invalid_argument","Invalid \(label) boolean") }; return n.boolValue
    }
    static func url(_ path:String)->URL { AgentPath.literalURL(path) }
    static func read(_ path:String)throws->Data {
        if path == "-" { return FileHandle.standardInput.readDataToEndOfFile() }
        do { return try Data(contentsOf:AgentPath.inputURL(path)) } catch { throw AgentError("io_error","Cannot read \(path): \(error.localizedDescription)") }
    }
    static func readJSON(_ path:String)throws->Any {
        guard let value=object(try read(path)) else { throw AgentError("invalid_json","Invalid JSON: \(path)") }; return value
    }
    /// Write fully prepared data to a same-directory temporary file, then
    /// publish atomically. link() gives no-overwrite semantics without a race.
    static func write(_ data:Data,to path:String,force:Bool)throws {
        let dest=url(path),fm=FileManager.default
        guard dest.lastPathComponent != ".",dest.path != "/" else { throw AgentError("invalid_argument","Invalid output path") }
        if !force,fm.fileExists(atPath:dest.path) { throw AgentError("output_exists","Output already exists: \(dest.path). Use --force to replace it.") }
        var isDirectory:ObjCBool=false
        if fm.fileExists(atPath:dest.path,isDirectory:&isDirectory),isDirectory.boolValue { throw AgentError("io_error","Output is a directory: \(dest.path)") }
        try fm.createDirectory(at:dest.deletingLastPathComponent(),withIntermediateDirectories:true)
        let temp=dest.deletingLastPathComponent().appendingPathComponent(".hanx-\(UUID().uuidString).tmp")
        defer { try? fm.removeItem(at:temp) }
        try data.write(to:temp,options:.withoutOverwriting)
        #if os(Windows)
        let flags: DWORD = force ? DWORD(MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH) : DWORD(MOVEFILE_WRITE_THROUGH)
        let moved = temp.path.withCString(encodedAs: UTF16.self) { src in
            dest.path.withCString(encodedAs: UTF16.self) { dst in MoveFileExW(src, dst, flags) }
        }
        if !moved {
            let code = GetLastError()
            throw AgentError(code == ERROR_FILE_EXISTS || code == ERROR_ALREADY_EXISTS ? "output_exists" : "io_error", "Cannot publish \(dest.path): Windows error \(code)")
        }
#else
        let rc = force ? rename(temp.path,dest.path) : link(temp.path,dest.path)
        if rc != 0 {
            let code=errno
            throw AgentError(code == EEXIST ? "output_exists" : "io_error","Cannot publish \(dest.path): \(String(cString:strerror(code)))")
        }
#endif
    }
    static func error(_ error:Error)->AgentError {
        if let error=error as? AgentError { return error }
        if let error=error as? FormatError { return AgentError("invalid_format",error.description) }
        return AgentError("invalid_input",error.localizedDescription)
    }
}

struct AgentDocumentModel:Codable {
    var sections:[Section]
    var images:[String:ImageData]
    var title:String?
    var source:SourceFormat
    var warnings:[String]
    init(_ doc:UDocument) { sections=doc.sections; images=doc.images; title=doc.title; source=doc.source; warnings=doc.warnings }
    func document()->UDocument { let d=UDocument(); d.sections=sections; d.images=images; d.title=title; d.source=source; d.warnings=warnings; return d }
}
struct AgentPresentationModel:Codable {
    var width:Double,height:Double
    var slides:[Slide]
    var images:[String:ImageData]
    init(_ p:Presentation) { width=p.width; height=p.height; slides=p.slides; images=p.images }
    func presentation()->Presentation { let p=Presentation(); p.width=width; p.height=height; p.slides=slides; p.images=images; return p }
}
enum AgentFile {
    case document(UDocument),presentation(Presentation),spreadsheet(Workbook),xml(XMLDocument)
    var kind:String { switch self { case .document:return "document"; case .presentation:return "presentation"; case .spreadsheet:return "spreadsheet"; case .xml:return "xml" } }
    var text:String {
        switch self { case .document(let d):return d.plainText; case .presentation(let p):return p.plainText; case .spreadsheet(let b):return AgentSheets.text(b); case .xml(let x):return x.rootElement()?.stringValue ?? "" }
    }
    func result()throws->[String:Any] {
        var result:[String:Any]=["kind":kind,"text":text]
        switch self {
        case .document(let d): result["model"]=try AgentIO.encode(AgentDocumentModel(d)); result["warnings"]=d.warnings
        case .presentation(let p): result["model"]=try AgentIO.encode(AgentPresentationModel(p)); result["warnings"]=[]
        case .spreadsheet(let b): result["model"]=AgentSheets.model(b); result["sheets"]=AgentSheets.summary(b); result["warnings"]=[AgentSheets.warning]; result["formulaErrors"]=AgentSheets.errors(b)
        case .xml(let x): result["xml"]=x.xmlString; result["root"]=x.rootElement()?.name ?? ""; result["warnings"]=[]
        }
        return result
    }
    static func load(_ path:String)throws->AgentFile {
        let data=try AgentIO.read(path),url=AgentPath.inputURL(path),ext=url.pathExtension.lowercased()
        if PDFReader.isPDF(data) || ext == "pdf" { return .document(try DocumentIO.load(url:url)) }
        if ZipReader.isZip(data) {
            let zip=try ZipReader(data:data)
            if zip.has("xl/workbook.xml") { let b=try XLSXReader.read(zip); try AgentSheets.validate(b); return .spreadsheet(b) }
            if zip.has("ppt/presentation.xml") { return .presentation(try PPTXReader(zip:zip).read()) }
            return .document(try DocumentIO.load(url:url))
        }
        if ["csv","tsv","tab"].contains(ext) { let b=try SheetIO.load(url:url); try AgentSheets.validate(b); return .spreadsheet(b) }
        if CFBReader.isCFB(data) { return .document(try DocumentIO.load(url:url)) }
        if ["xml","hml"].contains(ext) {
            let xml=try AgentXML.parse(data)
            if xml.rootElement()?.local.uppercased() == "HWPML" { return .document(try HWPML.read(xml)) }
            return .xml(xml)
        }
        if ext == "json" {
            let spec=try AgentIO.map(AgentIO.object(data))
            return try AgentDocuments.create(spec,base:url.deletingLastPathComponent())
        }
        if ["txt","md"].contains(ext),let text=String(data:data,encoding:.utf8) { return .document(UDocument.plain(text,char:CharProps())) }
        throw AgentError("unsupported_format","Expected PDF, HWP, HWPX, DOCX, PPTX, XLSX, CSV, TSV, HWPML, XML, JSON or UTF-8 text")
    }
    func data(for ext:String)throws->Data {
        // Native model import and XML readers also pass this boundary before
        // numeric values enter binary format writers.
        try AgentValidation.file(self,format:ext)
        if ext == "pdf" { return try AgentPDF.data(self) }
        switch self {
        case .document(let d):
            switch ext {
            case "docx":return DOCXWriter(d).write()
            case "hwpx":return HWPXWriter(d).write()
            case "hwp":return HWP5Writer(d).write()
            case "xml","hml":return try HWPML.write(d)
            case "txt":return Data(d.plainText.utf8)
            case "md":return Data(MarkdownWriter.write(d).utf8)
            case "html","htm":return Data(HTMLWriter.write(d).utf8)
            case "json":return try AgentIO.json(["kind":kind,"model":AgentIO.encode(AgentDocumentModel(d))],pretty:true)
            default:break
            }
        case .presentation(let p):
            switch ext {
            case "pptx":return PPTXWriter.write(p)
            case "txt":return Data(p.plainText.utf8)
            case "json":return try AgentIO.json(["kind":kind,"model":AgentIO.encode(AgentPresentationModel(p))],pretty:true)
            default:break
            }
        case .spreadsheet(let b):return try AgentSheets.data(b,format:ext)
        case .xml(let x):
            if ["xml","hml"].contains(ext) { return x.xmlData }
        }
        throw AgentError("unsupported_format","Cannot write \(kind) as .\(ext)")
    }
}
