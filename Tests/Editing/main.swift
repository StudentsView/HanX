import Foundation
func check(_ value: @autoclosure () -> Bool, _ name: String) { if !value() { fatalError(name) } }
func near(_ a: Double, _ b: Double) -> Bool { abs(a-b) < 0.001 }
let base = Frame(x: 40, y: 30, w: 200, h: 100)
let f = ShapeGeometry.resized(base, rotation: 90, handle: 4, dx: -50, dy: 100, preserveAspect: true)
check(near(f.w/f.h, 2), "rotated aspect ratio")
let before = ShapeGeometry.world(x: base.x, y: base.y, frame: base, rotation: 90)
let after = ShapeGeometry.world(x: f.x, y: f.y, frame: f, rotation: 90)
check(near(before.0,after.0) && near(before.1,after.1), "opposite rotated corner stays fixed")
let tiny = ShapeGeometry.resized(base, rotation: 0, handle: 0, dx: 10000, dy: 10000, preserveAspect: true)
check(tiny.w >= 1 && tiny.h >= 1 && near(tiny.w/tiny.h,2), "minimum size keeps ratio")
let p = Presentation.blank()
p.slides = TransitionKind.allCases.map { kind in
 var s = Slide(); s.transition.kind = kind; s.transition.duration = 1.237; s.transition.advanceOnClick = false; s.transition.advanceAfter = 3.25; s.transition.vertical = [.split,.blinds,.checker,.comb,.randomBar].contains(kind); s.transition.inward = [.split,.zoom].contains(kind); s.transition.direction = kind == .none ? .right : .left
 s.shapes = ShapeKind.allCases.filter { ![.image,.table,.line,.text].contains($0) }.enumerated().map { i,k in
  var sh = SlideShape(id:i+2,name:k.rawValue,kind:k,frame:base); sh.rotation=37; sh.flipH=true; sh.flipV=true; sh.lockAspect=true; sh.fill = .black; return sh
 }
 return s
}
let url = URL(fileURLWithPath: CommandLine.arguments[1])
try PPTXWriter.write(p).write(to:url)
let back = try SlidesIO.load(url:url)
check(back.slides.count == p.slides.count,"slide count")
for (a,b) in zip(p.slides,back.slides) {
 check(a.transition == b.transition,"transition roundtrip \(a.transition.kind)")
 check(a.shapes.count == b.shapes.count,"shapes")
 for (x,y) in zip(a.shapes,b.shapes) { check(x.kind == y.kind && near(x.rotation,y.rotation) && y.flipH && y.flipV && y.lockAspect,"shape transform \(x.kind)") }
}
print("PASS geometry + \(back.slides.count) transitions + \(p.slides[0].shapes.count) shape kinds PPTX roundtrip")
var tableShape=SlideShape(id:2,kind:.table,frame:base)
var table=Table(); table.columnWidths=[40,60]; table.rows=[[TableCell(),TableCell()]]
tableShape.table=table; tableShape.tableRowHeights=[20]; tableShape.rotation=45; tableShape.flipH=true; tableShape.lockAspect=true
let special=Presentation(); special.slides=[Slide(shapes:[tableShape])]
try PPTXWriter.write(special).write(to:url)
let tableBack=try SlidesIO.load(url:url).slides[0].shapes[0]
check(near(tableBack.rotation,45) && tableBack.flipH && tableBack.lockAspect,"table transforms saved")
check(near(tableBack.table!.columnWidths.reduce(0,+),base.w),"table columns scale to frame")
for dir in AnimDirection.allCases {
 special.slides[0].transition.kind = .strips; special.slides[0].transition.direction=dir
 try PPTXWriter.write(special).write(to:url)
 let stripBack=try SlidesIO.load(url:url)
 check(stripBack.slides[0].transition.direction == dir,"all strip directions")
}
print("PASS table transforms, table scaling, all four strip directions")

