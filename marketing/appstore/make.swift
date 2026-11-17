import AppKit
let W=1206,H=2622
let srcs=["IMG_7558","IMG_7559","IMG_7560","IMG_7561"].map{"/Users/imac/Downloads/\($0).PNG"}
let band:[CGFloat]=[130,175,230,130]
let cap:[String:[(String,String)]]=[
"ko":[("보고 싶은 영상으로","영어 공부 시작"),("자막을 읽으며","모르는 단어 미리 확인"),("카드로 복습하고","연속 학습일 달성"),("내 단어장을 한눈에","오프라인에서도")],
"en":[("Learn English from","videos you love"),("Read the subtitles,","preview new words"),("Review with flashcards,","keep your streak"),("Your word list,","always offline")]]
func color(_ h:Int)->NSColor{NSColor(srgbRed:CGFloat(h>>16&255)/255,green:CGFloat(h>>8&255)/255,blue:CGFloat(h&255)/255,alpha:1)}
for (lang,items) in cap { for i in 0..<4 {
 let img=NSImage(contentsOfFile:srcs[i])!
 let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:W,pixelsHigh:H,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:32)!
 NSGraphicsContext.saveGraphicsState()
 let ctx=NSGraphicsContext(bitmapImageRep:rep)!; NSGraphicsContext.current=ctx
 NSGradient(starting:color(0x0E6F62),ending:color(0x28A890))!.draw(in:NSRect(x:0,y:0,width:W,height:H),angle:-60)
 // screenshot
 let sw:CGFloat=1010, sh=sw*2622/1206, sx=(CGFloat(W)-sw)/2, top:CGFloat=520
 let r=NSRect(x:sx,y:CGFloat(H)-top-sh,width:sw,height:sh)
 NSColor.black.withAlphaComponent(0.25).setFill()
 let shadow=NSShadow(); shadow.shadowBlurRadius=50; shadow.shadowOffset=NSSize(width:0,height:-20); shadow.shadowColor=NSColor.black.withAlphaComponent(0.35)
 NSGraphicsContext.saveGraphicsState(); shadow.set(); NSBezierPath(roundedRect:r,xRadius:150,yRadius:150).fill(); NSGraphicsContext.restoreGraphicsState()
 NSGraphicsContext.saveGraphicsState()
 NSBezierPath(roundedRect:r,xRadius:150,yRadius:150).addClip()
 img.draw(in:r)
 // cover status bar band with sampled color
 let bm=NSBitmapImageRep(data:img.tiffRepresentation!)!
 let c=bm.colorAt(x:600,y:Int(band[i]+70))!
 c.setFill(); let bh=band[i]*sh/2622
 NSRect(x:r.minX,y:r.maxY-bh,width:sw,height:bh).fill()
 NSGraphicsContext.restoreGraphicsState()
 // captions
 let font1:NSFont = lang=="ko" ? (NSFont(name:"AppleSDGothicNeo-ExtraBold",size:92) ?? .boldSystemFont(ofSize:92)) : .systemFont(ofSize:92,weight:.heavy)
 let para=NSMutableParagraphStyle(); para.alignment = .center
 for (j,t) in [items[i].0,items[i].1].enumerated(){
  let a:[NSAttributedString.Key:Any]=[.font:font1,.foregroundColor:j==0 ? NSColor.white : color(0xFFD27A),.paragraphStyle:para]
  (t as NSString).draw(in:NSRect(x:40,y:CGFloat(H)-190-CGFloat(j)*118-100,width:CGFloat(W)-80,height:120),withAttributes:a)
 }
 NSGraphicsContext.restoreGraphicsState()
 try! rep.representation(using:.png,properties:[:])!.write(to:URL(fileURLWithPath:"\(lang)_\(i+1).png"))
}}
