import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

enum AgentXML {
    static let packageNS="http://schemas.microsoft.com/office/2006/xmlPackage"
    static func parse(_ data:Data)throws->XMLDocument {
        // Also detect UTF-16/32 ASCII markup before invoking the XML parser.
        let markup=String(decoding:data.filter {$0 != 0},as:UTF8.self)
        guard markup.range(of:"<!DOCTYPE",options:.caseInsensitive) == nil,markup.range(of:"<!ENTITY",options:.caseInsensitive) == nil else { throw AgentError("unsafe_xml","DTD and external entities are not supported") }
        do {
            let doc=try XMLDocument(data:data,options:[.nodePreserveAll,.nodeLoadExternalEntitiesNever])
            guard doc.rootElement() != nil else { throw AgentError("invalid_xml","XML has no document element") }
            return doc
        } catch let e as AgentError { throw e } catch { throw AgentError("invalid_xml",error.localizedDescription) }
    }
    static func query(_ doc:XMLDocument,xpath:String?)throws->[String:Any] {
        var result:[String:Any]=["root":doc.rootElement()?.name ?? "","xml":doc.xmlString]
        if let xpath {
            let nodes=try select(doc,xpath)
            result["nodes"]=nodes.map { n -> [String:Any] in
                var value:[String:Any]=["name":n.name ?? "","text":n.stringValue ?? "","xml":n.xmlString,"xpath":n.xPath ?? ""]
                if let e=n as? XMLElement { value["attributes"]=Dictionary((e.attributes ?? []).map { ($0.name ?? "",$0.stringValue ?? "") },uniquingKeysWith: { a,_ in a }) }
                return value
            }
        }
        return result
    }
    static func select(_ doc:XMLDocument,_ xpath:String)throws->[XMLNode] {
        guard !xpath.isEmpty else { throw AgentError("invalid_xpath","XPath must not be empty") }
        do { return try doc.nodes(forXPath:xpath) } catch { throw AgentError("invalid_xpath",error.localizedDescription) }
    }
    static func fragments(_ xml:String,at node:XMLNode)throws->[XMLNode] {
        var namespaces:[String:String]=[:],p:XMLNode?=node
        while let n=p {
            if let e=n as? XMLElement { for ns in e.namespaces ?? [] { let prefix=ns.name ?? ""; if namespaces[prefix] == nil { namespaces[prefix]=ns.stringValue ?? "" } } }
            p=n.parent
        }
        let declarations=namespaces.sorted {$0.key<$1.key}.map { key,value in " xmlns\(key.isEmpty ? "" : ":"+key)=\"\(XMLEscape.text(value))\"" }.joined()
        let doc=try parse(Data("<hanxFragment\(declarations)>\(xml)</hanxFragment>".utf8))
        return (doc.rootElement()?.children ?? []).map { $0.copy() as! XMLNode }
    }
    static func patch(_ doc:XMLDocument,operations:[Any])throws->XMLDocument {
        for value in operations {
            let op=try AgentIO.map(value,"XML operation"),name=try AgentIO.string(op["op"],"op")
            guard ["set_text","set_attribute","delete","append_xml","replace_xml"].contains(name) else { throw AgentError("invalid_operation","Unknown XML operation: \(name)") }
            let xpath=try AgentIO.string(op["xpath"],"xpath"),nodes=try select(doc,xpath)
            guard !nodes.isEmpty else { throw AgentError("xpath_not_found","No nodes match \(xpath)") }
            for node in nodes {
                switch name {
                case "set_text":node.stringValue=try AgentIO.string(op["text"],"text")
                case "set_attribute":
                    guard let e=node as? XMLElement else { throw AgentError("invalid_operation","set_attribute requires an element") }
                    let name=try AgentIO.string(op["name"],"attribute name"),value=try AgentIO.string(op["value"],"attribute value")
                    guard !name.isEmpty,!name.hasPrefix("xmlns") else { throw AgentError("invalid_argument","Use XML replacement to change namespaces") }
                    if let a=e.attribute(forName:name) { a.stringValue=value }
                    else {
                        if name.contains(":") {
                            guard let uri=e.resolveNamespace(forName:name)?.stringValue else { throw AgentError("invalid_argument","Unknown namespace prefix in \(name)") }
                            e.addAttribute(XMLNode.attribute(withName:name,uri:uri,stringValue:value) as! XMLNode)
                        } else { e.addAttribute(XMLNode.attribute(withName:name,stringValue:value) as! XMLNode) }
                    }
                case "delete":
                    guard node.parent != nil,!(node.parent is XMLDocument) else { throw AgentError("invalid_operation","Cannot delete the document root") }; node.detach()
                case "append_xml":
                    guard let e=node as? XMLElement else { throw AgentError("invalid_operation","append_xml requires an element") }
                    for child in try fragments(AgentIO.string(op["xml"],"xml"),at:node) { e.addChild(child) }
                case "replace_xml":
                    let children=try fragments(AgentIO.string(op["xml"],"xml"),at:node)
                    if let parent=node.parent as? XMLElement {
                        let index=node.index; node.detach()
                        for (offset,child) in children.enumerated() { parent.insertChild(child,at:index+offset) }
                    } else if node.parent is XMLDocument,children.count == 1,let e=children[0] as? XMLElement { doc.setRootElement(e) }
                    else { throw AgentError("invalid_operation","Invalid root replacement") }
                default:break
                }
            }
        }
        // Detect invalid names, unbound prefixes and malformed root changes.
        return try parse(doc.xmlData)
    }
    static func zip(_ path:String)throws->ZipReader {
        let data=try AgentIO.read(path)
        guard ZipReader.isZip(data) else { throw AgentError("invalid_format","Expected a DOCX/PPTX/HWPX ZIP package") }
        let z=try ZipReader(data:data)
        guard !z.order.isEmpty,z.order.count<=65000,Set(z.order).count == z.order.count,
              z.order.allSatisfy({$0.utf8.count<=65535 && !$0.contains("\0")}) else { throw AgentError("invalid_format","Invalid or oversized ZIP directory") }
        return z
    }
    static func packageList(_ path:String)throws->[String:Any] {
        let z=try zip(path)
        return ["parts":z.order.map { name -> [String:Any] in ["name":name,"size":z.entries[name]?.size ?? 0,"xml":name.lowercased().hasSuffix(".xml") || name.lowercased().hasSuffix(".rels")] }]
    }
    static func packageRead(_ path:String,part:String,xpath:String?)throws->[String:Any] {
        let z=try zip(path)
        guard let data=z.read(part) else { throw AgentError("part_not_found","Package part not found: \(part)") }
        if let xml=try? parse(data) { var value=try query(xml,xpath:xpath); value["part"]=z.resolve(part) ?? part; return value }
        guard xpath == nil else { throw AgentError("invalid_xml","Part is not XML") }
        return ["part":part,"base64":data.base64EncodedString(),"size":data.count]
    }
    static func packagePatch(_ path:String,part:String,operations:[Any])throws->Data {
        let z=try zip(path)
        guard let key=z.resolve(part),let data=z.read(key) else { throw AgentError("part_not_found","Package part not found: \(part)") }
        let changed=try patch(parse(data),operations:operations).xmlData
        let writer=ZipWriter()
        for name in z.order {
            guard let original=z.read(name) else { throw AgentError("invalid_format","Cannot decompress package part: \(name)") }
            writer.add(name,name == key ? changed : original,compress:name != "mimetype")
        }
        return writer.finish()
    }
    static func flatten(_ path:String)throws->Data {
        let z=try zip(path),root=XMLElement(name:"pkg:package")
        root.addNamespace(XMLNode.namespace(withName:"pkg",stringValue:packageNS) as! XMLNode)
        var defaults:[String:String]=[:],overrides:[String:String]=[:]
        if let types=z.read("[Content_Types].xml") {
            let doc=try parse(types)
            for e in doc.rootElement()?.elementChildren ?? [] {
                if e.local == "Default",let key=e.attr("Extension"),let type=e.attr("ContentType") { defaults[key]=type }
                if e.local == "Override",let key=e.attr("PartName"),let type=e.attr("ContentType") { overrides[key]=type }
            }
        }
        for name in z.order where name != "[Content_Types].xml" {
            guard let data=z.read(name) else { throw AgentError("invalid_format","Cannot read \(name)") }
            let part=XMLElement(name:"pkg:part"),ext=(name as NSString).pathExtension.lowercased()
            let type=overrides["/"+name] ?? defaults[ext] ?? (["xml","rels","hpf"].contains(ext) ? "application/xml" : "application/octet-stream")
            part.addAttribute(XMLNode.attribute(withName:"pkg:name",stringValue:"/"+name) as! XMLNode)
            part.addAttribute(XMLNode.attribute(withName:"pkg:contentType",stringValue:type) as! XMLNode)
            if let doc=try? parse(data),let element=doc.rootElement() {
                let container=XMLElement(name:"pkg:xmlData"); container.addChild(element.copy() as! XMLNode); part.addChild(container)
            } else {
                let container=XMLElement(name:"pkg:binaryData",stringValue:data.base64EncodedString()); part.addChild(container)
            }
            root.addChild(part)
        }
        let xml=XMLDocument(rootElement:root); xml.version="1.0"; xml.characterEncoding="UTF-8"
        return xml.xmlData
    }
    static func unflatten(_ doc:XMLDocument,extension ext:String)throws->Data {
        guard let root=doc.rootElement(),root.local == "package",root.uri == packageNS else { throw AgentError("invalid_format","Expected Flat OPC package XML") }
        var parts:[(String,String,Data)]=[],seen=Set<String>()
        for part in root.elementChildren {
            guard part.local == "part",let absolute=part.attr("name"),absolute.hasPrefix("/") else { throw AgentError("invalid_format","Invalid Flat OPC part") }
            let name=String(absolute.dropFirst())
            guard !name.isEmpty,name.utf8.count<=65535,!name.contains("\0"),!name.split(separator:"/").contains(".."),seen.insert(name).inserted else { throw AgentError("invalid_format","Invalid, oversized or duplicate package part name") }
            let data:Data
            if let xml=part.child("xmlData"),let element=xml.elementChildren.first {
                let content=XMLDocument(rootElement:(element.copy() as! XMLElement)); content.version="1.0"; content.characterEncoding="UTF-8"; data=content.xmlData
                _ = try parse(data)
            } else if let text=part.child("binaryData")?.stringValue,let binary=Data(base64Encoded:text.components(separatedBy:.whitespacesAndNewlines).joined()) { data=binary }
            else { throw AgentError("invalid_format","Missing package part content: \(name)") }
            parts.append((name,part.attr("contentType") ?? "application/octet-stream",data))
        }
        guard parts.count<=65000 else { throw AgentError("invalid_format","Too many package parts") }
        let expected=ext == "pptx" ? "ppt/presentation.xml" : ext == "docx" ? "word/document.xml" : ext == "hwpx" ? "Contents/header.xml" : ext == "xlsx" ? "xl/workbook.xml" : ""
        guard !expected.isEmpty,seen.contains(expected) else { throw AgentError("unsupported_format","Package does not match .\(ext)") }
        let z=ZipWriter()
        if ext != "hwpx",!seen.contains("[Content_Types].xml") {
            let overrides=parts.map { "<Override PartName=\"/\(XMLEscape.text($0.0))\" ContentType=\"\(XMLEscape.text($0.1))\"/>" }.joined()
            z.add("[Content_Types].xml","<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">\(overrides)</Types>")
        }
        // The HWPX mimetype entry must remain first and stored.
        if let mime=parts.first(where:{$0.0 == "mimetype"}) { z.add(mime.0,mime.2,compress:false) }
        for (name,_,data) in parts where name != "mimetype" { z.add(name,data) }
        return z.finish()
    }
}
