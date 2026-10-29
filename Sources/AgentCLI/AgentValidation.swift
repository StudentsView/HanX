import Foundation

/// Validate the model before calling format writers that use fixed-width
/// binary fields. Decoding Codable data alone does not establish these bounds.
enum AgentValidation {
    static func require(_ condition:Bool,_ message:String)throws { if !condition { throw AgentError("invalid_argument",message) } }
    static func dimension(_ n:Double,_ name:String,zero:Bool=false)throws {
        try require(n.isFinite && n<=100_000 && (zero ? n>=0 : n>0),"\(name) must be \(zero ? "0" : ">0")...100000 points")
    }
    static func string(_ s:String,_ name:String)throws { try require(s.utf16.count<=1024,"\(name) exceeds 1024 UTF-16 units") }
    static func chars(_ c:CharProps)throws {
        try string(c.fontName,"Font name"); if let name=c.eastAsianFontName { try string(name,"East Asian font name") }
        try require(c.size.isFinite && c.size>0 && c.size<=4000,"Font size must be 0 < size <= 4000 points")
        try require(c.widthRatio.isFinite && c.widthRatio>0 && c.widthRatio<=1000,"Invalid character width ratio")
        try require(c.spacing.isFinite && abs(c.spacing)<=1000,"Invalid character spacing")
    }
    static func paragraph(_ p:Paragraph,images:[String:ImageData],binaryHWP:Bool=false)throws {
        if binaryHWP { try require(p.inlines.count<=65534,"HWP paragraph has too many character runs (maximum 65534)") }
        try chars(p.markProps)
        for inline in p.inlines {
            switch inline {
            case .text(_,let c),.tab(let c),.lineBreak(let c),.field(_,let c):try chars(c)
            case .image(let id,let w,let h):
                try require(images[id] != nil,"Missing image data: \(id)"); try dimension(w,"Image width"); try dimension(h,"Image height")
            case .pageBreak:break
            }
        }
        switch p.props.lineSpacing {
        case .multiple(let n),.percentOfSize(let n),.exact(let n),.atLeast(let n):try require(n.isFinite && n>=0 && n<=100_000,"Invalid line spacing")
        }
    }
    static func table(_ t:Table,images:[String:ImageData],binaryHWP:Bool=false)throws {
        let columns=t.columnCount
        try require(!t.rows.isEmpty && t.rows.count<=10_000 && columns>0 && columns<=1000 && t.rows.count*columns<=100_000,"Invalid table dimensions")
        for w in t.columnWidths { try dimension(w,"Table column width") }
        try require(t.borderWidth.isFinite && t.borderWidth>=0 && t.borderWidth<=1000,"Invalid table border width")
        for (r,row) in t.rows.enumerated() { for (c,cell) in row.enumerated() {
            try require(cell.colSpan>0 && cell.colSpan<=columns-c && cell.rowSpan>0 && cell.rowSpan<=t.rows.count-r,"Table cell span exceeds its grid")
            if let w=cell.width { try dimension(w,"Cell width",zero:true) }; if let h=cell.height { try dimension(h,"Cell height",zero:true) }
            if let padding=cell.padding {
                for n in [padding.left,padding.right,padding.top,padding.bottom] {
                    try require(n.isFinite && n>=0 && n<=(binaryHWP ? 655.35 : 100_000),"Cell padding exceeds supported range")
                }
            }
            try blocks(cell.blocks,images:images,binaryHWP:binaryHWP)
        } }
    }
    static func blocks(_ values:[Block],images:[String:ImageData],binaryHWP:Bool=false)throws {
        if binaryHWP { try require(values.count<=65535,"HWP block list exceeds 65535 paragraphs") }
        for b in values { switch b { case .paragraph(let p):try paragraph(p,images:images,binaryHWP:binaryHWP); case .table(let t):try table(t,images:images,binaryHWP:binaryHWP) } }
    }
    static func imageNames(_ images:[String:ImageData])throws {
        for image in images.values { try string(image.name,"Image filename") }
    }
    static func hwpTables(_ doc:UDocument)throws {
        var fonts=Set<String>(),paragraphs=Set<Data>(),borders=Set<Data>()
        func character(_ c:CharProps) { fonts.insert(c.fontName); if let east=c.eastAsianFontName { fonts.insert(east) } }
        func walk(_ blocks:[Block])throws {
            for block in blocks {
                switch block {
                case .paragraph(let p):
                    character(p.markProps)
                    paragraphs.insert(try AgentIO.json(AgentIO.encode(p.props)))
                    if p.props.pageBreakBefore { var props=p.props; props.pageBreakBefore=false; paragraphs.insert(try AgentIO.json(AgentIO.encode(props))) }
                    for inline in p.inlines { switch inline { case .text(_,let c),.tab(let c),.lineBreak(let c),.field(_,let c):character(c); default:break } }
                case .table(let t):
                    for row in t.rows { for cell in row {
                        let value:[String:Any]=["borders":try AgentIO.encode(cell.borders),"background":try cell.background.map { try AgentIO.encode($0) } ?? NSNull()]
                        borders.insert(try AgentIO.json(value)); try walk(cell.blocks)
                    } }
                }
                try require(fonts.count<=65530 && paragraphs.count<=65530 && borders.count<=65530,"HWP font/paragraph/border style table exceeds binary capacity")
            }
        }
        try require(doc.images.count<=65535,"Too many embedded images for HWP")
        for section in doc.sections { try walk(section.blocks); try walk(section.header ?? []); try walk(section.footer ?? []) }
    }
    static func file(_ file:AgentFile,format:String)throws {
        switch file {
        case .document(let d):
            try AgentIO.validateNumbers(AgentIO.encode(AgentDocumentModel(d)))
            try require(!d.sections.isEmpty && d.sections.count<=65535,"Invalid section count")
            try imageNames(d.images)
            for s in d.sections {
                let p=s.page
                try dimension(p.width,"Page width"); try dimension(p.height,"Page height")
                for n in [p.marginLeft,p.marginRight,p.marginTop,p.marginBottom,p.header,p.footer] { try dimension(n,"Page margin",zero:true) }
                try require(p.width>p.marginLeft+p.marginRight && p.height>p.marginTop+p.marginBottom,"Margins leave no content area")
                try blocks(s.blocks,images:d.images,binaryHWP:format == "hwp"); try blocks(s.header ?? [],images:d.images,binaryHWP:format == "hwp"); try blocks(s.footer ?? [],images:d.images,binaryHWP:format == "hwp")
            }
            if format == "hwp" { try hwpTables(d) }
        case .presentation(let p):
            try AgentIO.validateNumbers(AgentIO.encode(AgentPresentationModel(p)))
            try dimension(p.width,"Slide width"); try dimension(p.height,"Slide height"); try imageNames(p.images)
            try require(p.slides.count<=65535,"Too many slides")
            for slide in p.slides {
                let ids=Set(slide.shapes.map(\.id))
                try require(ids.count == slide.shapes.count,"Duplicate shape IDs in slide")
                for shape in slide.shapes {
                    try require(shape.id>=0,"Negative shape ID")
                    try dimension(shape.frame.w,"Shape width",zero:shape.kind == .line)
                    try dimension(shape.frame.h,"Shape height",zero:shape.kind == .line)
                    try require(shape.kind != .line || shape.frame.w>0 || shape.frame.h>0,"Line has no extent")
                    if let id=shape.imageID { try require(p.images[id] != nil,"Missing image data: \(id)") }
                    for paragraph in shape.paragraphs { try self.paragraph(paragraph,images:p.images) }
                    if let table=shape.table { try self.table(table,images:p.images) }
                    try require(shape.lineWidth>=0 && shape.lineWidth<=1000,"Invalid line width")
                    try require(shape.autofitScale>0 && shape.autofitScale<=1000,"Invalid text scale")
                }
                for animation in slide.animations {
                    try require(ids.contains(animation.shapeID),"Animation points to missing shape")
                    try require(animation.duration>0 && animation.duration<=3600 && animation.delay>=0 && animation.delay<=86400,"Invalid animation timing")
                }
                try require(slide.transition.duration>=0 && slide.transition.duration<=60,"Invalid transition duration")
                if let after=slide.transition.advanceAfter { try require(after>=0 && after<=86400,"Invalid slide advance delay") }
            }
        case .spreadsheet(let b):try AgentSheets.validate(b)
        case .xml:break
        }
    }
}
