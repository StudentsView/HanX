import AppKit

// Preserve the user's clipboard even if a failing interaction check crashes.
let saved=NSPasteboard.general.pasteboardItems?.map { item in item.types.compactMap { type in item.data(forType:type).map { (type,$0) } } } ?? []
let child=Process()
child.executableURL=URL(fileURLWithPath:CommandLine.arguments[1])
child.arguments=Array(CommandLine.arguments.dropFirst(2))
do { try child.run(); child.waitUntilExit() } catch { fputs("Cannot run interaction checks: \(error)\n",stderr); exit(1) }
NSPasteboard.general.clearContents()
let items=saved.map { pairs -> NSPasteboardItem in let item=NSPasteboardItem(); for (type,data) in pairs { item.setData(data,forType:type) }; return item }
NSPasteboard.general.writeObjects(items)
exit(child.terminationStatus)