let anchors:[(Double,Double)]=[(1,1),(0.5,1),(0,1),(0,0.5),(0,0),(0.5,0),(1,0),(1,0.5)]
for angle in [0.0,30,90,180,270] { for h in 0..<8 {
 let delta=ShapeGeometry.rotated(40,20,angle)
 let changed=ShapeGeometry.resized(base,rotation:angle,handle:h,dx:delta.0,dy:delta.1,preserveAspect:true)
 let a=anchors[h], old=ShapeGeometry.world(x:base.x+base.w*a.0,y:base.y+base.h*a.1,frame:base,rotation:angle)
 let new=ShapeGeometry.world(x:changed.x+changed.w*a.0,y:changed.y+changed.h*a.1,frame:changed,rotation:angle)
 check(near(old.0,new.0) && near(old.1,new.1) && near(changed.w/changed.h,2),"all rotated handle anchors")
} }
var imageShape=SlideShape(id:3,kind:.image,frame:base)
imageShape.imageID="tiny"; imageShape.rotation=27; imageShape.flipH=true; imageShape.flipV=true; imageShape.lockAspect=true
var lineShape=SlideShape(id:4,kind:.line,frame:base)
lineShape.rotation=71; lineShape.flipH=true; lineShape.lockAspect=true
special.images["tiny"]=ImageData(name:"tiny.png",data:Data(base64Encoded:"iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aX24AAAAASUVORK5CYII=")!)
special.slides[0].shapes=[imageShape,lineShape]
try PPTXWriter.write(special).write(to:url)
let mediaBack=try SlidesIO.load(url:url)
check(mediaBack.slides[0].shapes[0].rotation == 27 && mediaBack.slides[0].shapes[0].flipV && mediaBack.slides[0].shapes[0].lockAspect,"image transforms")
check(mediaBack.slides[0].shapes[1].rotation == 71 && mediaBack.slides[0].shapes[1].flipH && mediaBack.slides[0].shapes[1].lockAspect,"line transforms")
print("PASS 40 rotated handle anchors, image and line transforms")
var editable=Table(); editable.columnWidths=[100,100]
var styled=TableCell(); styled.blocks=[.paragraph(Presentation.textParagraph("원래 내용",size:19,bold:true))]
var covered=TableCell(); covered.isMergedAway=true
editable.rows=[[styled,covered]]
let edited=SlideTableEditing.settingText(editable,row:0,column:0,text:"새 내용\n둘째 줄")
check(SlideTableEditing.text(edited.rows[0][0]) == "새 내용\n둘째 줄","table cell multiline editing")
if case .paragraph(let paragraph)=edited.rows[0][0].blocks[0] { check(paragraph.markProps.size == 19 && paragraph.markProps.bold,"table cell style preserved") }
let untouched=SlideTableEditing.settingText(editable,row:0,column:1,text:"병합 셀")
check(SlideTableEditing.text(untouched.rows[0][1]).isEmpty,"merged-away cell untouched")
print("PASS table cell editing, text style and merged cell preservation")
var heading=Presentation.textParagraph("Heading",size:24,bold:true,align:.center)
var body=Presentation.textParagraph("Body",size:12,align:.left)
var red=CharProps(); red.size=12; red.color=RGB(r:210,g:30,b:40)
body.inlines.append(.text(" red",red))
var rich=Table(); rich.rows=[[TableCell(blocks:[.paragraph(heading),.paragraph(body)])]]
let richEdit=SlideTableEditing.settingText(rich,row:0,column:0,text:"Heading\nBody! red")
if case .paragraph(let h)=richEdit.rows[0][0].blocks[0],case .paragraph(let b)=richEdit.rows[0][0].blocks[1] {
    check(h.props == heading.props && h.markProps == heading.markProps,"untouched heading formatting")
    check(b.props == body.props && b.markProps == body.markProps,"body paragraph formatting")
    check(b.inlines.contains { if case .text(let text,let props)=$0 { return text == " red" && props == red }; return false },"untouched colored run")
    check(b.inlines.contains { if case .text(let text,let props)=$0 { return text == "Body!" && props.size == 12 && !props.bold }; return false },"edited run formatting")
}
let splitEdit=SlideTableEditing.settingText(rich,row:0,column:0,text:"Heading\nBody\nnew red")
if case .paragraph(let b)=splitEdit.rows[0][0].blocks[2] { check(b.props == body.props,"inserted paragraph inherits body") }
print("PASS table text edits retain distinct paragraph and mixed run formatting")
let notesPresentation=Presentation.blank()
notesPresentation.slides[0].notes="발표 노트 & 내용\n다음 줄"
let notesBack=try PPTXReader(zip:ZipReader(data:PPTXWriter.write(notesPresentation))).read()
check(notesBack.slides[0].notes == "발표 노트 & 내용\n다음 줄","speaker notes survive PPTX clipboard/save roundtrip")
let emptyPresentation=Presentation()
let emptyBack=try PPTXReader(zip:ZipReader(data:PPTXWriter.write(emptyPresentation))).read()
check(emptyBack.slides.isEmpty,"zero slides remain empty after save/reopen")
print("PASS speaker notes and empty presentation roundtrip")
var nativeShape=imageShape
nativeShape.locked=true; nativeShape.sourceIDs=[10,99]; nativeShape.wrap=false
let native=Presentation(); native.slides=[Slide(shapes:[nativeShape])]; native.slides[0].notes="메모\n둘째 줄"; native.images=special.images
native.images["unused"]=ImageData(name:"unused.png",data:Data([0]))
let nativeBack=SlideClipboard.decode(try SlideClipboard.encode(native))!
let nativeCopied=nativeBack.slides[0].shapes[0]
check(nativeCopied.locked && nativeCopied.sourceIDs == [10,99] && !nativeCopied.wrap && nativeBack.slides[0].notes == native.slides[0].notes,"native clipboard retains editing metadata")
check(nativeBack.images.count == 1 && nativeBack.images["tiny"]?.data == native.images["tiny"]?.data,"native clipboard includes referenced images only")
let legacy=SlideClipboard.decode(PPTXWriter.write(notesPresentation))
check(legacy?.slides.first?.notes == notesPresentation.slides.first?.notes,"legacy PPTX clipboard remains readable")
check(SlideClipboard.decode(Data("invalid".utf8)) == nil,"invalid clipboard rejected")
print("PASS native clipboard metadata, referenced media, legacy fallback and invalid data")
var inlineParagraph=Paragraph(); inlineParagraph.inlines=[.image(id:"tiny",width:10,height:12)]
var nestedTable=Table(); nestedTable.rows=[[TableCell(blocks:[.paragraph(inlineParagraph)])]]
var outerTable=Table(); outerTable.rows=[[TableCell(blocks:[.table(nestedTable)])]]
var withInline=nativeShape; withInline.paragraphs=[inlineParagraph]; withInline.table=outerTable
var withBackground=Slide(shapes:[withInline]); withBackground.backgroundImage="tiny"
let mapped=SlideClipboard.remappingMedia([withBackground],ids:["tiny":"new-media"])[0]
check(mapped.backgroundImage == "new-media" && mapped.shapes[0].imageID == "new-media","background and shape media remapped")
if case .image(let id,_,_)=mapped.shapes[0].paragraphs[0].inlines[0] { check(id == "new-media","inline media remapped") } else { fatalError("inline image missing") }
if case .table(let t)=mapped.shapes[0].table!.rows[0][0].blocks[0],case .paragraph(let p)=t.rows[0][0].blocks[0],case .image(let id,_,_)=p.inlines[0] { check(id == "new-media","nested table media remapped") } else { fatalError("nested media missing") }
print("PASS clipboard media references remapped through nested tables")
