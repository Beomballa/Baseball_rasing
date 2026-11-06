import SwiftUI
import UIKit
import SpriteKit
#if DEBUG
import Darwin
import os
import Metal
import QuartzCore
import ObjectiveC
#endif

#if DEBUG
/// QA opt-in only: read the drawable's actual presentedTime, independently of main-thread callbacks.
final class MatchDrawableProbe:@unchecked Sendable {
    static let shared=MatchDrawableProbe()
    struct Frame:Encodable {let presented:Double;let uptime:Double;let surface:String}
    struct Snapshot:Encodable {let frames:[Frame];let zeroTimes:Int;let layers:Int;let hostOffset:Double;let endHostOffset:Double}
    private let lock=NSLock()
    private var layerIDs=Set<ObjectIdentifier>(),viewIDs=Set<ObjectIdentifier>()
    private var surfaces:[ObjectIdentifier:String]=[:]
    private var frames:[Frame]=[],zeroTimes=0,hostOffset=0.0,hooked=false
    private var enabled:Bool {ProcessInfo.processInfo.arguments.contains("-qa-presented-times")}
    @MainActor func register(_ view:SKView,surface:String="arena") {
        guard enabled else {return}
        lock.lock();let known=viewIDs.contains(ObjectIdentifier(view));lock.unlock();if known {return}
        var found=Set<ObjectIdentifier>()
        func visit(_ layer:CALayer) {
            if layer is CAMetalLayer {found.insert(ObjectIdentifier(layer))}
            for child in layer.sublayers ?? [] {visit(child)}
        }
        visit(view.layer)
        lock.lock();layerIDs.formUnion(found)
        for id in found {surfaces[id]=surface}
        if !found.isEmpty {viewIDs.insert(ObjectIdentifier(view))}
        let install = !hooked;hooked=true;lock.unlock()
        if install,let original=class_getInstanceMethod(CAMetalLayer.self,#selector(CAMetalLayer.nextDrawable)),
           let replacement=class_getInstanceMethod(CAMetalLayer.self,#selector(CAMetalLayer.bmQANextDrawable)) {
            method_exchangeImplementations(original,replacement)
        }
    }
    func tracks(_ layer:CAMetalLayer)->Bool {lock.lock();defer{lock.unlock()};return layerIDs.contains(ObjectIdentifier(layer))}
    func record(_ time:Double,layer:CAMetalLayer) {
        lock.lock();defer{lock.unlock()}
        if time>0,frames.count<5000 {frames.append(Frame(presented:time,uptime:time+hostOffset,surface:surfaces[ObjectIdentifier(layer)] ?? "unknown"))}
        else if time<=0 {zeroTimes+=1}
    }
    @MainActor func reset() {
        lock.lock();defer{lock.unlock()};frames=[];zeroTimes=0
        hostOffset=ProcessInfo.processInfo.systemUptime-CACurrentMediaTime()
    }
    @MainActor func snapshot()->Snapshot {
        lock.lock();defer{lock.unlock()}
        return Snapshot(frames:frames,zeroTimes:zeroTimes,layers:layerIDs.count,hostOffset:hostOffset,
                        endHostOffset:ProcessInfo.processInfo.systemUptime-CACurrentMediaTime())
    }
}
private extension CAMetalLayer {
    @objc dynamic func bmQANextDrawable()->(any CAMetalDrawable)? {
        let drawable=bmQANextDrawable()
        let selector=NSSelectorFromString("addPresentedHandler:")
        if let object=drawable as? NSObject,MatchDrawableProbe.shared.tracks(self),object.responds(to:selector) {
            // 일부 SDK의 Drawable 전방 선언을 피하고 같은 공개 ObjC API를 호출한다.
            let handler:@convention(block)(AnyObject)->Void = { value in
                if let number=(value as? NSObject)?.value(forKey:"presentedTime") as? NSNumber {
                    MatchDrawableProbe.shared.record(number.doubleValue,layer:self)
                }
            }
            _ = object.perform(selector,with:handler)
        }
        return drawable
    }
}
#endif

// Presentation geometry never changes the saved pitch, timing window or RNG.
enum MatchArt {
    static let names = ["batter-view-clean", "stadium-clean", "batter-actions", "pitcher-delivery-v2", "catcher-parts",
                        "grip-fastball", "grip-slider", "grip-changeup", "grips-extra", "inplay-stadium-arcade-v1",
                        "batter-field-v52", "pitcher-field-v52", "opponent-pitcher-v52", "opponent-batter-v52",
                        "batter-actions-v75", "pitcher-delivery-v75", "batting-practice-v75", "opponent-batter-v116"]
    private static let images: [String: UIImage] = Dictionary(uniqueKeysWithValues: names.compactMap { name in
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "MatchArt"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        return (name, image)
    })
    // Analysis needs only this portrait; opening it must not initialize the full match-art dictionary.
    static let opponentPortrait:UIImage? = {
        guard let url=Bundle.main.url(forResource:"opponent-avatar-v1",withExtension:"png",subdirectory:"MatchArt") else {return nil}
        return UIImage(contentsOfFile:url.path)
    }()
    static func image(_ name: String) -> UIImage? { images[name] }
    static func cell(_ name: String, column: Int, row: Int, columns: Int, rows: Int) -> UIImage? {
        guard let source = image(name)?.cgImage,
              let crop = source.cropping(to: CGRect(x: column * source.width / columns, y: row * source.height / rows,
                                                   width: source.width / columns, height: source.height / rows)) else { return nil }
        return UIImage(cgImage: crop)
    }
}

// Bundled raster presentation only. None of these samples are written to the match ledger.
@MainActor enum FieldRasterArt {
    struct Frame: Decodable, Sendable {
        let file: String
        let action: String
        let rect: [Double]
        let pivot: [Double]
        let clipRows: [[Int]]
        let hand: [Double]
        let glove: [Double]
        let sourceLeft: Bool
        let referenceHeight: Double?
        let numberCenter: [Double]?
    }
    struct Sheet: Decodable {let referenceHeight: Double;let frames: [Frame]}
    struct Manifest: Decodable {let kinds: [String:[String:Sheet]]}
    struct Sample {let frame:Frame;let weight:Double;let unit:Double;let mirrored:Bool;var rearFacing=false}
    static let directions=["n","ne","e","se","s","sw","w","nw"]
    static let manifest: Manifest? = {
        guard let url=Bundle.main.url(forResource:"field-runtime-v1",withExtension:"json",subdirectory:"MatchArt"),
              let data=try? Data(contentsOf:url) else {return nil}
        return try? JSONDecoder().decode(Manifest.self,from:data)
    }()
    private static let cache: NSCache<NSString,UIImage> = {
        let c=NSCache<NSString,UIImage>();c.totalCostLimit=48*1024*1024
        #if DEBUG
        c.delegate=cacheMetrics
        #endif
        return c
    }()
    #if DEBUG
    static let cacheMetrics=FieldCacheMetrics()
    static func resetCacheForVerification() {cache.removeAllObjects();cacheMetrics.reset()}
    #endif
    static func samples(_ motion:FieldSpriteMotion,kind:String,left:Bool) -> [Sample] {
        let direction=left ? (8-motion.facing.rawValue)%8:motion.facing.rawValue
        guard let sheet=manifest?.kinds[kind]?[directions[direction]] else {return []}
        let p=max(0,min(1,motion.progress))
        let caught=motion.airCatch && kind == "fielder" ? "airCatch":motion.chestCatch && kind == "fielder" ? "gather":"catch"
        var poses:[(String,Double)]
        switch motion.stage {
        case .ready:poses=[("ready",1)]
        case .run:
            // Pixel running is a frame cycle, not an alpha dissolve between two bodies.
            poses=[(sin(motion.gait)>=0 ? "runB":"runA",1)]
        case .catchBall:poses=[("ready",1-p),(caught,p)]
        case .gather:
            poses=motion.willThrow ? [(caught,1-p),("gather",p)]:p<0.5 ? [(caught,1-p*2),("gather",p*2)]:[("gather",2-p*2),("ready",p*2-1)]
        case .windup:poses=p<0.5 ? [("gather",1-p*2),("windup",p*2)]:[("windup",2-p*2),("release",p*2-1)]
        case .release:poses=[("release",1)]
        case .followThrough:
            poses=kind == "catcher" ? [("release",1-p),("ready",p)]:p<0.5 ? [("release",1-p*2),("followThrough",p*2)]:[("followThrough",2-p*2),("ready",p*2-1)]
        }
        if kind == "runner" && motion.runnerPose == .slide {
            let phase=motion.reducedArrival ? 0.5:motion.arrivalProgress
            poses=[(phase<0.24 ? "slideEnter":phase<0.82 ? "slideHold":"slideRecover",1)]
        } else if kind != "runner" && motion.baseReceive != .none {
            let action: String
            switch motion.receivePose {
            case .reach:action="baseReach"
            case .secure,.recover:action="baseSecure"
            case .tag:action="baseTag"
            }
            poses=[(action,1)]
        }
        if kind == "fielder",motion.relayTransfer {
            if motion.stage == .gather {poses=[(p<0.5 ? "transferSecure":"transferExtract",1)]}
            else if motion.stage == .windup {poses=[(p<0.25 ? "transferPlant":p<0.75 ? "windup":"release",1)]}
        }
        if kind != "runner",motion.errorPose != .none {
            poses=[(motion.errorPose == .spill ? "spill":motion.errorPose == .reach ? "missReach":motion.errorPose == .scoop ? "scoop":"scoopSecure",1)]
        }
        // Use one opaque pose; the ball reads exactly the same hand/mitt anchor.
        if let pose=poses.enumerated().max(by: {a,b in a.element.1 == b.element.1 ? a.offset<b.offset:a.element.1<b.element.1}) {
            poses=[(pose.element.0,1)]
        }
        // A single physical scale for the whole direction avoids pose-dependent size pulses.
        let widest=sheet.frames.filter {$0.referenceHeight == nil}.map {$0.rect[2]}.max() ?? sheet.referenceHeight
        let unit=min(24/sheet.referenceHeight,26/widest)
        return poses.compactMap {action,weight in
            guard weight>0,let frame=sheet.frames.first(where:{$0.action==action}) ?? sheet.frames.first(where:{$0.action=="ready"}) else {return nil}
            let authoredUnit:Double
            if let height=frame.referenceHeight {
                let width=sheet.frames.filter {$0.referenceHeight == height}.map {$0.rect[2]}.max() ?? frame.rect[2]
                authoredUnit=min(24/height,26/width)
            } else {authoredUnit=unit}
            return Sample(frame:frame,weight:weight,unit:authoredUnit,mirrored:left != frame.sourceLeft,rearFacing:direction == 0)
        }
    }
    static func contact(_ motion:FieldSpriteMotion,kind:String,left:Bool,hand:Bool) -> CGPoint? {
        let frames=samples(motion,kind:kind,left:left);guard !frames.isEmpty else {return nil}
        return frames.reduce(CGPoint.zero) {point,sample in
            let f=sample.frame,a=hand ? f.hand:f.glove
            return CGPoint(x:point.x+(a[0]-f.pivot[0])*sample.unit*sample.weight*(sample.mirrored ? -1:1),
                           y:point.y+(a[1]-f.pivot[1])*sample.unit*sample.weight)
        }
    }
    static func image(_ sample:Sample,kit:Int,skin:Int,hair:Int,number:Int,back:Bool,style:GameUniformStyle?=nil,prepared:Prepared?=nil) -> UIImage? {
        let request=Request(sample:sample,kit:kit,skin:skin,hair:hair,number:number,back:back,style:style)
        let key=request.key as NSString
        if let result=prepared?.images[request.key] {
            #if DEBUG
            if MatchRenderMetrics.enabled {MatchRenderMetrics.preparedHits+=1}
            #endif
            return result
        }
        #if DEBUG
        if prepared != nil && MatchRenderMetrics.enabled {MatchRenderMetrics.preparedMisses+=1}
        #endif
        if let result=cache.object(forKey:key) {
            #if DEBUG
            cacheMetrics.hit()
            #endif
            return result
        }
        #if DEBUG
        cacheMetrics.miss()
        #endif
        guard let url=Bundle.main.url(forResource:request.frame.file,withExtension:nil,subdirectory:"MatchArt"),
              let original=UIImage(contentsOfFile:url.path)?.cgImage,let result=build(request,original:original) else {return nil}
        #if DEBUG
        cacheMetrics.insert(result,cost:result.cgImage!.bytesPerRow*result.cgImage!.height)
        #endif
        cache.setObject(result,forKey:key,cost:result.cgImage!.bytesPerRow*result.cgImage!.height);return result
    }
    struct Request:Sendable {
        let frame:Frame
        let kit:Int,skin:Int,hair:Int,number:Int
        let back:Bool,mirrored:Bool
        let style:GameUniformStyle?
        let garmentBack: Bool
        let garmentMirrored: Bool
        init(sample:Sample,kit:Int,skin:Int,hair:Int,number:Int,back:Bool,style:GameUniformStyle?=nil) {
            frame=sample.frame;self.style=style;self.kit=kit;self.skin=skin;self.hair=hair
            self.number=back && sample.rearFacing ? number:0;self.back=back && sample.rearFacing;mirrored=self.back && sample.mirrored
            garmentBack = style?.pro != nil && back
            garmentMirrored = style?.pro != nil && sample.mirrored
        }
        var key:String {
            let legacy = "\(frame.file):\(frame.rect):\(kit):\(skin):\(hair):\(number):\(back):\(mirrored):\(style?.id ?? "legacy")"
            return style?.pro == nil ? legacy : "\(legacy):\(garmentBack):\(garmentMirrored)"
        }
    }
    // Immutable images cross the worker boundary, then live only for this replay.
    struct Prepared:Sendable {
        let images:[String:UIImage]
        var bytes:Int {images.values.reduce(0) {$0+($1.cgImage.map {$0.bytesPerRow*$0.height} ?? 0)}}
    }
    static func prepare(_ requests:[String:Request]) async -> Prepared? {
        let worker=Task.detached(priority:.userInitiated) { () -> Prepared? in
            var images:[String:UIImage]=[:],sources:[String:CGImage]=[:]
            for (key,request) in requests.sorted(by:{$0.key<$1.key}) {
                guard !Task.isCancelled else {return nil}
                let image:UIImage?=autoreleasepool {
                    if sources[request.frame.file] == nil,
                       let url=Bundle.main.url(forResource:request.frame.file,withExtension:nil,subdirectory:"MatchArt") {
                        sources[request.frame.file]=UIImage(contentsOfFile:url.path)?.cgImage
                    }
                    return sources[request.frame.file].flatMap {build(request,original:$0)}
                }
                if let image {images[key]=image}
            }
            return Prepared(images:images)
        }
        return await withTaskCancellationHandler(operation:{await worker.value},onCancel:{worker.cancel()})
    }
    nonisolated private static func build(_ request:Request,original:CGImage) -> UIImage? {
        let f=request.frame,kit=request.kit,skin=request.skin,hair=request.hair,number=request.number,back=request.back
        guard let crop=original.cropping(to:CGRect(x:f.rect[0],y:f.rect[1],width:f.rect[2],height:f.rect[3])) else {return nil}
        let w=crop.width,h=crop.height,format=CGBitmapInfo.byteOrder32Big.rawValue|CGImageAlphaInfo.premultipliedLast.rawValue
        var bytes=[UInt8](repeating:0,count:w*h*4)
        let ok=bytes.withUnsafeMutableBytes {buffer -> Bool in
            guard let c=CGContext(data:buffer.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:format) else {return false}
            c.draw(crop,in:CGRect(x:0,y:0,width:w,height:h));return true
        }
        guard ok else {return nil}
        var bounds=[(Int,Int)](repeating:(0,0),count:h)
        var backCloth=[Bool](repeating:false,count:w*h),sumX=0.0,sumY=0.0,clothCount=0.0
        let pro = request.style?.pro != nil
        let catcher = f.file.hasPrefix("catcher-")
        // In other poses the blue fabric can be a raised cleat, so its existing colors stay in place.
        let standingFielder = f.action == "ready" && (f.file == "fielder-s-v1.png" || f.file == "fielder-n-v1.png")
        for row in f.clipRows where row.count==3 && row[0]<h {bounds[row[0]]=(row[1],row[1]+row[2])}
        for y in 0..<h {for x in 0..<w {
            let i=(y*w+x)*4,a=Int(bytes[i+3])
            guard x>=bounds[y].0 && x<bounds[y].1 else {bytes[i+3]=0;bytes[i]=0;bytes[i+1]=0;bytes[i+2]=0;continue}
            guard a>128 else {continue}
            let r=Double(bytes[i])*255/Double(a),g=Double(bytes[i+1])*255/Double(a),b=Double(bytes[i+2])*255/Double(a)
            let nx = Double(x) / Double(w), ny = Double(y) / Double(h)
            var color:Int?,shade=1.0
            if b>40 && b>r*1.35 && b>g*1.08 {
                if (0.30...0.68).contains(nx) && (0.30...0.65).contains(ny) {
                    backCloth[y*w+x]=true;sumX+=Double(x);sumY+=Double(y);clothCount+=1
                }
                if let style=request.style {
                    if pro && catcher { color = style.gear ?? style.sleeves }
                    else if ny < 0.30 { color = ny > 0.26 ? style.brim : style.cap }
                    else if ny < 0.56 {
                        color = style.shirt(x: nx, y: (ny - 0.32) / 0.24, back: request.garmentBack, mirrored: request.garmentMirrored)
                    } else if pro && standingFielder && (0.77..<0.865).contains(ny) {
                        color = style.sock(base: style.sleeves, y: (ny - 0.77) / 0.095)
                    } else { color = style.gear ?? style.sleeves }
                } else {color=kit}
                shade=max(0.3,min(1.5,b/155))
            }
            else if pro && standingFielder, let style = request.style, min(r,g,b) > 110, max(r,g,b)-min(r,g,b) < 65,
                    (0.40...0.52).contains(ny), nx < 0.36 || nx > 0.64 {
                color = style.sleeve(base: style.sleeves, y: 1)
                shade = max(0.35, min(1.1, (r + g + b) / 735))
            }
            else if let style=request.style, !(pro && catcher), min(r,g,b)>110, max(r,g,b)-min(r,g,b)<65,
                    ny > 0.56, ny < 0.81 {
                if pro && !catcher {
                    let (left, right) = bounds[y]
                    color = style.leg(base: style.pants, x: Double(x - left) / Double(right - left),
                                      y: (ny - 0.56) / 0.25,
                                      back: request.garmentBack, mirrored: request.garmentMirrored)
                } else { color = style.pants }
                shade=max(0.35,min(1.1,(r+g+b)/735))
            }
            // Keep the glove's brown leather independent from skin recoloring.
            else if (f.file.hasPrefix("runner-") || abs(Double(x)-f.glove[0])>Double(w)*0.16 || abs(Double(y)-f.glove[1])>Double(h)*0.18) && r>185 && r>g*1.13 && g>b*1.12 && g>95 {color=skin;shade=max(0.45,min(1.2,r/240))}
            else if Double(y)>Double(h)*0.19 && Double(y)<Double(h)*0.36 && Double(x)>Double(w)*0.23 && Double(x)<Double(w)*0.77 && r<65 && abs(r-g)<22 && abs(g-b)<22 {color=hair;shade=max(0.5,(r+g+b)/100)}
            if let color {for (offset,shift) in [(0,16),(1,8),(2,0)] {bytes[i+offset]=UInt8(min(255,Double((color>>shift)&255)*shade)*Double(a)/255)}}
        }}
        if !back && !(pro && catcher) {
            request.style?.drawMark(at: CGPoint(x: Double(w) * (request.garmentMirrored ? 0.65 : 0.35), y: Double(h) * 0.40), unit: 1,
                                    mirrored: request.garmentMirrored, eligible: pro ? backCloth : nil, bytes: &bytes, width: w, height: h)
        }
        if back, clothCount > 0 {
            let center=CGPoint(x:f.numberCenter?[0] ?? sumX/clothCount,y:f.numberCenter?[1] ?? sumY/clothCount)
            let ink=request.style?.ink ?? 0xf4f0db
            PlayerMotionArt.drawNumber(number,at:center,angle:0,mirrored:request.mirrored,unit:max(2,w/70),
                ink:ink,outline:GameUniformStyle.outline(for:ink),eligible:backCloth,bytes:&bytes,width:w,height:h)
        }
        guard let provider=CGDataProvider(data:Data(bytes) as CFData),let cg=CGImage(width:w,height:h,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:format),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else {return nil}
        return UIImage(cgImage:cg)
    }
    @discardableResult static func draw(in context:GraphicsContext,at point:CGPoint,scale:Double,motion:FieldSpriteMotion,
            kind:String,kit:Int,skin:Int,hair:Int,number:Int,left:Bool,selected:Bool,out:Bool,style:GameUniformStyle?=nil,prepared:Prepared?=nil) -> Bool {
        let frames=samples(motion,kind:kind,left:left);guard !frames.isEmpty else {return false}
        var c=context
        c.opacity=out ? 0.38:1
        c.fill(Path(ellipseIn:CGRect(x:point.x-7*scale,y:point.y-1*scale,width:14*scale,height:3*scale)),with:.color(.black.opacity(0.25)))
        if selected {c.stroke(Path(ellipseIn:CGRect(x:point.x-8*scale,y:point.y-2*scale,width:16*scale,height:4*scale)),with:.color(GameTheme.gold),lineWidth:1)}
        if kind == "runner" && [.slide,.decelerate].contains(motion.runnerPose) {
            for i in 0..<3 {
                let trail=Double(i+1)*3
                let alpha=(1-motion.arrivalProgress)*0.55
                c.fill(Path(CGRect(x:point.x-motion.facing.vector.x*trail*scale,y:point.y+Double(i%2)*scale,width:2*scale,height:scale)),with:.color(Color(hex:0xc39962).opacity(alpha)))
            }
        }
        for sample in frames {
            guard let image=image(sample,kit:kit,skin:skin,hair:hair,number:number,back:motion.facing.back && kind != "catcher",style:style,prepared:prepared) else {return false}
            let f=sample.frame,u=sample.unit*scale
            var layer=c;layer.opacity *= sample.weight
            layer.translateBy(x:point.x+motion.bodyOffset.x*scale,y:point.y+motion.bodyOffset.y*scale)
            if kind == "runner" && motion.runnerPose == .tagUp {
                layer.scaleBy(x:1,y:0.90)
            }
            if sample.mirrored {layer.scaleBy(x:-1,y:1)}
            let rect=CGRect(x:-f.pivot[0]*u,y:-f.pivot[1]*u,width:f.rect[2]*u,height:f.rect[3]*u)
            layer.draw(Image(uiImage:image).interpolation(.none),in:rect)
        }
        return true
    }
}

// A transient presentation clock. It is never encoded in the career/match ledger.
struct FieldContactHandoff {
    let startedAt:Double
    let cutAt:Double
    let sourcePoint:CGPoint // top-left normalized coordinates in the SpriteKit arena
    var sourceFrame:CGRect = .zero
    func elapsed(at now:Double) -> Double {max(0,now-startedAt)}
    func delayed(by seconds:Double) -> Self {
        Self(startedAt:startedAt+seconds,cutAt:cutAt+seconds,sourcePoint:sourcePoint,sourceFrame:sourceFrame)
    }
}

enum FieldContactPresentation {
    static let cameraDuration=0.24
    static func duration(_ play:MatchDetailedPlay) -> Double {max(0,min(0.28,play.flight*0.30))}
    static func matches(_ play:MatchDetailedPlay,previous:CareerMatch,action:String) -> Bool {
        play.half == previous.half && play.order == (previous.half%2 == 1 ? previous.homeOrder:previous.awayOrder) && action != "watch"
    }
    static func sourcePoint(_ play:MatchDetailedPlay,time:Double,origin:CGPoint,size:CGSize) -> CGPoint {
        let t=max(0,min(play.duration,time)),first=FieldNode.sample(play.ball,at:0)
        let start=InplayFieldProjection.point(first,size:size)
        let point=InplayFieldProjection.point(FieldNode.sample(play.ball,at:t),size:size)
        return CGPoint(x:origin.x+(point.x-start.x)/size.width,
                       y:origin.y+(point.y-start.y-FieldReplayPresentation.lift(play,time:t,height:size.height))/size.height)
    }
    static func cameraOffset(_ handoff:FieldContactHandoff?,fieldPoint:CGPoint,canvas:CGRect,now:Double,reduced:Bool) -> CGPoint {
        guard !reduced,let h=handoff,h.sourceFrame.width>0,h.sourceFrame.height>0 else {return .zero}
        let global=CGPoint(x:h.sourceFrame.minX+h.sourcePoint.x*h.sourceFrame.width,y:h.sourceFrame.minY+h.sourcePoint.y*h.sourceFrame.height)
        guard canvas.contains(global) else {return .zero}
        let p=max(0,min(1,(now-h.cutAt)/cameraDuration)),remaining=pow(1-p,3)
        return CGPoint(x:(global.x-canvas.minX-fieldPoint.x)*remaining,y:(global.y-canvas.minY-fieldPoint.y)*remaining)
    }
}

enum MatchPresentation {
    static func batContact(action: String) -> CGPoint {
        let bunt = action == "bunt"
        let feet = bunt ? 471.0 : 503.0
        return CGPoint(x: -0.005 + 0.62 * (bunt ? 416 : 426) / 512,
                       y: 0.34 + 0.61 * (1 - feet / 512) + 0.61 * (bunt ? 245 : 266) / 512)
    }
    static func fieldSize(available: CGSize, role: PlayerRole, chromeHeight: CGFloat = 310) -> CGSize {
        let ratio = MatchPitchProjection(role: role).aspectRatio
        let height = min(max(150, available.height - chromeHeight), max(1, available.width) / ratio)
        return CGSize(width: height * ratio, height: height)
    }
    static func countPulse(_ outcome: String?) -> String? {
        switch outcome {
        case "볼", "볼넷": "B"
        case "루킹 스트라이크", "헛스윙", "삼진": "S"
        default: nil
        }
    }
    static func pitchName(_ result: ManualMatchResult?) -> String {
        guard let result else { return "투구 대기" }
        return result.pitchCode.flatMap { PitchType(rawValue: $0)?.label } ?? "구종 미기록"
    }
}

// Game-time calibration, separate from saved velocity and phase-based judgments.
struct PitchFlightPresentation {
    let flightDuration: Double
    var battingDuration: Double { flightDuration / MatchDelivery.contactPhase }
    init(delivery: MatchDelivery) {
        flightDuration = 0.90 * 145 / (delivery.exactSpeed ?? Double(delivery.speed))
    }
}

enum MatchBallPath {
    static func movement(_ code: String) -> (lateral: Double, drop: Double) {
        switch PitchType(rawValue: code) ?? .fourSeam {
        case .fourSeam: (0, 0.018)
        case .twoSeam: (-0.055, 0.05)
        case .cutter: (0.06, 0.035)
        case .slider: (0.10, 0.06)
        case .curve: (0.065, 0.23)
        case .changeup: (-0.05, 0.12)
        case .fork: (0, 0.20)
        case .sweeper: (0.19, 0.07)
        case .knuckle: (0.025, 0.16)
        }
    }
    static func point(from start: CGPoint, to end: CGPoint, size: CGSize, role: PlayerRole,
                      hand: String, code: String, progress: Double) -> CGPoint {
        let t = min(1, max(0, progress))
        let depth = role == .batter ? t / (2.4 - 1.4 * t) : 2.4 * t / (1 + 1.4 * t)
        // A late-breaking arc returns to the saved endpoint without oscillation.
        let bend = depth - depth * depth * depth
        let movement = movement(code)
        let lateral = movement.lateral * (hand == "left" ? -1.0 : 1)
        let drop = movement.drop
        return CGPoint(x: start.x + (end.x - start.x) * depth - lateral * size.width * bend,
                       y: start.y + (end.y - start.y) * depth + drop * size.height * bend)
    }
}

struct MatchPixelButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    var selected = false
    var primary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.font(.system(.subheadline, design: .monospaced, weight: .bold))
            .frame(maxWidth: .infinity, minHeight: primary ? 48 : 44)
            .foregroundStyle(enabled ? Color(hex: 0xf3edcf) : Color(hex: 0x9aacb7))
            .background(selected || primary ? Color(hex: 0x307855) : Color(hex: 0x203e57))
            .overlay(Rectangle().strokeBorder(selected ? GameTheme.gold : Color(hex: 0x7695a6), lineWidth: 2))
            .overlay(alignment: .bottom) { Rectangle().fill(.black.opacity(0.25)).frame(height: 3) }
            .opacity(enabled ? (configuration.isPressed ? 0.7 : 1) : 0.5)
    }
}

struct MatchScoreStrip: View {
    let match: CareerMatch
    let pitchCount: Int?
    let pulse: String?
    let pulseAt: Date
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.dynamicTypeSize) private var typeSize
    private let ink = Color(hex: 0xeee9cd)
    var body: some View {
        TimelineView(.animation(minimumInterval: 0.2, paused: reduced || pulse == nil)) { timeline in
            let elapsed = timeline.date.timeIntervalSince(pulseAt)
            let blink = !reduced && elapsed >= 0 && elapsed < 1.2 && Int(elapsed / 0.2).isMultiple(of: 2)
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                HStack(spacing: 8) {
                    VStack(spacing: 4) {
                        Text("\(match.half / 2 + 1) \(match.half % 2 == 0 ? "▲" : "▼")").bold()
                        Text(pitchCount.map { "P \($0)" } ?? "BAT").font(.system(.caption2, design: .monospaced))
                            .accessibilityIdentifier("boardPitchCount")
                    }.frame(minWidth: 32)
                    HStack(spacing: 8) {
                        lamps("B", count: match.balls, total: 3, blink: blink)
                        lamps("S", count: match.strikes, total: 2, blink: blink)
                        lamps("O", count: match.outs, total: 2, blink: blink)
                    }.accessibilityElement(children: .ignore)
                        .accessibilityLabel("B \(match.balls) S \(match.strikes) O \(match.outs)")
                        .accessibilityIdentifier("careerGameCount")
                }
                if !typeSize.isAccessibilitySize { Rectangle().fill(ink.opacity(0.25)).frame(width: 1) }
                let details = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
                details {
                    VStack(spacing: 2) {
                        Text(MatchPresentation.pitchName(match.lastManual)).font(.caption.bold())
                            .lineLimit(1).minimumScaleFactor(0.8).accessibilityIdentifier("boardPitchName")
                        HStack(alignment: .firstTextBaseline, spacing: 3) {
                            Text(match.lastManual.map { String($0.speed) } ?? "–––").lineLimit(1).minimumScaleFactor(0.8).font(.system(.title2, design: .monospaced, weight: .bold)).foregroundStyle(GameTheme.gold)
                            Text("km/h").font(.caption2)
                        }
                    }.frame(maxWidth: .infinity).accessibilityElement(children: .combine).accessibilityIdentifier("boardPitchSpeed")
                    VStack(alignment: .leading, spacing: 4) {
                        Text("날씨 · 예시").font(.caption2)
                        Text("맑음 22°C").font(.caption2.bold())
                        Text("바람 ↑ 2m/s").font(.caption2)
                    }.accessibilityLabel("예시 날씨 맑음 22도, 외야 방향 바람 초속 2미터")
                }
            }.foregroundStyle(ink).padding(8).frame(maxWidth: .infinity, minHeight: 64)
                .background(Color(hex: 0x0b3552))
                .overlay(Rectangle().strokeBorder(Color(hex: 0x69a4bf), lineWidth: 1))
        }.accessibilityElement(children: .contain).accessibilityIdentifier("matchScoreboard")
    }
    private func lamps(_ label: String, count: Int, total: Int, blink: Bool) -> some View {
        VStack(spacing: 4) {
            HStack(spacing: 3) { Text(label).font(.caption2); Text("\(count)").font(.system(.headline, design: .monospaced, weight: .bold)) }
            HStack(spacing: 3) {
                ForEach(0..<total, id: \.self) { i in
                    let confirming = pulse == label && i == (count == 0 ? total - 1 : min(count, total) - 1)
                    Rectangle().fill(i < count || confirming ? (label == "B" ? Color(hex: 0x82e6b2) : Color(hex: 0xed7c6b)) : Color(hex: 0x082337))
                        .frame(width: 6, height: 6).overlay(Rectangle().strokeBorder(ink.opacity(0.5), lineWidth: 0.5))
                        .opacity(confirming && blink ? 0.2 : 1)
                }
            }
        }
    }
}

struct MatchGrip: View {
    let code: String
    let hand: String
    static func image(code: String) -> UIImage? {
        let extra: [String: Int] = ["two-seam": 0, "cutter": 2, "sweeper": 3, "curve": 4, "fork": 6, "knuckle": 7]
        if let cell = extra[code] { return MatchArt.cell("grips-extra", column: cell % 4, row: cell / 4, columns: 4, rows: 2) }
        return MatchArt.image(code == "slider" ? "grip-slider" : code == "changeup" ? "grip-changeup" : "grip-fastball")
    }
    var body: some View {
        if let image = Self.image(code: code) {
            Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
                .scaleEffect(x: hand == "left" ? -1 : 1, y: 1)
                .accessibilityLabel((hand == "left" ? "왼손 " : "오른손 ") + (PitchType(rawValue: code)?.label ?? "구종") + " 그립")
        }
    }
}

// Read-only projection of the completed ledger; never estimates missing statistics.
struct MatchResultSummary {
    struct Metric: Identifiable, Equatable {
        let id: String
        let label: String
        let value: String
    }
    let match: CareerMatch
    let fatigueBefore: Int
    let fatigueAfter: Int
    var outcome: String {
        match.teamScore == match.opponentScore ? "무승부" : (match.teamScore > match.opponentScore ? "승리" : "패배")
    }
    var metrics: [Metric] {
        guard match.appearance else { return [] }
        let l = match.line
        let values: [(String, String, String)] = match.role == "pitcher" ? [
            ("innings", "이닝", "\(l.pitchingOuts / 3).\(l.pitchingOuts % 3)"), ("pitches", "투구 수", "\(l.pitches)"),
            ("hitsAllowed", "피안타", "\(l.hitsAllowed)"), ("runsAllowed", "실점", "\(l.runsAllowed)"),
            ("pitchingWalks", "볼넷", "\(l.pitchingWalks)"), ("pitchingStrikeouts", "탈삼진", "\(l.pitchingStrikeouts)")
        ] : [
            ("plateAppearances", "타석", "\(l.plateAppearances)"), ("atBats", "타수", "\(l.atBats)"),
            ("hits", "안타", "\(l.hits)"), ("homeRuns", "홈런", "\(l.homeRuns)"),
            ("rbi", "타점", "\(l.rbi)"), ("walks", "볼넷", "\(l.walks)"), ("strikeouts", "삼진", "\(l.strikeouts)")
        ]
        var result=values.map { Metric(id: $0.0, label: $0.1, value: $0.2) }
        if (match.detailedFieldVersion ?? 0) >= 2,let plays=match.fieldPlays {
            let count=plays.filter { $0.secondThrow?.out == true && (match.role == "batter" ? $0.ownBatter : (($0.half % 2 == 1) != match.isHome)) }.count
            result.append(Metric(id:"doublePlays",label:match.role == "batter" ? "병살타" : "병살 유도",value:String(count)))
        }
        if (match.detailedFieldVersion ?? 0) >= 3,match.role == "batter" {
            let count=match.fieldPlays?.filter { $0.ownBatter && $0.sacrificeFly }.count ?? 0
            result.append(Metric(id:"sacrificeFlies",label:"희생플라이",value:String(count)))
        }
        if match.detailedFieldVersion == 5 {
            let plays=match.fieldPlays ?? []
            result.append(Metric(id:"fieldingErrors",label:"내 수비 실책",value:String(plays.filter { $0.misplay?.ownError == true }.count)))
            result.append(Metric(id:"teamErrors",label:"팀 실책",value:String(plays.filter { $0.misplay != nil && (($0.half % 2 == 1) != match.isHome) }.count)))
            if match.role == "batter" {result.append(Metric(id:"reachedOnError",label:"실책 출루",value:String(plays.filter { $0.ownBatter && $0.misplay?.reachedOnError == true }.count)))}
        }
        return result
    }
    var fatigueChange: String {
        let delta = fatigueAfter - fatigueBefore
        return delta == 0 ? "변화 없음" : (delta > 0 ? "+\(delta)" : "\(delta)")
    }
    var appliedTraits: [PlayerTrait] { match.lastFieldPlay?.appliedTraits ?? [] }
    var traitMessage: String {
        guard match.appearance else { return "비등판 · 개인 특성 적용 기록 없음" }
        guard let play = match.lastFieldPlay else { return "저장된 개인 주루·수비 경합이 없습니다." }
        guard play.appliedTraits != nil else { return "이전 기록 · 적용 특성 미기록" }
        return appliedTraits.isEmpty ? "마지막 개인 경합에 적용된 특성 없음" : "마지막 개인 경합에서 적용"
    }
}


enum FieldReplayPresentation {
    static func resultTitle(_ play:MatchDetailedPlay) -> String {
        if let error=play.misplay {return error.kind == .fielding ? "포구 실책":"악송구"}
        return play.secondThrow?.out == true ? "DOUBLE PLAY":play.fly?.caught == true && play.targetRunner == nil ? "CATCH · OUT":play.out ? "OUT":"SAFE"
    }
    static func errorDetail(_ play:MatchDetailedPlay,ownTeamFielding:Bool) -> String? {
        guard let error=play.misplay else {return nil}
        let positions=["투수","포수","1루수","2루수","3루수","유격수","좌익수","중견수","우익수"]
        let result=error.reachedOnError ? "실책 출루 · 안타 제외":error.ordinaryHitBases>0 ? "안타 인정 · 실책 별도":error.extraBases.isEmpty ? "실책으로 주자 생존":"실책으로 추가 진루"
        return "\(ownTeamFielding ? "우리 팀":"상대 팀") \(positions[error.fielder]) · \(result)"
    }
    static func stageHeight(width:CGFloat,available:CGFloat,accessibility:Bool=false) -> CGFloat {
        max(320,min(width*1.5+36,available-112)) + (accessibility ? 160:0)
    }
    static func elapsed(start:Double?,handoff:FieldContactHandoff?,now:Double) -> Double {
        handoff?.elapsed(at:now) ?? start.map {max(0,now-$0)} ?? 0
    }
    static func seconds(_ play:MatchDetailedPlay,reduced:Bool,animated:Bool) -> Double {
        animated ? max(3,play.duration):0
    }
    static func time(_ play:MatchDetailedPlay,elapsed:Double,reduced:Bool,animated:Bool) -> Double {
        guard animated else {return play.duration}
        let time=min(play.duration,max(0,elapsed))
        guard reduced else {return time}
        // Reduced motion uses readable, ordered stills instead of skipping to the result.
        let moments=[0,play.flight,play.pickupAt,play.releaseAt,play.ballAt,play.controlAt,play.duration]
            + (play.relay.map {[$0.receiveAt,$0.releaseAt]} ?? [])
            + (play.secondThrow.map {[$0.releaseAt,$0.ballAt,$0.controlAt]} ?? [])
            + (play.misplay.map {[$0.at,$0.scatteredAt,$0.recoveredAt]} ?? [])
        let runnerMoments=play.runners.flatMap {runner in runner.nodes.map(\.at)}
        return (moments+runnerMoments+FieldMisplayAnimation.moments(play)+FieldRelayTransfer.moments(play)).filter {$0<=time}.max() ?? 0
    }
    static func retired(_ runner:DetailedRunner,finished:Bool) -> Bool {
        finished && runner.out
    }
    static func phase(_ play:MatchDetailedPlay,time:Double,finished:Bool) -> String {
        if finished {return play.summary}
        if let error=play.misplay,time>=error.at && time<error.recoveredAt {
            if time<error.scatteredAt {return error.kind == .fielding ? "포구 놓침 · 공 이탈":"빗나간 송구 · 수신 시도"}
            if time<(FieldMisplayAnimation.recoveryStart(play) ?? error.recoveredAt) {return "벗어난 공 추격 · 주자 이동 중"}
            return "몸을 낮춰 회수 · 주자 이동 중"
        }
        if time < play.flight {
            if let ball=play.battedBall {return "\(ball.kind.label) · 타구 \(Int(ball.kmh.rounded())) km/h / 야수 추격"}
            return play.fly == nil ? "타격 · 땅볼 이동 / 야수 추격":"타격 · 공중 타구 / 야수 추격"
        }
        if time < play.pickupAt {return "타구 도착 · 야수 포구 준비"}
        if let relay=play.relay,time>=play.releaseAt {
            if time < relay.receiveAt {return "외야 송구 · 중계 야수 수신 대기"}
            if time < relay.releaseAt {
                let motion=FieldSpriteAnimation.motion(play,index:relay.fielder,time:time)
                if motion.stage == .windup {return "중계 전환 · 발 디딤/송구 준비"}
                return motion.stage == .gather && motion.progress>=0.5 ? "중계 전환 · 공 빼기":"중계 포구 · 공 확보"
            }
        }
        if let second=play.secondThrow,time>=play.controlAt && time<second.releaseAt {return "베이스 포구 · 1루 재송구 준비"}
        if play.fly?.caught == true && play.targetRunner == nil && play.misplay == nil {return "포구 · 플레이 확인 중"}
        if time < play.releaseAt {return "포구 · 송구 자세 전환"}
        return "송구 · 주자와 베이스 경합"
    }
    static func lift(_ play:MatchDetailedPlay,time:Double,height:Double) -> Double {
        if let error=FieldMisplayAnimation.lift(play,time:time,height:height) {return error}
        if time < play.flight {
            if let ball=play.battedBall {return min(height*0.28,ball.height(at:time)*height*0.009)}
            let t=max(0,min(1,time/max(0.001,play.flight)))
            return play.fly == nil ? abs(sin(t * .pi * 4))*3:sin(t * .pi)*height*0.19
        }
        for (a,b) in zip(play.ball,play.ball.dropFirst()) where time>=a.at && time<b.at && a.at>=play.releaseAt && a.point != b.point {
            return sin(.pi*(time-a.at)/max(0.001,b.at-a.at))*height*0.035
        }
        return 0
    }
    static func opponentKit(_ own:Int) -> Int {
        [0x294c77,0xf0ead9,0x9a3e39].max {a,b in
            func distance(_ color:Int) -> Int {
                [0,8,16].reduce(0) {sum,shift in let d=((color>>shift)&255)-((own>>shift)&255);return sum+d*d}
            }
            return distance(a)<distance(b)
        }!
    }

}

/// Supporting movement is derived for display. Saved pursuit, contact and throws keep their own paths.
enum FieldBackupRoutes {
    struct Route {
        let nodes: [FieldNode]
        let focus: FieldPoint

        func motion(at time: Double) -> FieldSpriteMotion {
            var motion = FieldSpriteAnimation.travel(nodes, time: time)
            if motion.stage == .ready {
                let point = FieldNode.sample(nodes, at: time)
                motion.facing = .direction(dx: focus.x - point.x, dy: focus.y - point.y)
            }
            return motion
        }
    }

    static func make(_ play: MatchDetailedPlay) -> [Int: Route] {
        // An error already has its own missed reception and recovery choreography.
        guard play.misplay == nil else { return [:] }
        var assigned: Set<Int> = [play.fielder]
        if play.ballAt > play.flight { assigned.insert(play.receiver) }
        if let relay = play.relay { assigned.insert(relay.fielder) }
        if let second = play.secondThrow { assigned.insert(second.receiver) }

        func idleStart(_ index: Int) -> FieldPoint? {
            guard play.fielders.indices.contains(index), !assigned.contains(index),
                  let first = play.fielders[index].first else { return nil }
            let nodes = play.fielders[index]
            if nodes.allSatisfy({ $0.point == first.point }) { return first.point }
            // Some saved grounders give all uninvolved fielders the same small shift toward the ball.
            if nodes.count == 2, nodes[1].at == play.pickupAt,
               nodes[1].point == first.point.towards(play.landing, fraction: 0.12) { return first.point }
            return nil
        }

        var routes: [Int: Route] = [:]
        func add(_ index: Int, toward goal: FieldPoint, focus: FieldPoint, reaction: Double, deadline: Double) {
            guard let start = idleStart(index), routes[index] == nil else { return }
            let distance = start.distance(to: goal)
            let duration = min(distance / 5.8 + 0.20, deadline - reaction)
            let travel = (duration - 0.20) * 5.8
            guard distance >= 1, travel >= 1 else { return }
            let end = start.towards(goal, fraction: travel / distance)
            routes[index] = Route(nodes: [
                FieldNode(at: 0, point: start),
                FieldNode(at: reaction, point: start),
                FieldNode(at: reaction + duration * 0.18, point: start.towards(end, fraction: 0.11)),
                FieldNode(at: reaction + duration * 0.83, point: start.towards(end, fraction: 0.91)),
                FieldNode(at: reaction + duration, point: end)
            ], focus: focus)
        }

        if let fly = play.fly {
            let landing = play.landing
            let deadline = fly.caught ? play.flight : min(play.pickupAt, play.flight + 0.45)
            let preferred = landing.x < -8 ? 6 : landing.x > 8 ? 8 : 7
            // A nearby outfielder takes the far side of the drop; the original fielder owns the catch.
            let outfield = [6, 7, 8].compactMap { index in idleStart(index).map { (index, $0) } }
            let backup = outfield.first { $0.0 == preferred } ?? outfield.min {
                $0.1.distance(to: landing) < $1.1.distance(to: landing)
            }
            if let (index, start) = backup {
                let side = start.x < landing.x ? -1.0 : 1.0
                let goal = FieldPoint(x: landing.x + 8 * side, y: min(96, landing.y + 8))
                add(index, toward: goal, focus: landing, reaction: 0.28, deadline: deadline)
                if play.fielder < 6, index != 7, routes[index] != nil, let center = idleStart(7) {
                    let gap = center.towards(start, fraction: 0.4)
                    add(7, toward: gap, focus: landing, reaction: 0.48, deadline: deadline)
                }
            }

            if (play.outsBefore ?? 0) < 2 {
                if play.fielder == 4, play.runners.contains(where: { $0.from == 2 || $0.from == 3 }) {
                    let bag = DetailedFieldRules.bases[3]
                    add(5, toward: FieldPoint(x: bag.x + 1.5, y: bag.y + 1), focus: landing,
                        reaction: 0.44, deadline: play.flight)
                } else if play.fielder == 2, play.runners.contains(where: { $0.from == 1 }) {
                    let bag = DetailedFieldRules.bases[1]
                    add(3, toward: FieldPoint(x: bag.x - 1.5, y: bag.y + 1), focus: landing,
                        reaction: 0.44, deadline: play.flight)
                }
            }
        } else if play.ballAt > play.flight {
            func backUpThrow(to base: Int, by arrival: Double) {
                let outfielder: Int
                let offsetX: Double
                switch base {
                case 1: (outfielder, offsetX) = (8, 6)
                case 2: (outfielder, offsetX) = (7, 0)
                case 3: (outfielder, offsetX) = (6, -6)
                default: return
                }
                let bag = DetailedFieldRules.bases[base]
                add(outfielder, toward: FieldPoint(x: bag.x + offsetX, y: bag.y + 8), focus: bag,
                    reaction: 0.42, deadline: min(play.duration, arrival + 0.12))
            }
            backUpThrow(to: play.targetBase, by: play.ballAt)
            if let second = play.secondThrow { backUpThrow(to: 1, by: second.ballAt) }
        }
        return routes
    }
}

enum FieldFacing: Int,CaseIterable,Equatable {
    case north,northEast,east,southEast,south,southWest,west,northWest
    var back:Bool {[.north,.northEast,.northWest].contains(self)}
    var side:Bool {self == .east || self == .west}
    var diagonal:Bool {[.northEast,.southEast,.southWest,.northWest].contains(self)}
    var horizontal:Double {[.northWest,.west,.southWest].contains(self) ? -1:1}
    var vector:CGPoint {
        switch self {
        case .north:CGPoint(x:0,y:-1)
        case .northEast:CGPoint(x:0.707,y:-0.707)
        case .east:CGPoint(x:1,y:0)
        case .southEast:CGPoint(x:0.707,y:0.707)
        case .south:CGPoint(x:0,y:1)
        case .southWest:CGPoint(x:-0.707,y:0.707)
        case .west:CGPoint(x:-1,y:0)
        case .northWest:CGPoint(x:-0.707,y:-0.707)
        }
    }
    static func turn(from:Self,to:Self,fraction:Double) -> Self {
        var delta=to.rawValue-from.rawValue
        if delta>4 {delta-=8};if delta < -4 {delta+=8}
        let step=Int((Double(delta)*max(0,min(1,fraction))).rounded())
        return Self(rawValue:(from.rawValue+step+8)%8) ?? to
    }
    static func direction(dx:Double,dy:Double) -> Self {
        if abs(dx)+abs(dy)<0.000001 {return .south}
        if abs(dx)<abs(dy)*0.414 {return dy>0 ? .north:.south}
        if abs(dy)<abs(dx)*0.414 {return dx>0 ? .east:.west}
        if dx>0 {return dy>0 ? .northEast:.southEast}
        return dy>0 ? .northWest:.southWest
    }
}

enum FieldRunnerPose: Equatable {case stride,accelerate,turn,decelerate,slide,tagUp,settled}
enum FieldBaseReceive: Equatable {case none,force,tag}
enum FieldReceivePose: Equatable {case reach,secure,tag,recover}
enum FieldErrorPose: Equatable {case none,spill,reach,scoop,secured}

enum FieldSpriteStage: Equatable {case ready,run,catchBall,gather,windup,release,followThrough}
struct FieldSpriteMotion {
    var facing:FieldFacing
    var stage:FieldSpriteStage
    var progress:Double = 0
    var gait:Double = 0
    var airCatch=false
    var willThrow=false
    var chestCatch=false
    var runnerPose:FieldRunnerPose = .stride
    var baseReceive:FieldBaseReceive = .none
    var arrivalProgress:Double = 0
    var receivePose:FieldReceivePose = .reach
    var reducedArrival=false
    var errorPose:FieldErrorPose = .none
    var relayTransfer=false
    var ballInThrowingHand:Bool {
        [.windup,.release].contains(stage) || (relayTransfer && stage == .gather && progress>=0.5)
    }

    var bodyOffset:CGPoint {
        // These frames already articulate knees/hips and anchor the contact cleat to the bag.
        if runnerPose == .slide || baseReceive != .none || errorPose != .none || relayTransfer {return .zero}
        let lean=stage == .followThrough ? facing.vector.x*sin(progress * .pi)*2:stage == .run ? facing.vector.x*1.2:0
        let bob=stage == .run ? -abs(cos(gait))*1.4:stage == .catchBall && !airCatch && !chestCatch ? sin(progress * .pi/2)*3:stage == .gather && !airCatch && !chestCatch ? (1-progress)*3:0
        let crouch=runnerPose == .tagUp ? 2.0:0
        let drive=runnerPose == .accelerate ? 2*(1-arrivalProgress):runnerPose == .decelerate ? -1.5:0
        return CGPoint(x:lean+facing.vector.x*drive,y:bob+crouch)
    }
    func throwingHand(left:Bool) -> CGPoint {
        let side=(left ? -1.0:1)*(facing.back ? 1:-1)
        let rest=CGPoint(x:side*6,y:-12)
        let direction=facing.vector,extended=CGPoint(x:direction.x*11,y:-17+direction.y*4)
        func blend(_ a:CGPoint,_ b:CGPoint,_ t:Double) -> CGPoint {CGPoint(x:a.x+(b.x-a.x)*t,y:a.y+(b.y-a.y)*t)}
        switch stage {
        case .run:return CGPoint(x:side*6+sin(gait)*2,y:-12+cos(gait)*3)
        case .gather:return willThrow ? blend(rest,CGPoint(x:0,y:-15),progress):rest
        case .windup:
            let cocked=CGPoint(x:-direction.x*7+side*2,y:-26)
            return progress<0.55 ? blend(CGPoint(x:0,y:-15),cocked,progress/0.55):blend(cocked,extended,(progress-0.55)/0.45)
        case .release:return extended
        case .followThrough:
            let crossed=CGPoint(x:-direction.x*4,y:-8)
            return progress<0.65 ? blend(extended,crossed,progress/0.65):blend(crossed,rest,(progress-0.65)/0.35)
        default:return rest
        }
    }
    func glove(left:Bool) -> CGPoint {
        let side=(left ? 1.0:-1)*(facing.back ? 1:-1)
        let rest=CGPoint(x:side*7,y:-12)
        let caught=CGPoint(x:airCatch ? side*4:side*7,y:airCatch ? -27:-7)
        switch stage {
        case .catchBall:
            let reach=sin(min(1,progress)*Double.pi/2)
            return CGPoint(x:rest.x+(caught.x-rest.x)*reach,y:rest.y+(caught.y-rest.y)*reach)
        case .gather:
            if willThrow {return CGPoint(x:caught.x*(1-progress),y:caught.y+(-15-caught.y)*progress)}
            if progress<0.5 {return CGPoint(x:caught.x*(1-progress*2),y:caught.y+(-15-caught.y)*progress*2)}
            return CGPoint(x:rest.x*(progress-0.5)*2,y:-15+(rest.y+15)*(progress-0.5)*2)
        case .windup,.release:return CGPoint(x:side*3,y:-15)
        case .followThrough:return CGPoint(x:side*3+(rest.x-side*3)*progress,y:-15+(rest.y+15)*progress)
        case .run:return CGPoint(x:side*7-sin(gait)*2,y:-12-cos(gait)*3)
        default:return rest
        }
    }
}

enum FieldSpriteAnimation {
    struct ThrowEvent {
        let fielder:Int
        let caughtAt:Double
        let releaseAt:Double
        let receivedAt:Double
        let receiver:Int
    }
    static func throwsIn(_ play:MatchDetailedPlay) -> [ThrowEvent] {
        if let error=play.misplay {
            return [.init(fielder:error.recoverer,caughtAt:error.recoveredAt,releaseAt:play.releaseAt,receivedAt:play.ballAt,receiver:play.receiver)]
        }
        var events:[ThrowEvent]=[]
        if play.releaseAt>play.pickupAt {
            events.append(.init(fielder:play.fielder,caughtAt:play.pickupAt,releaseAt:play.releaseAt,
                receivedAt:play.relay?.receiveAt ?? play.ballAt,receiver:play.relay?.fielder ?? play.receiver))
        }
        if let relay=play.relay {events.append(.init(fielder:relay.fielder,caughtAt:relay.receiveAt,releaseAt:relay.releaseAt,receivedAt:play.ballAt,receiver:play.receiver))}
        if let second=play.secondThrow {events.append(.init(fielder:play.receiver,caughtAt:play.ballAt,releaseAt:second.releaseAt,receivedAt:second.ballAt,receiver:second.receiver))}
        return events
    }
    static func travel(_ nodes:[FieldNode],time:Double) -> FieldSpriteMotion {
        var last:FieldFacing = .south
        for (a,b) in zip(nodes,nodes.dropFirst()) where a.point != b.point {
            let direction=FieldFacing.direction(dx:b.point.x-a.point.x,dy:b.point.y-a.point.y)
            if time>=a.at && time<b.at {return .init(facing:direction,stage:.run,gait:time*17)}
            if time>=b.at {last=direction}
        }
        return .init(facing:last,stage:.ready)
    }
    struct RunnerSample {
        var point:FieldPoint
        var motion:FieldSpriteMotion
    }
    static func runner(_ runner:DetailedRunner,play:MatchDetailedPlay,time:Double,reduced:Bool=false) -> RunnerSample {
        let legs=Array(zip(runner.nodes,runner.nodes.dropFirst())).filter {$0.0.point != $0.1.point}
        var result=RunnerSample(point:FieldNode.sample(runner.nodes,at:time),motion:travel(runner.nodes,time:time))
        result.motion.runnerPose = .settled
        guard let first=legs.first else {
            if play.fly?.caught == true && runner.from>0 {
                result.motion.runnerPose = .tagUp
                result.motion.facing = .direction(dx:play.landing.x-result.point.x,dy:play.landing.y-result.point.y)
            }
            return result
        }
        if play.fly?.caught == true && runner.from>0 && time<first.0.at {
            result.motion.runnerPose = .tagUp
            let incoming=play.landing
            result.motion.facing = .direction(dx:incoming.x-result.point.x,dy:incoming.y-result.point.y)
            return result
        }
        for (index,leg) in legs.enumerated() where time>=leg.0.at && time<leg.1.at {
            let elapsed=time-leg.0.at
            result.motion.runnerPose = .stride
            if index == 0 && elapsed<0.32 {
                let p=min(1,elapsed/min(0.32,leg.1.at-leg.0.at))
                result.motion.runnerPose = .accelerate;result.motion.arrivalProgress=p
                result.motion.gait=elapsed*17*(0.4+0.6*p)
                if !reduced {
                    // Ease only the opening stride and rejoin the saved path within 320ms.
                    let delayed=elapsed-0.55*elapsed*pow(1-p,3)
                    result.point=FieldNode.sample(runner.nodes,at:leg.0.at+delayed)
                }
            }
            if index>0 && elapsed<0.16 {
                let previous=legs[index-1]
                let old=FieldFacing.direction(dx:previous.1.point.x-previous.0.point.x,dy:previous.1.point.y-previous.0.point.y)
                result.motion.facing=FieldFacing.turn(from:old,to:result.motion.facing,fraction:elapsed/0.16)
                result.motion.runnerPose = .turn
            }
        }
        let reachesBase=runner.destination>0 && runner.destination<DetailedFieldRules.bases.count && runner.nodes.last?.point == DetailedFieldRules.bases[runner.destination]
        guard reachesBase else {return result}
        let arrival=runner.arrival
        if [2,3].contains(runner.destination) && time>=arrival-0.34 && time<arrival+0.24 {
            result.motion.runnerPose = .slide
            result.motion.arrivalProgress=max(0,min(1,(time-arrival+0.34)/0.58))
            if reduced {result.motion.stage = .ready;result.motion.reducedArrival=true}
        } else if runner.from == 0 && runner.destination == 1 && !runner.out && time>=arrival {
            let window=max(0.001,min(0.4,play.duration-arrival))
            let p=max(0,min(1,(time-arrival)/window))
            result.motion.runnerPose = p<1 ? .decelerate:.settled
            result.motion.stage = p<1 ? .run:.ready
            result.motion.arrivalProgress=p;result.motion.gait=arrival*17+6*p-3*p*p
            if !reduced,let last=legs.last {
                let length=last.0.point.distance(to:last.1.point)
                // First-base overrun is visual only; the next play still starts on its saved bag.
                let overshoot=1.8*(1-pow(1-p,3))
                result.point=FieldPoint(x:result.point.x+(last.1.point.x-last.0.point.x)/length*overshoot,
                                       y:result.point.y+(last.1.point.y-last.0.point.y)/length*overshoot)
            }
        }
        return result
    }
    static func motion(_ play:MatchDetailedPlay,index:Int,time:Double) -> FieldSpriteMotion {
        if let error=FieldMisplayAnimation.motion(play,index:index,time:time) {return error}
        var result=fieldingMotion(play,index:index,time:time)
        // An outgoing pivot owns its gather/windup; do not replace a double-play throw.
        guard ![FieldSpriteStage.windup,.release,.followThrough].contains(result.stage) else {return result}
        var receive:(at:Double,control:Double,force:Bool,runner:Int?)?
        if index == play.receiver && play.targetRunner != nil && play.releaseAt>play.pickupAt {
            receive=(play.ballAt,play.controlAt,play.force,play.targetRunner)
        }
        if let second=play.secondThrow,index == second.receiver {receive=(second.ballAt,second.controlAt,true,0)}
        guard let receive,time>=receive.at-0.12,time<receive.control+0.28 else {return result}
        if receive.force {
            result.baseReceive = .force
            result.chestCatch=true
        } else {
            result.baseReceive = .tag;result.chestCatch=false;result.airCatch=false
            result.stage = .catchBall;result.progress=1
            result.arrivalProgress=max(0,min(1,(time-receive.at)/max(0.12,receive.control+0.28-receive.at)))
            if time>=min(receive.control,receive.at+0.06),let runner=play.runners.first(where:{$0.from == receive.runner}) {
                let at=FieldNode.sample(play.fielders[index],at:time)
                let target=FieldNode.sample(runner.nodes,at:receive.control)
                result.facing = .direction(dx:target.x-at.x,dy:target.y-at.y)
            }
        }
        if time<receive.at {result.receivePose = .reach}
        else if receive.force || time<min(receive.control,receive.at+0.06) {result.receivePose = .secure}
        else if time<receive.control+0.12 {result.receivePose = .tag}
        else {result.receivePose = .recover}
        return result
    }
    private static func fieldingMotion(_ play:MatchDetailedPlay,index:Int,time:Double) -> FieldSpriteMotion {
        let nodes=play.fielders[index],at=FieldNode.sample(nodes,at:time)
        let events=throwsIn(play)
        var motion=travel(nodes,time:time)
        if index == play.fielder, time < play.pickupAt {
            if motion.stage == .ready {
                let incoming = FieldNode.sample(play.ball, at: time)
                let focus = at.distance(to: play.landing) > 1 ? play.landing : incoming
                if at.distance(to: focus) > 0.01 {
                    motion.facing = .direction(dx: focus.x - at.x, dy: focus.y - at.y)
                }
            } else if play.fly != nil {
                // Finish the last running stride before switching to the stationary glove pose.
                if time >= play.pickupAt - 0.32 {
                    let incoming = FieldNode.sample(play.ball, at: max(0, play.pickupAt - 0.32))
                    if at.distance(to: incoming) > 0.01 {
                        let facing = FieldFacing.direction(dx: incoming.x - at.x, dy: incoming.y - at.y)
                        motion.facing = .turn(from: motion.facing, to: facing, fraction: (time - (play.pickupAt - 0.32)) / 0.32)
                    }
                }
                return motion
            }
        }
        if let event=events.first(where:{$0.fielder == index && time >= $0.caughtAt-0.12 && time<=$0.releaseAt+0.38}) {
            let receiver=FieldNode.sample(play.fielders[event.receiver],at:event.receivedAt)
            motion.willThrow=true
            motion.facing=FieldFacing.direction(dx:receiver.x-at.x,dy:receiver.y-at.y)
            let transfer=max(0.001,event.releaseAt-event.caughtAt)
            let catchEnd=event.caughtAt+min(0.10,transfer*0.25)
            let windup=event.releaseAt-min(0.20,transfer*0.50)
            if time<catchEnd {motion.stage = .catchBall;motion.progress=min(1,max(0,(time-event.caughtAt+0.12)/(catchEnd-event.caughtAt+0.12)))}
            else if time<windup {motion.stage = .gather;motion.progress=(time-catchEnd)/max(0.001,windup-catchEnd)}
            else if time<event.releaseAt {motion.stage = .windup;motion.progress=(time-windup)/max(0.001,event.releaseAt-windup)}
            else if time<event.releaseAt+0.08 {motion.stage = .release;motion.progress=(time-event.releaseAt)/0.08}
            else {motion.stage = .followThrough;motion.progress=min(1,(time-event.releaseAt-0.08)/0.30)}
            let incoming=FieldNode.sample(play.ball,at:max(0,event.caughtAt-0.12))
            let catchFacing=FieldFacing.direction(dx:incoming.x-at.x,dy:incoming.y-at.y)
            if motion.stage == .catchBall {motion.facing=catchFacing}
            else if motion.stage == .gather {motion.facing=FieldFacing.turn(from:catchFacing,to:motion.facing,fraction:motion.progress)}
            motion.airCatch=play.misplay == nil && index == play.fielder && play.fly?.caught == true
            motion.chestCatch=play.misplay == nil && index != play.fielder
            motion.relayTransfer=play.misplay == nil && play.relay?.fielder == index && [.gather,.windup].contains(motion.stage)
            return motion
        }
        // Turn toward the incoming ball over the final two strides, before the catch pose.
        // Positions and arrival times remain the saved play's path.
        if motion.stage == .run, index == play.fielder, time >= play.pickupAt - 0.32, time < play.pickupAt - 0.12 {
            let incoming = FieldNode.sample(play.ball, at: max(0, play.pickupAt - 0.12))
            let facing = FieldFacing.direction(dx: incoming.x - at.x, dy: incoming.y - at.y)
            motion.facing = FieldFacing.turn(from: motion.facing, to: facing, fraction: (time - (play.pickupAt - 0.32)) / 0.20)
        }
        let catches=[(play.fielder,play.pickupAt)]+events.map {($0.receiver,$0.receivedAt)}
        if let caught=catches.last(where:{$0.0 == index && time >= $0.1-0.12 && time < $0.1+0.35}) {
            let incoming=FieldNode.sample(play.ball,at:max(0,caught.1-0.12))
            motion.facing=FieldFacing.direction(dx:incoming.x-at.x,dy:incoming.y-at.y)
            motion.stage=time<caught.1+0.10 ? .catchBall:.gather
            motion.progress=time<caught.1+0.10 ? min(1,max(0,(time-caught.1+0.12)/0.22)):min(1,(time-caught.1-0.10)/0.25)
            motion.airCatch=index == play.fielder && play.fly?.caught == true
            motion.chestCatch=index != play.fielder
        }
        if motion.stage == .ready {
            if let last=events.last(where:{$0.fielder == index && time>$0.releaseAt}) {
                let target=FieldNode.sample(play.fielders[last.receiver],at:last.receivedAt)
                motion.facing=FieldFacing.direction(dx:target.x-at.x,dy:target.y-at.y)
            } else if let caught=catches.last(where:{$0.0 == index && time>=$0.1}) {
                let incoming=FieldNode.sample(play.ball,at:max(0,caught.1-0.12))
                motion.facing=FieldFacing.direction(dx:incoming.x-at.x,dy:incoming.y-at.y)
            }
        }
        return motion
    }
    static func ballOffset(_ play:MatchDetailedPlay,time:Double,leftIndex:Int?) -> CGPoint {
        ballContact(play,time:time,leftIndex:leftIndex)?.offset ?? .zero
    }
    static func ballContact(_ play:MatchDetailedPlay,time:Double,leftIndex:Int?) -> (index:Int,offset:CGPoint)? {
        if FieldMisplayAnimation.ballIsLoose(play,time:time) {return nil}
        let events=throwsIn(play)
        let catches=[(play.fielder,play.pickupAt)]+events.map {($0.receiver,$0.receivedAt)}
        let ball=FieldNode.sample(play.ball,at:time)
        for index in play.fielders.indices {
            let at=FieldNode.sample(play.fielders[index],at:time)
            guard ball.distance(to:at)<0.9 else {continue}
            let motion=motion(play,index:index,time:time),left=index == leftIndex
            let active=events.contains {$0.fielder == index && time >= $0.caughtAt && time <= $0.releaseAt+0.0001} || FieldMisplayAnimation.holdsBall(play,index:index,time:time)
            let caught=catches.contains {$0.0 == index && time >= $0.1}
            guard active || caught else {continue}
            var p=motion.glove(left:left)
            if active && motion.ballInThrowingHand {p=motion.throwingHand(left:left)}
            else if active && motion.stage == .gather {
                let hand=motion.throwingHand(left:left)
                p=CGPoint(x:p.x+(hand.x-p.x)*motion.progress,y:p.y+(hand.y-p.y)*motion.progress)
            }
            return (index,CGPoint(x:p.x+motion.bodyOffset.x,y:p.y+motion.bodyOffset.y))
        }
        return nil
    }
}

enum FieldRelayTransfer {
    static func moments(_ play:MatchDetailedPlay) -> [Double] {
        guard play.misplay == nil,let relay=play.relay else {return []}
        let length=relay.releaseAt-relay.receiveAt
        let caught=relay.receiveAt+min(0.10,length*0.25)
        let windup=relay.releaseAt-min(0.20,length*0.50)
        return [caught+(windup-caught)*0.25,caught+(windup-caught)*0.75,windup+(relay.releaseAt-windup)*0.1]
    }
}

// Reads only the saved error/ball/player timeline; never resolves a new play or awards participation.
enum FieldMisplayAnimation {
    struct MissedReception {let fielder:Int;let at:Double}
    static func recoveryStart(_ play:MatchDetailedPlay) -> Double? {
        guard let e=play.misplay else {return nil}
        return play.fielders[e.recoverer].first {$0.at>=e.scatteredAt && $0.point == e.loosePoint}?.at ?? e.recoveredAt
    }
    static func securedAt(_ play:MatchDetailedPlay) -> Double? {
        guard let e=play.misplay else {return nil}
        let windup=play.releaseAt-min(0.20,(play.releaseAt-e.recoveredAt)*0.50)
        return e.recoveredAt+min(0.08,(windup-e.recoveredAt)*0.45)
    }
    static func moments(_ play:MatchDetailedPlay) -> [Double] {
        guard let e=play.misplay else {return []}
        return [e.at-0.08,e.at+0.08,recoveryStart(play),securedAt(play).map {$0+0.001},missedReception(play)?.at]
            .compactMap {$0}.filter {$0>=0 && $0<=play.duration}
    }
    static func missedReception(_ play:MatchDetailedPlay) -> MissedReception? {
        guard let e=play.misplay,e.kind == .throwing else {return nil}
        // Old error JSON has no intended receiver. This is a nearby visual reaction, not a ledger participant.
        let candidates=play.fielders.indices.filter {$0 != e.fielder}
        guard let index=candidates.min(by:{
            FieldNode.sample(play.fielders[$0],at:e.at).distance(to:e.loosePoint)<FieldNode.sample(play.fielders[$1],at:e.at).distance(to:e.loosePoint)
        }) else {return nil}
        let a=FieldNode.sample(play.ball,at:e.at),b=e.loosePoint
        let c=FieldNode.sample(play.fielders[index],at:e.at),d=FieldNode.sample(play.fielders[index],at:e.scatteredAt)
        guard c.distance(to:b)<=14 else {return nil}
        let x=a.x-c.x,y=a.y-c.y,dx=(b.x-a.x)-(d.x-c.x),dy=(b.y-a.y)-(d.y-c.y)
        let length=dx*dx+dy*dy
        let p=length>0 ? max(0,min(1,-(x*dx+y*dy)/length)):1
        guard p>=0.4 else {return nil}
        return MissedReception(fielder:index,at:e.at+(e.scatteredAt-e.at)*p)
    }
    static func motion(_ play:MatchDetailedPlay,index:Int,time:Double) -> FieldSpriteMotion? {
        guard let e=play.misplay else {return nil}
        let at=FieldNode.sample(play.fielders[index],at:time)
        var motion=FieldSpriteAnimation.travel(play.fielders[index],time:time)
        let scoop=recoveryStart(play) ?? e.recoveredAt
        let windup=play.releaseAt-min(0.20,(play.releaseAt-e.recoveredAt)*0.50)
        if index == e.recoverer,time>=scoop,time<windup {
            motion.stage = .gather;motion.progress=0;motion.willThrow=time>=e.recoveredAt
            let secure=securedAt(play) ?? e.recoveredAt
            motion.errorPose=time<secure ? .scoop:.secured
            if motion.errorPose == .secured {
                let target=FieldNode.sample(play.fielders[play.receiver],at:play.ballAt)
                let facing=FieldFacing.direction(dx:target.x-at.x,dy:target.y-at.y)
                motion.facing=FieldFacing.turn(from:motion.facing,to:facing,fraction:min(1,(time-secure)/0.18))
            }
            return motion
        }
        if index == e.fielder,e.kind == .fielding,time>=e.at-0.12,time<e.at+0.26 {
            if time>=e.at,motion.stage == .run {return nil}
            let ball=FieldNode.sample(play.ball,at:time<e.at ? max(0,e.at-0.12):e.scatteredAt)
            motion.facing = .direction(dx:ball.x-at.x,dy:ball.y-at.y)
            motion.stage = .catchBall;motion.progress=1
            let low=e.stage == 0 && play.fly == nil && (play.battedBall?.angle ?? 0)<15
            motion.errorPose=low ? .spill:.reach
            return motion
        }
        if index == e.fielder,e.kind == .throwing,time>=max(play.pickupAt,e.at-0.2),time<e.at+0.30 {
            if time>e.at+0.08,motion.stage == .run {return nil}
            motion.facing = .direction(dx:e.loosePoint.x-at.x,dy:e.loosePoint.y-at.y);motion.willThrow=true
            if time<e.at {motion.stage = .windup;motion.progress=max(0,min(1,(time-e.at+0.2)/0.2))}
            else if time<e.at+0.08 {motion.stage = .release;motion.progress=1}
            else {motion.stage = .followThrough;motion.progress=(time-e.at-0.08)/0.22}
            return motion
        }
        if let miss=missedReception(play),index == miss.fielder,time>=miss.at-0.12,time<miss.at+0.18 {
            motion.stage = .catchBall;motion.progress=1;motion.errorPose = .reach
            let ball=FieldNode.sample(play.ball,at:miss.at)
            motion.facing = .direction(dx:ball.x-at.x,dy:ball.y-at.y)
            return motion
        }
        return nil
    }
    static func ballIsLoose(_ play:MatchDetailedPlay,time:Double) -> Bool {
        guard let e=play.misplay else {return false}
        return time>e.at && time<e.recoveredAt
    }
    static func holdsBall(_ play:MatchDetailedPlay,index:Int,time:Double) -> Bool {
        guard let e=play.misplay else {return false}
        if time == e.at {return index == e.fielder}
        return e.kind == .throwing && index == e.fielder && time>=play.pickupAt && time<e.at
    }
    static func lift(_ play:MatchDetailedPlay,time:Double,height:Double) -> Double? {
        guard let e=play.misplay,time>=e.at,time<=e.recoveredAt else {return nil}
        if time<e.scatteredAt {
            let p=(time-e.at)/max(0.001,e.scatteredAt-e.at)
            return sin(.pi*p)*height*(e.kind == .throwing ? 0.035:0.018)
        }
        let p=min(1,(time-e.scatteredAt)/0.35)
        return max(0,sin(p * .pi * 3))*(1-p)*height*0.007
    }
}

@MainActor enum FieldActorArt {
    // Includes glove, throwing hand and the running lean at every displayed heading.
    static let horizontalReach = 15.0
    static func draw(in context:GraphicsContext,at c:CGPoint,scale u:Double,motion:FieldSpriteMotion,
                     kit:Int,skin:Int,hair:Int,number:Int,left:Bool,selected:Bool,out:Bool=false) {
        let outline=0x102336,pants=0xf1f3e9
        let bob=motion.bodyOffset.y,lean=motion.bodyOffset.x
        func tone(_ color:Int,_ delta:Int) -> Int {
            [0,8,16].reduce(0) {$0 | (max(0,min(255,((color >> $1)&255)+delta)) << $1)}
        }
        let kitDark=tone(kit,-35),kitLight=tone(kit,30),skinDark=tone(skin,-35)
        func box(_ x:Double,_ y:Double,_ w:Double,_ h:Double,_ hex:Int,_ body:Bool=true) {
            let rect=CGRect(x:(c.x+(x+(body ? lean:0))*u).rounded(),y:(c.y+(y+(body ? bob:0))*u).rounded(),width:max(1,(w*u).rounded()),height:max(1,(h*u).rounded()))
            context.fill(Path(rect),with:.color(Color(hex:hex).opacity(out ? 0.38:1)))
        }
        func limb(_ a:CGPoint,_ b:CGPoint,_ color:Int,_ body:Bool=true) {
            let steps=max(1,Int(max(abs(b.x-a.x),abs(b.y-a.y))))
            for i in 0...steps {
                let t=Double(i)/Double(steps),x=a.x+(b.x-a.x)*t,y=a.y+(b.y-a.y)*t
                box(x-2,y-2,5,5,outline,body)
            }
            for i in 0...steps {
                let t=Double(i)/Double(steps),x=a.x+(b.x-a.x)*t,y=a.y+(b.y-a.y)*t
                box(x-1,y-1,3,3,color,body);box(x-1,y-1,1,2,tone(color,18),body)
            }
        }
        let side=motion.facing.side,width=side ? 9.0:motion.facing.diagonal ? 11:12
        box(-9,2,18,3,0x246b39,false);box(-7,3,14,2,0x174b32,false)
        let crouch=max(0,bob)
        for (hip,phase) in [(side ? -2.0:-3.5,0.0),(side ? 2.0:3.5,Double.pi)] {
            let stride=motion.stage == .run ? sin(motion.gait+phase):0
            let foot=CGPoint(x:hip+motion.facing.vector.x*stride*4,y:3+(abs(motion.facing.vector.y)>0.4 ? stride*2:-max(0,stride)*3))
            let knee=CGPoint(x:hip+motion.facing.vector.x*stride,y:-3-max(0,stride)*2+crouch*0.6)
            limb(CGPoint(x:hip,y:-8+crouch),knee,pants,false);limb(knee,foot,pants,false)
            box(knee.x+1,knee.y,1,3,0xa2b6b9,false)
            box(foot.x-2,foot.y-2,4,3,kitDark,false)
            let toe=side && motion.facing.horizontal<0 ? -4.0:-2
            box(foot.x+toe,foot.y+1,6,3,outline,false)
            box(foot.x+toe+1,foot.y+1,4,1,pants,false)
            box(foot.x+toe,foot.y+3,6,1,0x6d8791,false)
        }
        box(-width/2-1,-20,width+2,14,outline)
        box(-width/2-2,-19,width+4,5,outline)
        box(-width/2,-19,width,12,kit)
        box(-width/2-1,-18,width+2,3,kit)
        box(-width/2,-18,2,10,kitLight);box(width/2-2,-17,2,10,kitDark)
        box(-2,-19,4,2,pants);box(-1,-17,1,8,kitDark)
        box(-width/2+2,-8,width-4,1,kitLight)
        box(-width/2,-7,width,2,outline);box(-1,-7,2,1,0xd6bf88)
        if !side {
            context.draw(Text("\(number)").font(.system(size:7*u,weight:.black,design:.monospaced)).foregroundStyle(Color(hex:kit == 0xf0ead9 ? outline:0xf6f2d8).opacity(out ? 0.38:1)),at:CGPoint(x:c.x+lean*u,y:c.y+(-12+bob)*u))
        } else {box(-1,-18,1,9,pants)}
        let hand=motion.throwingHand(left:left),glove=motion.glove(left:left)
        let anatomical=(left ? -1.0:1)*(motion.facing.back ? 1:-1)
        func arm(_ shoulder:CGPoint,_ end:CGPoint) {
            let elbow=CGPoint(x:shoulder.x*0.4+end.x*0.6,y:shoulder.y*0.45+end.y*0.55+1)
            limb(shoulder,elbow,kit);limb(elbow,end,skin)
            box(shoulder.x-1,shoulder.y-1,3,1,pants)
            box(end.x-1,end.y,2,1,skinDark)
        }
        arm(CGPoint(x:anatomical*(width/2+1),y:-18),hand)
        arm(CGPoint(x:-anatomical*(width/2+1),y:-18),glove)
        let headShift=motion.facing.diagonal ? motion.facing.horizontal:0
        func head(_ x:Double,_ y:Double,_ w:Double,_ h:Double,_ hex:Int) {box(x+headShift,y,w,h,hex)}
        head(-5,-32,10,1,outline);head(-7,-31,14,11,outline)
        head(-6,-21,12,3,outline);head(-4,-18,8,1,outline)
        head(-6,-28,12,8,skin);head(-5,-20,10,2,skinDark)
        head(-8,-25,2,4,skinDark);head(6,-25,2,4,skinDark)
        if motion.facing.back {
            head(-6,-27,12,7,hair);head(-5,-21,10,2,tone(hair,20))
            head(-2,-20,4,2,skin)
            if motion.facing.diagonal {head(motion.facing.horizontal*5,-25,2,4,skin)}
        } else {
            head(-5,-27,10,2,hair);head(-5,-25,10,5,skin)
            head(-4,-24,2,3,tone(skin,20))
            let eye=side || motion.facing.diagonal ? motion.facing.horizontal*3:3
            head(eye-1,-25,3,3,0xf7f3e7);head(eye,-25,2,2,outline)
            if !side && !motion.facing.diagonal {head(-4,-25,3,3,0xf7f3e7);head(-3,-25,2,2,outline)}
            head(side || motion.facing.diagonal ? motion.facing.horizontal*6:-1,-23,2,2,skinDark)
            head(-1,-20,3,1,0x9b634a)
        }
        head(-5,-33,10,1,outline);head(-6,-32,12,4,kit)
        head(-4,-32,7,1,kitLight);head(3,-31,3,3,kitDark)
        head(-7,-28,14,2,outline)
        let brim=motion.facing == .north ? -4:motion.facing == .south ? -8:motion.facing.horizontal>0 ? 4:-11
        head(Double(brim),-28,motion.facing == .south ? 16:7,2,kitDark)
        head(Double(brim)+1,-28,motion.facing == .south ? 13:5,1,kitLight)
        if !motion.facing.back && !side {head(-1,-31,2,2,pants)}
        // The glove and fingers are drawn last, at the same anchors used by the ball layer.
        box(hand.x-1,hand.y-1,3,3,skin);box(hand.x,hand.y-1,1,1,tone(skin,20))
        box(glove.x-4,glove.y-3,8,7,outline)
        box(glove.x-3,glove.y-3,6,6,0x8e562d);box(glove.x-2,glove.y-2,4,4,0xb88145)
        box(glove.x-1,glove.y-1,2,3,0x654026);box(glove.x-3,glove.y-2,1,4,0xd5a56b)
        for finger in 0..<3 {box(glove.x-2+Double(finger)*2,glove.y-3,1,2,0xd5a56b)}
        if selected {box(-2,-38,4,2,0xecc66b);box(-1,-36,2,1,0xecc66b)}
    }
}

// Calibrated to the clean backdrop's home, first/third, second and mound landmarks.
// Shared by actors, bases and the ball; it never changes simulation geometry.
enum InplayFieldProjection {
    static func viewport(_ size:CGSize) -> CGRect {
        CGRect(x:size.width*0.025,y:size.height*0.025,width:size.width*0.95,height:size.height*0.95)
    }
    static func point(_ p:FieldPoint,size:CGSize) -> CGPoint {
        let depth=max(-6,p.y),denominator=28+depth,frame=viewport(size)
        return CGPoint(x:frame.minX+frame.width*(0.5+1.16*p.x/denominator),
                       y:frame.minY+frame.height*(0.739-0.59*depth/denominator))
    }
    static func actorScale(_ p:FieldPoint,size:CGSize) -> Double {
        viewport(size).width/310*(1.12-0.36*min(1,max(0,p.y)/80))
    }
    static func facing(_ facing:FieldFacing,at p:FieldPoint,size:CGSize) -> FieldFacing {
        let a=point(p,size:size)
        let b=point(.init(x:p.x+facing.vector.x,y:p.y-facing.vector.y),size:size)
        return .direction(dx:b.x-a.x,dy:a.y-b.y)
    }
    static func motion(_ motion:FieldSpriteMotion,at p:FieldPoint,size:CGSize) -> FieldSpriteMotion {
        var display=motion;display.facing=facing(motion.facing,at:p,size:size);return display
    }
}

@MainActor enum FieldBallPresentation {
    static func handOffset(_ play:MatchDetailedPlay,time:Double,size:CGSize,leftIndex:Int?) -> CGPoint {
        guard let contact=FieldSpriteAnimation.ballContact(play,time:time,leftIndex:leftIndex) else {return .zero}
        let position=FieldNode.sample(play.ball,at:time)
        let index=contact.index
        let scale=InplayFieldProjection.actorScale(position,size:size)
        let motion=InplayFieldProjection.motion(FieldSpriteAnimation.motion(play,index:index,time:time),at:position,size:size)
        let left=index == leftIndex
        var offset=motion.glove(left:left)
        if motion.ballInThrowingHand {offset=motion.throwingHand(left:left)}
        else if motion.stage == .gather && motion.willThrow {
            let hand=motion.throwingHand(left:left)
            offset=CGPoint(x:offset.x+(hand.x-offset.x)*motion.progress,y:offset.y+(hand.y-offset.y)*motion.progress)
        }
        // The saved ball handler owns the visual contact, even if a nearby teammate is closer to the ball.
        if let raster=FieldRasterArt.contact(motion,kind:index == 1 ? "catcher":"fielder",left:left,hand:motion.ballInThrowingHand) {offset=raster}
        return CGPoint(x:(offset.x+motion.bodyOffset.x)*scale,y:(offset.y+motion.bodyOffset.y)*scale)
    }
    static func point(_ play:MatchDetailedPlay,time:Double,size:CGSize,leftIndex:Int?) -> CGPoint {
        let raw=InplayFieldProjection.point(FieldNode.sample(play.ball,at:time),size:size)
        var offset=handOffset(play,time:time,size:size,leftIndex:leftIndex)
        if let segment=zip(play.ball,play.ball.dropFirst()).first(where:{time >= $0.0.at && time < $0.1.at && $0.0.point != $0.1.point}) {
            let a=handOffset(play,time:segment.0.at,size:size,leftIndex:leftIndex)
            let b=handOffset(play,time:segment.1.at,size:size,leftIndex:leftIndex)
            let f=(time-segment.0.at)/max(0.001,segment.1.at-segment.0.at)
            offset=CGPoint(x:a.x+(b.x-a.x)*f,y:a.y+(b.y-a.y)*f)
        }
        return CGPoint(x:raw.x+offset.x,y:raw.y+offset.y-FieldReplayPresentation.lift(play,time:time,height:size.height))
    }
}

// The bundled art contains no players, ball or score; live layers own every moving object.
@MainActor enum InplayStadiumArt {
    static let size=CGSize(width:1024,height:1536)
    static let image=MatchArt.image("inplay-stadium-arcade-v1")

    @MainActor final class UpperArt {
        let image:UIImage
        init(image:UIImage) {self.image=image}
        lazy var texture:SKTexture = {
            let value=SKTexture(image:image);value.filteringMode = .nearest;return value
        }()
    }
    private static let upperArtCache:NSCache<NSString,UpperArt> = {
        let cache=NSCache<NSString,UpperArt>()
        cache.totalCostLimit=6*1024*1024
        return cache
    }()
    static func upperArt(_ venue:StadiumBackdrop) -> UpperArt? {
        let key=venue.imageName as NSString
        if let cached=upperArtCache.object(forKey:key) {return cached}
        guard let url=Bundle.main.url(forResource:venue.imageName,withExtension:"png",subdirectory:"MatchArt"),
              let image=UIImage(contentsOfFile:url.path),image.size == venue.pixelSize else {return nil}
        let art=UpperArt(image:image)
        upperArtCache.setObject(art,forKey:key,cost:Int(venue.pixelSize.width*venue.pixelSize.height)*8)
        return art
    }
    static func frame(for pixels:CGRect,in canvas:CGSize) -> CGRect {
        let viewport=InplayFieldProjection.viewport(canvas),x=viewport.width/size.width,y=viewport.height/size.height
        return CGRect(x:viewport.minX+pixels.minX*x,y:viewport.minY+pixels.minY*y,width:pixels.width*x,height:pixels.height*y)
    }
    static func upperFrame(_ venue:StadiumBackdrop,in canvas:CGSize) -> CGRect {
        frame(for:CGRect(x:0,y:0,width:size.width,height:venue.height),in:canvas)
    }
    static func legacyScoreFrame(in canvas:CGSize,homeRun:Bool) -> CGRect {
        if homeRun {return CGRect(x:canvas.width*0.38,y:canvas.height*0.14,width:canvas.width*0.24,height:canvas.height*0.04)}
        let viewport=InplayFieldProjection.viewport(canvas)
        return CGRect(x:viewport.minX+viewport.width*0.39,y:viewport.minY+viewport.height*0.123,width:viewport.width*0.22,height:viewport.height*0.039)
    }

    struct Scoreboard {
        let venue:StadiumBackdrop
        let frame:CGRect
        var logoFrame:CGRect? {
            guard venue.logoAsset != nil else {return nil}
            let side=min(frame.height*0.80,frame.width*0.25)
            return CGRect(x:frame.minX+frame.width*0.04,y:frame.midY-side/2,width:side,height:side)
        }
        private var textFrame:CGRect {
            guard let logoFrame else {return frame}
            let leading=logoFrame.maxX+frame.width*0.03
            return CGRect(x:leading,y:frame.minY,width:frame.maxX-leading-frame.width*0.04,height:frame.height)
        }
        var namePosition:CGPoint {
            CGPoint(x:venue.compact ? frame.minX+frame.width*0.27:textFrame.midX,
                    y:venue.compact ? frame.midY:frame.minY+frame.height*0.27)
        }
        var scorePosition:CGPoint {
            CGPoint(x:venue.compact ? frame.minX+frame.width*0.73:textFrame.midX,
                    y:venue.compact ? frame.midY:frame.minY+frame.height*0.69)
        }
        var nameFontSize:CGFloat {
            min(frame.height*(venue.compact ? 0.67:0.27),textFrame.width*(venue.compact ? 0.45:0.90)/CGFloat(venue.name.count))
        }
        func scoreFontSize(_ text:String) -> CGFloat {
            min(frame.height*(venue.compact ? 0.75:0.45),textFrame.width*(venue.compact ? 0.45:0.90)/CGFloat(max(1,text.count))*1.5)
        }
        var fill:Color {Color(hex:venue.panel).opacity(0.9)}
        var trim:Color {Color(hex:venue.trim)}
    }
    static func scoreboard(_ venue:StadiumBackdrop,in canvas:CGSize) -> Scoreboard {
        Scoreboard(venue:venue,frame:frame(for:venue.board,in:canvas))
    }
    static func draw(in context:GraphicsContext,size:CGSize,stadium:StadiumIdentity) -> Scoreboard? {
        if let image {context.draw(Image(uiImage:image).interpolation(.none),in:InplayFieldProjection.viewport(size))}
        guard let venue=stadium.backdrop,let upper=upperArt(venue) else {return nil}
        context.draw(Image(uiImage:upper.image).interpolation(.none),in:upperFrame(venue,in:size))
        return scoreboard(venue,in:size)
    }
    static func drawScore(_ text:String,in context:GraphicsContext,size:CGSize,board:Scoreboard?,homeRun:Bool) {
        if let board {
            context.fill(Path(board.frame),with:.color(board.fill))
            context.stroke(Path(board.frame),with:.color(board.trim),lineWidth:1)
            if let logo=board.venue.logoAsset,let logoFrame=board.logoFrame {
                context.draw(Image(logo).interpolation(.none),in:logoFrame)
            }
            context.draw(Text(board.venue.name).font(.system(size:board.nameFontSize,weight:.bold)).foregroundStyle(GameTheme.paper),at:board.namePosition)
            context.draw(Text(text).font(.system(size:board.scoreFontSize(text),weight:.bold,design:.monospaced)).foregroundStyle(GameTheme.paper),at:board.scorePosition)
        } else {
            let frame=legacyScoreFrame(in:size,homeRun:homeRun)
            context.fill(Path(frame),with:.color(homeRun ? GameTheme.navy:Color(hex:0x0b2030)))
            if !homeRun {context.stroke(Path(frame),with:.color(GameTheme.gold),lineWidth:2)}
            let font:Font = .system(size:max(12,size.width*(homeRun ? 0.027:0.028)),weight:homeRun ? .bold:.black,design:.monospaced)
            context.draw(Text(text).font(font).foregroundStyle(GameTheme.paper),at:CGPoint(x:frame.midX,y:frame.midY))
        }
    }
}

@MainActor struct FieldReplaySprites {
    typealias Actor=(point:FieldPoint,motion:FieldSpriteMotion,own:Bool,teamOwn:Bool,number:Int,out:Bool,kind:String)
    let appearance:PlayerAppearance
    let jerseyNumber:Int
    let ownPosition:String?
    let throwingHand:String
    let ownTeamFielding:Bool?
    func actors(_ play:MatchDetailedPlay,time:Double,reduced:Bool,finished:Bool,backupRoutes:[Int:FieldBackupRoutes.Route]? = nil) -> [Actor] {
        let defenseOwn=ownTeamFielding ?? !play.ownBatter
        let routes = backupRoutes ?? FieldBackupRoutes.make(play)
        var actors:[Actor]=[]
        for index in play.fielders.indices {
            let own=defenseOwn && (ownPosition.map {DetailedFieldRules.names[index] == $0} ?? (play.ownDefense && index==play.fielder))
            let backup = routes[index]
            let point = FieldNode.sample(backup?.nodes ?? play.fielders[index], at: time)
            let motion = backup?.motion(at: time) ?? FieldSpriteAnimation.motion(play,index:index,time:time)
            actors.append((point,motion,own,defenseOwn,own ? jerseyNumber:index+1,false,index == 1 ? "catcher":"fielder"))
        }
        for runner in play.runners {
            let display=FieldSpriteAnimation.runner(runner,play:play,time:time,reduced:reduced)
            actors.append((display.point,display.motion,runner.profile.own,!defenseOwn,runner.profile.own ? jerseyNumber:runner.from+10,FieldReplayPresentation.retired(runner,finished:finished),"runner"))
        }
        return actors
    }
    func actors(_ event:MatchHomeRun,time:Double,reduced:Bool) -> [Actor] {
        let ownTeamFielding=ownTeamFielding ?? false
        var actors:[Actor]=[]
        for index in 0..<9 {
            let p=event.defender(index,at:time),previous=event.defender(index,at:max(0,time-0.08)),next=event.defender(index,at:time+0.08)
            let moving=index>=6 && time<event.flight && p.distance(to:next)>0.001
            let motion=FieldSpriteMotion(facing:.direction(dx:next.x-previous.x,dy:next.y-previous.y),stage:moving && !reduced ? .run:.ready,gait:time*12)
            let own=ownTeamFielding && event.ownDefender == index
            actors.append((p,motion,own,ownTeamFielding,own ? jerseyNumber:index+1,false,index == 1 ? "catcher":"fielder"))
        }
        for runner in event.runners where time<=runner.arrival+0.6 || runner.from == 0 {
            let (p,motion)=HomeRunPresentation.runner(runner,time:time,reduced:reduced)
            actors.append((p,motion,runner.profile.own,!ownTeamFielding,runner.profile.own ? jerseyNumber:runner.from+10,false,"runner"))
        }
        return actors
    }
    private struct Selection:Hashable {
        let file:String
        let rect:[Double]
        let own:Bool,teamOwn:Bool,back:Bool,mirrored:Bool,garmentBack:Bool,garmentMirrored:Bool
        let number:Int
    }
    func requests(duration:Double,reduced:Bool,actorsAt:(Double)->[Actor]) async -> [String:FieldRasterArt.Request]? {
        var result:[String:FieldRasterArt.Request]=[:],seen=Set<Selection>()
        let ownKit=appearance.uniformColor,opponent=appearance.opponentUniformColor
        let ownStyle=appearance.uniformStyle,opponentStyle=appearance.opponentUniformStyle
        // Both field canvases use 2:3; perspective direction is independent of pixel resolution.
        let size=CGSize(width:400,height:600)
        let steps=Int(ceil(duration*120))
        #if DEBUG
        var chunkStart=MatchRenderMetrics.begin()
        MatchRenderMetrics.mark("field.plan.begin")
        #endif
        for index in 0...steps {
            guard !Task.isCancelled else {return nil}
            if index%32 == 0 {
                #if DEBUG
                MatchRenderMetrics.end("fieldPlanChunk",started:chunkStart)
                #endif
                // 약 2ms 분량씩 준비하고 실제 표시 큐가 실행될 틈을 둔다.
                do {try await Task.sleep(for:.microseconds(250))} catch {return nil}
                #if DEBUG
                chunkStart=MatchRenderMetrics.begin()
                #endif
            }
            for actor in actorsAt(min(duration,Double(index)/120)) {
                var motion=InplayFieldProjection.motion(actor.motion,at:actor.point,size:size)
                let style=actor.teamOwn ? ownStyle:opponentStyle
                // Include both sides of pose changes even when a short stage falls between samples.
                let poses = motion.stage == .run ? [0.0,1.0] : [0.0,0.25,0.5,0.75,1.0]
                for progress in poses {
                    motion.progress=progress
                    if motion.stage == .run {motion.gait=progress == 0 ? 0 : -.pi/2}
                    for sample in FieldRasterArt.samples(motion,kind:actor.kind,left:actor.own && throwingHand == "left") {
                        let back=motion.facing.back && actor.kind != "catcher"
                        let selection=Selection(file:sample.frame.file,rect:sample.frame.rect,own:actor.own,teamOwn:actor.teamOwn,
                            back:back,mirrored:back && sample.mirrored,garmentBack:style?.pro != nil && back,
                            garmentMirrored:style?.pro != nil && sample.mirrored,number:back ? actor.number:0)
                        guard seen.insert(selection).inserted else {continue}
                        let r=FieldRasterArt.Request(sample:sample,kit:actor.teamOwn ? ownKit:opponent,
                            skin:actor.own ? PlayerAppearance.skinColors[appearance.skin]:0xefbe91,
                            hair:actor.own ? PlayerAppearance.hairColors[appearance.hair]:0x263b48,number:actor.number,back:back,style:style)
                        result[r.key]=r
                    }
                }
            }
        }
        #if DEBUG
        MatchRenderMetrics.end("fieldPlanChunk",started:chunkStart)
        MatchRenderMetrics.mark("field.plan.end")
        #endif
        return result
    }
}

@MainActor final class FieldReplayPreparation {
    let eventID:String
    let backupRoutes: [Int: FieldBackupRoutes.Route]
    private let task:Task<FieldRasterArt.Prepared?,Never>
    private var cancelled=false
    init(replay:InplayReplay,sprites:FieldReplaySprites) {
        eventID=replay.eventID
        let routes = replay.backupRoutes
        backupRoutes = routes
        task=Task(priority:.utility) {
            // 확정 뒤 짧은 묶음으로 준비한다. 각 묶음의 suspension이 표시 작업에 틈을 준다.
            guard let requests=await sprites.requests(duration:replay.duration,reduced:false,actorsAt:{
                replay.actors(sprites,time:$0,reduced:false,finished:false,backupRoutes:routes)
            }),!Task.isCancelled else {return nil}
            return await FieldRasterArt.prepare(requests)
        }
    }
    func images(for eventID:String) async -> FieldRasterArt.Prepared? {
        guard self.eventID==eventID,!cancelled,!Task.isCancelled else {return nil}
        let result=await task.value
        return cancelled || Task.isCancelled ? nil:result
    }
    func cancel() {cancelled=true;task.cancel()}
    deinit {task.cancel()}
}

struct DetailedFieldReplayBoard:View {
    let play:MatchDetailedPlay
    let appearance:PlayerAppearance
    var animated=true
    var jerseyNumber=1
    var ownPosition:String?=nil
    var throwingHand="right"
    var ownTeamFielding:Bool?=nil
    var stadium:StadiumIdentity = .legacy
    var scoreText="IN PLAY"
    var previewTime:Double?=nil
    var reduceMotionOverride:Bool?=nil
    var handoff:FieldContactHandoff?=nil
    var showsContactPoints=false
    var playbackMode:FieldPlaybackMode = .system
    var preparesMotion=false
    var preparation:FieldReplayPreparation?=nil
    var onResolved:@MainActor () -> Void = {}
    let complete:@MainActor () -> Void
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @Environment(\.accessibilityDimFlashingLights) private var dimFlashingLights
    @Environment(\.dynamicTypeSize) private var typeSize
    private var reduced:Bool {playbackMode.reducesMovement(system:systemReduced)}
    private var replay:InplayReplay {.field(play)}
    private var effectsReduced:Bool {dimFlashingLights || (reduceMotionOverride ?? (systemReduced || reduced))}
    @State private var scene:InplayFieldScene?
    @State private var prepared:FieldRasterArt.Prepared?
    @State private var backupRoutes: [Int: FieldBackupRoutes.Route] = [:]
    @State private var preparationDelay=0.0
    @State private var start:Double?
    @State private var resolved=false
    private var sprites:FieldReplaySprites {FieldReplaySprites(appearance:appearance,jerseyNumber:jerseyNumber,ownPosition:ownPosition,throwingHand:throwingHand,ownTeamFielding:ownTeamFielding)}
    private var usesSpriteKit:Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-field-canvas-comparison") {return false}
        #endif
        return true
    }
    private var playbackHandoff:FieldContactHandoff? {handoff?.delayed(by:preparationDelay)}
    private var phaseDates:[Date] {
        guard let start else {return [.now]}
        let elapsed=playbackHandoff?.elapsed(at:start) ?? 0
        let origin=Date(timeIntervalSinceNow:start-ProcessInfo.processInfo.systemUptime)
        return replay.phaseMoments.map {origin.addingTimeInterval(max(0,$0-elapsed)+0.001)}
    }
    var body:some View {
        Group {
            if usesSpriteKit {
                TimelineView(.explicit(phaseDates)) {_ in frame(now:ProcessInfo.processInfo.systemUptime)}
            } else {
                TimelineView(.animation(minimumInterval:reduced ? 0.15:1.0/30,paused:previewTime != nil || !animated || resolved || prepared == nil)) {_ in frame(now:ProcessInfo.processInfo.systemUptime)}
            }
        }
        .task(id:replay.eventID+(animated ? ":live":":still")) {
            let began=ProcessInfo.processInfo.systemUptime
            let playback = replay
            let matchingPreparation = preparation.flatMap { $0.eventID == playback.eventID ? $0 : nil }
            let routes = matchingPreparation?.backupRoutes ?? playback.backupRoutes
            #if DEBUG
            MatchRenderMetrics.mark("requestBegin")
            #endif
            let images:FieldRasterArt.Prepared?
            if let matchingPreparation {images=await matchingPreparation.images(for:playback.eventID)}
            else {
                guard let requests=await sprites.requests(duration:playback.duration,reduced:false,actorsAt:{playback.actors(sprites,time:$0,reduced:false,finished:false,backupRoutes:routes)}) else {return}
                images=await FieldRasterArt.prepare(requests)
            }
            #if DEBUG
            MatchRenderMetrics.mark("requestsReady")
            #endif
            guard let images,!Task.isCancelled else {return}
            #if DEBUG
            MatchRenderMetrics.mark("imagesReady")
            #endif
            if usesSpriteKit {
                let next=InplayFieldScene(replay:playback,sprites:sprites,prepared:images,scoreText:scoreText,stadium:stadium,backupRoutes:routes)
                #if DEBUG
                MatchRenderMetrics.mark("sceneCreated")
                #endif
                await next.preload()
                #if DEBUG
                MatchRenderMetrics.mark("texturesReady")
                #endif
                guard !Task.isCancelled else {return}
                let initialTime=replay.time(elapsed:handoff?.elapsed(at:began) ?? 0,reduced:reduced)
                next.display(time:initialTime,finished:false)
                scene=next
                #if DEBUG
                MatchRenderMetrics.mark("scenePublished")
                #endif
                if animated,previewTime == nil {
                    guard await next.waitForStartup(),!Task.isCancelled else {return}
                }
            }
            backupRoutes=routes;prepared=images;preparationDelay=ProcessInfo.processInfo.systemUptime-began
            #if DEBUG
            MatchRenderMetrics.motionPolicy=MatchRenderMetrics.MotionPolicy(effectiveReduced:reduced,effectsReduced:effectsReduced,swiftUIReduced:systemReduced,uiReduced:UIAccessibility.isReduceMotionEnabled,lowPower:ProcessInfo.processInfo.isLowPowerModeEnabled)
            MatchRenderMetrics.prepared(seconds:preparationDelay,images:images)
            #endif
            start=ProcessInfo.processInfo.systemUptime;resolved=false
            scene?.setClock(start:start!,handoff:playbackHandoff,reduced:reduced)
            guard animated,previewTime == nil else {return}
            let elapsed=playbackHandoff?.elapsed(at:start!) ?? 0
            do {try await Task.sleep(for:.seconds(max(0,replay.playbackSeconds-elapsed)))} catch {return}
            guard !Task.isCancelled else {return}
            resolved=true;onResolved()
            do {try await Task.sleep(for:.seconds(DeliveryPresentation.receipt(reduced:effectsReduced,match:true)))} catch {return}
            if !Task.isCancelled {complete()}
        }
    }
    @ViewBuilder private func frame(now:Double) -> some View {
        let elapsed=FieldReplayPresentation.elapsed(start:start,handoff:playbackHandoff,now:now)
        let time=previewTime.map {max(0,min(play.duration,$0))} ?? (resolved || !animated ? play.duration:replay.time(elapsed:elapsed,reduced:reduced))
        let finished=previewTime.map {$0>=play.duration} ?? (resolved || !animated)
        VStack(spacing:4) {
            Text(finished ? "플레이 완료":FieldReplayPresentation.phase(play,time:time,finished:false)).font(.system(.headline,design:.monospaced,weight:.bold)).foregroundStyle(GameTheme.gold)
                .lineLimit(typeSize.isAccessibilitySize ? nil:2).accessibilityIdentifier("fieldReplayPhase")
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-match-render-performance") {
                Text((InplayFieldScene.isOrdinaryGround(play) ? "일반 땅볼":"기타 플레이")+" · "+(usesSpriteKit ? "SpriteKit":"Canvas"))
                    .font(.system(size:10,design:.monospaced)).lineLimit(1).foregroundStyle(GameTheme.paper).accessibilityIdentifier("fieldRendererName")
            }
            #endif
            GeometryReader {geometry in
                if usesSpriteKit {
                    if let scene {InplayFieldSurface(scene:scene,scoreText:scoreText,finished:finished,reduced:reduced,effectsReduced:effectsReduced,previewTime:previewTime ?? (!animated ? play.duration:nil),preparing:animated && previewTime == nil && start == nil,showsContactPoints:showsContactPoints)}
                    else {InplayPreparationView(stadium:stadium,scoreText:scoreText,homeRun:false)}
                } else {
                    #if DEBUG
                    legacyFrame(geometry:geometry,now:now,time:time,finished:finished)
                    #endif
                }
            }.aspectRatio(2.0/3,contentMode:.fit)
                .accessibilityLabel(finished ? "도트 수비 주루 재생 · "+play.summary:"인플레이 · "+(play.fly == nil ? "땅볼":"공중 타구"))
                .accessibilityValue(finished ? FieldReplayPresentation.errorDetail(play,ownTeamFielding:ownTeamFielding ?? !play.ownBatter) ?? "플레이 완료":"진행 \(Int(min(1,time/max(0.001,play.duration))*100))%")
                .accessibilityIdentifier("fieldReplayCanvas").id("fieldGraphic")
        }.padding(4).background(GameTheme.board).overlay(Rectangle().strokeBorder(GameTheme.boardLine,lineWidth:2))
    }
    #if DEBUG
    private func legacyFrame(geometry:GeometryProxy,now:Double,time:Double,finished:Bool) -> some View {
        let target=time >= (play.secondThrow?.releaseAt ?? .infinity) ? 1:play.targetBase
        return Canvas { context,size in
                    #if DEBUG
                    let measuredAt=MatchRenderMetrics.begin()
                    defer {MatchRenderMetrics.end("field",started:measuredAt)}
                    #endif
                    if preparesMotion && prepared == nil && previewTime == nil {
                        let board=InplayStadiumArt.draw(in:context,size:size,stadium:stadium)
                        if let board {InplayStadiumArt.drawScore(scoreText,in:context,size:size,board:board,homeRun:false)}
                        context.draw(Text("선수 모션 준비 중").font(.headline.monospaced()).foregroundStyle(GameTheme.paper),at:CGPoint(x:size.width/2,y:size.height/2));return
                    }
                    var context=context
                    if let handoff=playbackHandoff {
                        let cut=max(0,min(play.duration,handoff.cutAt-handoff.startedAt))
                        let ball=FieldBallPresentation.point(play,time:cut,size:size,leftIndex:ownTeamFielding == true && throwingHand == "left" ? DetailedFieldRules.names.firstIndex(of:ownPosition ?? ""):nil)
                        let offset=FieldContactPresentation.cameraOffset(handoff,fieldPoint:ball,canvas:geometry.frame(in:.global),now:now,reduced:effectsReduced)
                        context.clip(to:Path(CGRect(origin:.zero,size:size)))
                        context.translateBy(x:offset.x,y:offset.y)
                    }
                    func point(_ p:FieldPoint) -> CGPoint {InplayFieldProjection.point(p,size:size)}
                    let board=InplayStadiumArt.draw(in:context,size:size,stadium:stadium)
                    if InplayStadiumArt.image == nil {
                        context.draw(Text("구장 이미지를 불러오지 못했습니다").foregroundStyle(GameTheme.paper),at:CGPoint(x:size.width/2,y:size.height/4))
                    }
                    InplayStadiumArt.drawScore(scoreText,in:context,size:size,board:board,homeRun:false)
                    if time>=play.pickupAt && play.releaseAt>play.pickupAt {
                        let b=point(DetailedFieldRules.bases[target]),w=max(7,size.width*0.025)
                        context.stroke(Path(ellipseIn:CGRect(x:b.x-w,y:b.y-w/2,width:w*2,height:w)),with:.color(GameTheme.gold.opacity(0.8)),lineWidth:1)
                    }
                    let ownKit=appearance.uniformColor,opponent=appearance.opponentUniformColor
                    let defenseOwn=ownTeamFielding ?? !play.ownBatter
                    let actors=sprites.actors(play,time:time,reduced:reduced,finished:finished,backupRoutes:backupRoutes)
                    for actor in actors.sorted(by:{$0.point.y>$1.point.y}) {
                        let raster=FieldRasterArt.draw(in:context,at:point(actor.point),scale:InplayFieldProjection.actorScale(actor.point,size:size),motion:InplayFieldProjection.motion(actor.motion,at:actor.point,size:size),kind:actor.kind,
                            kit:actor.teamOwn ? ownKit:opponent,skin:actor.own ? PlayerAppearance.skinColors[appearance.skin]:0xefbe91,
                            hair:actor.own ? PlayerAppearance.hairColors[appearance.hair]:0x263b48,number:actor.number,
                            left:actor.own && throwingHand == "left",selected:actor.own,out:actor.out,style:actor.teamOwn ? appearance.uniformStyle:appearance.opponentUniformStyle,prepared:prepared)
                        if !raster {FieldActorArt.draw(in:context,at:point(actor.point),scale:InplayFieldProjection.actorScale(actor.point,size:size),motion:InplayFieldProjection.motion(actor.motion,at:actor.point,size:size),
                            kit:actor.teamOwn ? ownKit:opponent,skin:actor.own ? PlayerAppearance.skinColors[appearance.skin]:0xefbe91,
                            hair:actor.own ? PlayerAppearance.hairColors[appearance.hair]:0x263b48,number:actor.number,
                            left:actor.own && throwingHand == "left",selected:actor.own,out:actor.out)}
                    }
                    let ownIndex=defenseOwn ? play.fielders.indices.first {index in ownPosition.map {DetailedFieldRules.names[index] == $0} ?? (play.ownDefense && index == play.fielder)}:nil
                    let leftIndex=throwingHand == "left" ? ownIndex:nil
                    @MainActor func ballPoint(_ t:Double) -> CGPoint {
                        FieldBallPresentation.point(play,time:t,size:size,leftIndex:leftIndex)
                    }
                    let groundBall=point(FieldNode.sample(play.ball,at:time))
                    context.fill(Path(ellipseIn:CGRect(x:groundBall.x-3,y:groundBall.y-1,width:6,height:2)),with:.color(.black.opacity(0.4)))
                    for i in 1...3 where !effectsReduced && time<Double(play.ball.last?.at ?? 0) {
                        let p=ballPoint(max(0,time-Double(i)*0.04))
                        context.fill(Path(CGRect(x:p.x,y:p.y,width:2,height:2)),with:.color(GameTheme.paper.opacity(0.4)))
                    }
                    if showsContactPoints {
                        for (index,actor) in actors.prefix(play.fielders.count).enumerated() {
                            let at=actor.point
                            let motion=InplayFieldProjection.motion(actor.motion,at:at,size:size)
                            let hand=motion.ballInThrowingHand
                            if let contact=FieldRasterArt.contact(motion,kind:index == 1 ? "catcher":"fielder",left:index == leftIndex,hand:hand) {
                                let scale=InplayFieldProjection.actorScale(at,size:size),base=point(at)
                                let marker=CGPoint(x:base.x+(contact.x+motion.bodyOffset.x)*scale,y:base.y+(contact.y+motion.bodyOffset.y)*scale)
                                context.stroke(Path(ellipseIn:CGRect(x:marker.x-3,y:marker.y-3,width:6,height:6)),with:.color(GameTheme.gold),lineWidth:1)
                            }
                        }
                    }
                    PixelBaseball.draw(in:context,at:ballPoint(time),diameter:max(5,6*InplayFieldProjection.actorScale(FieldNode.sample(play.ball,at:time),size:size)))
                    if finished {
                        let label=FieldReplayPresentation.resultTitle(play)
                        let detail=FieldReplayPresentation.errorDetail(play,ownTeamFielding:defenseOwn)
                        let frame=CGRect(x:size.width*(detail == nil ? 0.18:0.04),y:size.height*0.27,width:size.width*(detail == nil ? 0.64:0.92),height:detail == nil ? 32:78)
                        context.fill(Path(frame),with:.color(GameTheme.board.opacity(0.96)))
                        context.stroke(Path(frame),with:.color(GameTheme.gold),lineWidth:2)
                        context.draw(Text(label).font(.system(size:18,weight:.black,design:.monospaced)).foregroundStyle(GameTheme.paper),at:CGPoint(x:frame.midX,y:detail == nil ? frame.midY:frame.minY+16))
                        if let detail {
                            context.draw(Text(detail).font(.system(size:12,weight:.bold)).foregroundStyle(GameTheme.paper),
                                in:CGRect(x:frame.minX+6,y:frame.minY+32,width:frame.width-12,height:40))
                        }
                    }
                }
    }
    #endif
}

struct FieldReplayDetails: View {
    let play:MatchDetailedPlay
    @State private var expanded=false
    var body: some View {
        DisclosureGroup("플레이 상세",isExpanded:$expanded) {
            let second=play.secondThrow
            if let ball=play.battedBall {
                Text("\(ball.kind.label) · 타구 \(ball.kmh,specifier:"%.1f") km/h · 발사각 \(ball.angle,specifier:"%.1f")°")
                    .font(.subheadline.monospaced()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("fieldBattedBallDetails")
            }
                if let error=play.misplay {
                    Text("실책 \(error.at,specifier:"%.2f")초 → 회수 \(error.recoveredAt,specifier:"%.2f")초 · 추가 \(error.extraBases.values.reduce(0,+))베이스")
                        .font(.subheadline.monospaced()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("fieldReplayMisplayTimes")
                    Text(error.reachedOnError ? "실책 출루 · 안타 제외" : "정상 타격 기록 유지 · 실책 추가 진루 분리")
                        .font(.subheadline).foregroundStyle(GameTheme.boardInk).accessibilityIdentifier("fieldReplayMisplayScoring")
                }
                if let relay=play.relay {
                    Text("중계 \(DetailedFieldRules.names[relay.fielder]) · 수신 \(relay.receiveAt,specifier:"%.2f")초 / 재송구 \(relay.releaseAt,specifier:"%.2f")초")
                        .font(.subheadline.monospaced()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("fieldReplayRelayTimes")
                    Text("직접 \(relay.directAt,specifier:"%.2f")초 → 중계 \(play.controlAt,specifier:"%.2f")초")
                        .font(.subheadline.monospaced()).foregroundStyle(GameTheme.boardInk).accessibilityIdentifier("fieldReplayRouteComparison")
                }
                if let fly=play.fly,play.misplay == nil {
                    Text("공 낙하 \(play.flight,specifier:"%.2f")초 / 포구 준비 \(fly.reachAt,specifier:"%.2f")초 · \(fly.caught ? "포구 성공" : "낙하 후 처리")")
                        .font(.subheadline.monospaced()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("fieldReplayCatchTimes")
                }
                if play.misplay == nil && (play.fly?.caught != true || play.targetRunner != nil) {
                Text("\(play.targetBase == 4 ? "홈" : "\(play.targetBase)루") · 공 \(play.controlAt,specifier:"%.2f")초 / 주자 \(play.runnerAt.map { String(format:"%.2f초",$0) } ?? "진루 완료")")
                    .font(.subheadline.monospaced()).foregroundStyle(GameTheme.boardInk).accessibilityIdentifier("fieldReplayTimes")
                }
                if let second {
                    Text("1루 · 공 \(second.controlAt,specifier:"%.2f")초 / 타자 \(second.runnerAt,specifier:"%.2f")초")
                        .font(.subheadline.monospaced()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("fieldReplaySecondTimes")
                }
        }.font(.subheadline.monospaced()).tint(GameTheme.gold)
            .accessibilityIdentifier("fieldReplayDetails")
    }
}

struct PitcherChangePanel: View {
    let change: PitcherChange
    var finalRuns: Int?
    let appearance: PlayerAppearance
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var entered=false
    var body: some View {
        VStack(alignment:.leading,spacing:6) {
            Text("투수 교체 · 내 등판 종료").font(.headline).foregroundStyle(GameTheme.gold)
            GeometryReader { g in
                ZStack {
                    Rectangle().fill(Color(hex:0x215b44))
                    Path {p in p.move(to:CGPoint(x:16,y:48));p.addLine(to:CGPoint(x:g.size.width-16,y:48))}.stroke(GameTheme.gold,style:StrokeStyle(lineWidth:2,dash:[4,4]))
                    PixelPlayer(appearance:appearance).frame(width:24,height:32).position(x:entered ? 26:g.size.width*0.5,y:38)
                    PixelPlayer(appearance:PlayerAppearance()).frame(width:24,height:32).position(x:entered ? g.size.width*0.5:g.size.width-26,y:38)
                }
            }.frame(height:66).accessibilityLabel("선발 퇴장 후 구원 투수 마운드 입장")
            Text("\(change.half/2+1)회 \(change.half%2 == 0 ? "초":"말") · \(change.outs)아웃 · \(change.reason) · \(change.pitches)구")
                .font(.caption.monospaced()).accessibilityIdentifier("pitcherChangeReason")
            Text("등판 \(change.outsAtExit/3).\(change.outsAtExit%3)이닝 · 강판 시 실점 \(change.runsAtExit)")
                .font(.caption.monospaced())
            if let finalRuns {
                Text("최종 실점 \(finalRuns) · 강판 후 책임 주자 실점 \(max(0,finalRuns-change.runsAtExit))")
                    .font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("pitcherResponsibilityResult")
            }
            Text(change.inheritedBases.isEmpty ? "남긴 주자 없음":"책임 주자 · \(change.inheritedBases.map {"\($0)루"}.joined(separator:" · "))")
                .font(.caption).accessibilityIdentifier("pitcherInheritedBases")
        }.padding(8).frame(maxWidth:.infinity,alignment:.leading).background(GameTheme.boardPanel)
            .overlay(Rectangle().strokeBorder(GameTheme.boardLine,lineWidth:2))
            .onAppear {withAnimation(reduced ? nil:.easeInOut(duration:0.9)){entered=true}}
    }
}

// These intervals affect presentation only; input windows, pitch speed and saved outcomes stay unchanged.
enum DeliveryPresentation {
    static func flight(_ duration: Double, reduced: Bool, role: PlayerRole = .batter) -> Double { duration }
    static func receipt(reduced: Bool, match: Bool = false) -> Double { (reduced ? 0.8 : 1.1) + (match ? 1:0) }
    static func trainingMotion(reduced: Bool) -> Double { reduced ? 0.15 : 0.9 }
    static func trainingRead(reduced: Bool) -> Double { reduced ? 0.8 : 1.1 }
    static func call(_ outcome: String) -> String {
        outcome == "루킹 스트라이크" ? "스트라이크" : outcome
    }
}

struct PitchJudgmentToast: View {
    let title: String
    var detail: String? = nil
    var body: some View {
        VStack(spacing: 3) {
            Text(title).font(.system(.headline, design: .monospaced, weight: .heavy))
            if let detail { Text(detail).font(.caption2.monospaced().bold()) }
        }.foregroundStyle(GameTheme.paper).padding(.horizontal, 14).padding(.vertical, 8)
            .background(GameTheme.board).overlay(Rectangle().strokeBorder(GameTheme.gold, lineWidth: 2))
            .overlay(alignment: .bottom) {
                Rectangle().fill(GameTheme.gold).frame(width: 8, height: 4).offset(y: 4)
            }.fixedSize(horizontal: false, vertical: true)
            .accessibilityElement(children: .combine).accessibilityAddTraits(.updatesFrequently)
            .allowsHitTesting(false)
    }
}

struct PitchLocationBoard: View {
    let result: ManualMatchResult?
    let side: OpponentBatterSide
    @Environment(\.dynamicTypeSize) private var typeSize
    nonisolated static func marker(x: Double, y: Double, size: CGSize) -> CGPoint {
        CGPoint(x: size.width * (0.08 + 0.84 * min(1, max(0, x))),
                y: size.height * (0.08 + 0.84 * min(1, max(0, y))))
    }
    var body: some View {
        VStack(spacing: 3) {
            Text(side.label).foregroundStyle(GameTheme.gold)
            Canvas { context, size in
                let a = Self.marker(x: 0.2, y: 0.2, size: size), b = Self.marker(x: 0.8, y: 0.8, size: size)
                context.stroke(Path(CGRect(x: a.x, y: a.y, width: b.x-a.x, height: b.y-a.y)), with: .color(GameTheme.boardInk), lineWidth: 1)
                for value in [0.4,0.6] {
                    let x = Self.marker(x:value,y:0,size:size).x, y = Self.marker(x:0,y:value,size:size).y
                    var line = Path(); line.move(to:CGPoint(x:x,y:a.y)); line.addLine(to:CGPoint(x:x,y:b.y))
                    line.move(to:CGPoint(x:a.x,y:y)); line.addLine(to:CGPoint(x:b.x,y:y))
                    context.stroke(line,with:.color(GameTheme.boardLine),lineWidth:0.5)
                }
                if let result {
                    let p = Self.marker(x:result.x,y:result.y,size:size)
                    PixelBaseball.draw(in:context,at:p,diameter:8)
                }
            }.aspectRatio(1,contentMode:.fit).accessibilityHidden(true)
            Text(result == nil ? "도착 대기" : "실제 도착 코스")
                .foregroundStyle(GameTheme.boardInk)
        }.font(typeSize.isAccessibilitySize ? .caption2 : .system(size:10,weight:.bold,design:.monospaced))
            .padding(5).background(GameTheme.board.opacity(0.94))
            .overlay(Rectangle().strokeBorder(GameTheme.boardLine))
            .accessibilityElement(children:.ignore)
            .accessibilityLabel("\(side.label) · \(side.mapOnRight ? "오른쪽" : "왼쪽") 코스 보드")
            .accessibilityValue(result.map { "실제 도착 가로 \(Int(($0.x*100).rounded())), 세로 \(Int(($0.y*100).rounded())), \(ManualMatchRules.isStrike(x:$0.x,y:$0.y) ? "존 안" : "존 밖")" } ?? "도착 대기")
            .accessibilityIdentifier("pitchLocationBoard")
            .allowsHitTesting(false)
    }
}

// One code-drawn pixel asset shared by SpriteKit and SwiftUI; transparent corners keep it round.
@MainActor enum PixelBaseball {
    static let rows = ["....oooo....","..oowwwwoo..",".owrwwwwrwo.",".owwrwwrwwwo","owwwwrrwwwwo","owwwwwwwwwwo","owwwwwwwwwwo","owwwwrrwwwwo",".owwrwwrwwwo",".owrwwwwrwo.","..oossssoo..","....oooo...."]
    static let image: UIImage = {
        let format=UIGraphicsImageRendererFormat();format.scale=1;format.opaque=false
        return UIGraphicsImageRenderer(size:CGSize(width:12,height:12),format:format).image {renderer in
            let colors:[Character:UIColor] = ["o":UIColor(red:0.26,green:0.34,blue:0.39,alpha:1),"w":UIColor(red:0.98,green:0.98,blue:0.93,alpha:1),"r":UIColor(red:0.78,green:0.24,blue:0.22,alpha:1),"s":UIColor(red:0.72,green:0.78,blue:0.78,alpha:1)]
            for (y,row) in rows.enumerated() {for (x,key) in row.enumerated() {
                guard let color=colors[key] else {continue};renderer.cgContext.setFillColor(color.cgColor)
                renderer.cgContext.fill(CGRect(x:x,y:y,width:1,height:1))
            }}
        }
    }()
    static let texture: SKTexture = {let t=SKTexture(image:image);t.filteringMode = .nearest;return t}()
    static func draw(in context: GraphicsContext, at point: CGPoint, diameter: CGFloat) {
        let transform=context.transform
        let scaleX=hypot(transform.a,transform.b),scaleY=hypot(transform.c,transform.d)
        let height=scaleY > 0 ? diameter*scaleX/scaleY:diameter
        context.draw(Image(uiImage:image).interpolation(.none),in:CGRect(x:point.x-diameter/2,y:point.y-height/2,width:diameter,height:height))
    }
}

// Presentation version 1 is fixed for persisted home-run inputs; no result or reward mutation here.
enum HomeRunPresentation {
    static func ballPoint(_ event:MatchHomeRun,time:Double,size:CGSize) -> CGPoint {
        let world=event.ball(at:time),point=InplayFieldProjection.point(world,size:size)
        let beyond=max(0,min(1,(hypot(world.x,world.y)-65)/max(1,Double(event.distance)-65)))
        return CGPoint(x:point.x,y:point.y-event.height(at:time)*size.height*0.003-beyond*size.height*0.11)
    }
    static func sourcePoint(_ event:MatchHomeRun,time:Double,origin:CGPoint,size:CGSize) -> CGPoint {
        let start=ballPoint(event,time:0,size:size),point=ballPoint(event,time:max(0,time),size:size)
        return CGPoint(x:origin.x+(point.x-start.x)/size.width,y:origin.y+(point.y-start.y)/size.height)
    }
    static func time(_ event:MatchHomeRun,elapsed:Double,reduced:Bool) -> Double {
        let t=max(0,min(event.duration,elapsed))
        guard reduced else {return t}
        let moments:[Double]=[0,event.flight/2,event.flight,event.duration]+event.runners.flatMap {$0.nodes.map(\.at)}
        return moments.filter {$0<=t}.max() ?? 0
    }
    static func runner(_ runner:DetailedRunner,time:Double,reduced:Bool) -> (FieldPoint,FieldSpriteMotion) {
        let p=FieldNode.sample(runner.nodes,at:time),after=FieldNode.sample(runner.nodes,at:min(runner.arrival,time+0.08))
        let before=FieldNode.sample(runner.nodes,at:max(0,time-0.08))
        let moving=time>=0.45 && time<runner.arrival
        var motion=FieldSpriteMotion(facing:.direction(dx:after.x-before.x,dy:after.y-before.y),stage:moving && !reduced ? .run:.ready,gait:time*12)
        if let at=runner.nodes.dropFirst(2).first(where:{$0.at>=time}),at.at-time<0.25 {motion.runnerPose = .turn}
        return (p,motion)
    }
    static func phase(_ event:MatchHomeRun,time:Double,finished:Bool) -> String {
        finished ? "홈 도착 · 홈런":time<event.flight ? "타구 비행 · 외야 추적":"베이스 일주 중"
    }
}

struct HomeRunReplayBoard:View {
    let event:MatchHomeRun
    let appearance:PlayerAppearance
    var jerseyNumber=1
    var ownPosition:String?=nil
    var throwingHand="right"
    var ownTeamFielding=false
    var stadium:StadiumIdentity = .legacy
    var scoreText="IN PLAY"
    var handoff:FieldContactHandoff?=nil
    var animated=true
    var previewTime:Double?=nil
    var reduceMotionOverride:Bool?=nil
    var playbackMode:FieldPlaybackMode = .system
    var preparesMotion=false
    var preparation:FieldReplayPreparation?=nil
    var playsSound=false
    var onResolved:@MainActor () -> Void = {}
    var complete:@MainActor () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var systemReduced
    @Environment(\.accessibilityDimFlashingLights) private var dimFlashingLights
    private var reduced:Bool {playbackMode.reducesMovement(system:systemReduced)}
    private var replay:InplayReplay {.homeRun(event)}
    private var effectsReduced:Bool {dimFlashingLights || (reduceMotionOverride ?? (systemReduced || reduced))}
    @State private var scene:InplayFieldScene?
    @State private var prepared:FieldRasterArt.Prepared?
    @State private var preparationDelay=0.0
    @State private var start:Double?
    @State private var resolved=false
    private var sprites:FieldReplaySprites {FieldReplaySprites(appearance:appearance,jerseyNumber:jerseyNumber,ownPosition:ownPosition,throwingHand:throwingHand,ownTeamFielding:ownTeamFielding)}
    private var usesSpriteKit:Bool {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-field-canvas-comparison") {return false}
        #endif
        return true
    }
    private var playbackHandoff:FieldContactHandoff? {handoff?.delayed(by:preparationDelay)}
    private var phaseDates:[Date] {
        guard let start else {return [.now]}
        let elapsed=playbackHandoff?.elapsed(at:start) ?? 0
        let origin=Date(timeIntervalSinceNow:start-ProcessInfo.processInfo.systemUptime)
        return replay.phaseMoments.map {origin.addingTimeInterval(max(0,$0-elapsed)+0.001)}
    }
    var body:some View {
        Group {
            if usesSpriteKit {
                TimelineView(.explicit(phaseDates)) {_ in frame(now:ProcessInfo.processInfo.systemUptime)}
            } else {
                TimelineView(.animation(minimumInterval:reduced ? 0.15:1.0/30,paused:previewTime != nil || !animated || resolved || prepared == nil)) {_ in frame(now:ProcessInfo.processInfo.systemUptime)}
            }
        }
        .task(id:replay.eventID+(animated ? ":live":":still")) {
            let began=ProcessInfo.processInfo.systemUptime
            #if DEBUG
            MatchRenderMetrics.mark("requestBegin")
            #endif
            let images:FieldRasterArt.Prepared?
            if let preparation,preparation.eventID==replay.eventID {images=await preparation.images(for:replay.eventID)}
            else {
                guard let requests=await sprites.requests(duration:replay.duration,reduced:false,actorsAt:{replay.actors(sprites,time:$0,reduced:false,finished:false)}) else {return}
                images=await FieldRasterArt.prepare(requests)
            }
            #if DEBUG
            MatchRenderMetrics.mark("requestsReady")
            #endif
            guard let images,!Task.isCancelled else {return}
            #if DEBUG
            MatchRenderMetrics.mark("imagesReady")
            #endif
            if usesSpriteKit {
                let next=InplayFieldScene(replay:replay,sprites:sprites,prepared:images,scoreText:scoreText,stadium:stadium)
                if playsSound,animated,previewTime == nil {
                    next.onHomeRunFenceCrossed={GameSound.shared.play(.crowd)}
                }
                #if DEBUG
                MatchRenderMetrics.mark("sceneCreated")
                #endif
                await next.preload()
                #if DEBUG
                MatchRenderMetrics.mark("texturesReady")
                #endif
                guard !Task.isCancelled else {return}
                let initialTime=replay.time(elapsed:handoff?.elapsed(at:began) ?? 0,reduced:reduced)
                next.display(time:initialTime,finished:false)
                scene=next
                #if DEBUG
                MatchRenderMetrics.mark("scenePublished")
                #endif
                if animated,previewTime == nil {
                    guard await next.waitForStartup(),!Task.isCancelled else {return}
                }
            }
            prepared=images;preparationDelay=ProcessInfo.processInfo.systemUptime-began
            #if DEBUG
            MatchRenderMetrics.motionPolicy=MatchRenderMetrics.MotionPolicy(effectiveReduced:reduced,effectsReduced:effectsReduced,swiftUIReduced:systemReduced,uiReduced:UIAccessibility.isReduceMotionEnabled,lowPower:ProcessInfo.processInfo.isLowPowerModeEnabled)
            MatchRenderMetrics.prepared(seconds:preparationDelay,images:images)
            #endif
            start=ProcessInfo.processInfo.systemUptime;resolved=false
            scene?.setClock(start:start!,handoff:playbackHandoff,reduced:reduced)
            guard animated,previewTime == nil else {return}
            let elapsed=playbackHandoff?.elapsed(at:start!) ?? 0
            do {try await Task.sleep(for:.seconds(max(0,replay.playbackSeconds-elapsed)))} catch {return}
            guard !Task.isCancelled else {return}
            resolved=true;onResolved()
            do {try await Task.sleep(for:.seconds(DeliveryPresentation.receipt(reduced:effectsReduced,match:true)))} catch {return}
            if !Task.isCancelled {complete()}
        }
        .onDisappear {if playsSound {GameSound.shared.stop()}}
    }
    @ViewBuilder private func frame(now:Double) -> some View {
        let elapsed=FieldReplayPresentation.elapsed(start:start,handoff:playbackHandoff,now:now)
        let time=previewTime.map {max(0,min(event.duration,$0))} ?? (resolved || !animated ? event.duration:replay.time(elapsed:elapsed,reduced:reduced))
        let finished=previewTime.map {$0>=event.duration} ?? (resolved || !animated)
        VStack(spacing:8) {
            Text(HomeRunPresentation.phase(event,time:time,finished:finished)).font(.headline.monospaced()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("homeRunPhase")
            GeometryReader {geometry in
                if usesSpriteKit {
                    if let scene {InplayFieldSurface(scene:scene,scoreText:scoreText,finished:finished,reduced:reduced,effectsReduced:effectsReduced,previewTime:previewTime ?? (!animated ? event.duration:nil),preparing:animated && previewTime == nil && start == nil)}
                    else {InplayPreparationView(stadium:stadium,scoreText:scoreText,homeRun:true)}
                } else {
                    #if DEBUG
                    legacyFrame(geometry:geometry,now:now,time:time,finished:finished)
                    #endif
                }
            }.aspectRatio(2.0/3,contentMode:.fit).accessibilityElement(children:.ignore)
                .accessibilityLabel(finished ? "홈런 · \(event.distance)m · \(event.runs)점":"타구 비행과 주자 베이스 일주")
                .accessibilityValue(finished ? "홈 도착 완료":"진행 \(Int(time/event.duration*100))%")
                .accessibilityIdentifier("homeRunCanvas")
            if finished {Text("HOME RUN · \(event.distance)m · \(event.runs)점").font(.headline.monospaced()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("homeRunCelebration")}
        }.padding(4).background(GameTheme.board).overlay(Rectangle().strokeBorder(GameTheme.boardLine,lineWidth:2))
    }
    #if DEBUG
    private func legacyFrame(geometry:GeometryProxy,now:Double,time:Double,finished:Bool) -> some View {
        Canvas {context,size in
                        #if DEBUG
                        let measuredAt=MatchRenderMetrics.begin()
                        defer {MatchRenderMetrics.end("homeRun",started:measuredAt)}
                        #endif
                        if preparesMotion && prepared == nil && previewTime == nil {
                            let board=InplayStadiumArt.draw(in:context,size:size,stadium:stadium)
                            if let board {InplayStadiumArt.drawScore(scoreText,in:context,size:size,board:board,homeRun:true)}
                        context.draw(Text("선수 모션 준비 중").font(.headline.monospaced()).foregroundStyle(GameTheme.paper),at:CGPoint(x:size.width/2,y:size.height/2));return
                        }
                        var context=context
                        if let handoff=playbackHandoff {
                            let cut=max(0,min(event.duration,handoff.cutAt-handoff.startedAt))
                            let offset=FieldContactPresentation.cameraOffset(handoff,fieldPoint:HomeRunPresentation.ballPoint(event,time:cut,size:size),canvas:geometry.frame(in:.global),now:now,reduced:effectsReduced)
                            context.clip(to:Path(CGRect(origin:.zero,size:size)));context.translateBy(x:offset.x,y:offset.y)
                        }
                        let board=InplayStadiumArt.draw(in:context,size:size,stadium:stadium)
                        let ownKit=appearance.uniformColor,opponent=appearance.opponentUniformColor
                        let actors=sprites.actors(event,time:time,reduced:reduced)
                        for actor in actors.sorted(by:{$0.point.y>$1.point.y}) {
                            let (p,motion,own,teamOwn,number,kind)=(actor.point,actor.motion,actor.own,actor.teamOwn,actor.number,actor.kind)
                            _=FieldRasterArt.draw(in:context,at:InplayFieldProjection.point(p,size:size),scale:InplayFieldProjection.actorScale(p,size:size),motion:InplayFieldProjection.motion(motion,at:p,size:size),kind:kind,
                                kit:teamOwn ? ownKit:opponent,skin:own ? PlayerAppearance.skinColors[appearance.skin]:0xefbe91,
                                hair:own ? PlayerAppearance.hairColors[appearance.hair]:0x263b48,number:number,left:own && throwingHand == "left",selected:own,out:false,style:teamOwn ? appearance.uniformStyle:appearance.opponentUniformStyle,prepared:prepared)
                        }
                        InplayStadiumArt.drawScore(scoreText,in:context,size:size,board:board,homeRun:true)
                        if time<=event.flight {
                            let p=HomeRunPresentation.ballPoint(event,time:time,size:size)
                            for i in 1...3 where !effectsReduced {
                                let tail=HomeRunPresentation.ballPoint(event,time:max(0,time-Double(i)*0.04),size:size)
                                context.fill(Path(CGRect(x:tail.x,y:tail.y,width:2,height:2)),with:.color(GameTheme.paper.opacity(0.4)))
                            }
                            let diameter=max(6,size.width*0.016)
                            context.fill(Path(ellipseIn:CGRect(x:p.x-diameter/2-1,y:p.y-diameter/2-1,width:diameter+2,height:diameter+2)),with:.color(GameTheme.navy))
                            PixelBaseball.draw(in:context,at:p,diameter:diameter)
                        }
                        if finished {
                            let banner=CGRect(x:size.width*0.08,y:size.height*0.24,width:size.width*0.84,height:size.height*0.12)
                            context.fill(Path(banner),with:.color(GameTheme.navy.opacity(0.97)))
                            context.stroke(Path(banner),with:.color(GameTheme.gold),lineWidth:3)
                            context.draw(Text("HOME RUN · \(event.distance)m").font(.system(size:max(16,size.width*0.052),weight:.black,design:.monospaced)).foregroundStyle(GameTheme.gold),at:CGPoint(x:banner.midX,y:banner.minY+banner.height*0.36))
                            context.draw(Text("\(event.runs)점 · \(ownTeamFielding ? "상대 팀":"우리 팀") 홈 도착").font(.system(size:max(12,size.width*0.035),weight:.bold)).foregroundStyle(GameTheme.paper),at:CGPoint(x:banner.midX,y:banner.minY+banner.height*0.75))
                        }
                    }
    }
    #endif
}

private struct InplayPreparationView:View {
    let stadium:StadiumIdentity
    let scoreText:String
    let homeRun:Bool
    var body:some View {
        ZStack {
            if stadium.backdrop != nil {
                Canvas {context,size in
                    let board=InplayStadiumArt.draw(in:context,size:size,stadium:stadium)
                    InplayStadiumArt.drawScore(scoreText,in:context,size:size,board:board,homeRun:homeRun)
                }
            } else if let image=InplayStadiumArt.image {
                Image(uiImage:image).resizable().interpolation(.none).scaledToFit()
            }
            Text("선수 모션 준비 중").font(.headline.monospaced()).foregroundStyle(GameTheme.paper).padding(8).background(GameTheme.navy)
        }.frame(maxWidth:.infinity,maxHeight:.infinity)
    }
}

#if DEBUG
/// Tracks NSCache-owned pixel costs, not process/GPU memory. NSCache limits are advisory.
final class FieldCacheMetrics:NSObject,NSCacheDelegate,@unchecked Sendable {
    struct Snapshot:Codable {let hits:Int;let misses:Int;let entries:Int;let bytes:Int;let peakBytes:Int;let generatedBytes:Int;let evictions:Int}
    private let lock=NSLock()
    private var live:[ObjectIdentifier:Int]=[:]
    private var hits=0,misses=0,bytes=0,peak=0,generated=0,evictions=0
    func hit() {lock.withLock {hits+=1}}
    func miss() {lock.withLock {misses+=1}}
    func insert(_ image:UIImage,cost:Int) {
        lock.withLock {live[ObjectIdentifier(image)]=cost;bytes+=cost;generated+=cost;peak=max(peak,bytes)}
    }
    func cache(_ cache:NSCache<AnyObject,AnyObject>,willEvictObject object:Any) {
        lock.withLock {if let cost=live.removeValue(forKey:ObjectIdentifier(object as AnyObject)) {bytes-=cost;evictions+=1}}
    }
    func reset() {lock.withLock {live=[:];hits=0;misses=0;bytes=0;peak=0;generated=0;evictions=0}}
    var snapshot:Snapshot {lock.withLock {Snapshot(hits:hits,misses:misses,entries:live.count,bytes:bytes,peakBytes:peak,generatedBytes:generated,evictions:evictions)}}
}
@MainActor enum MatchRenderMetrics {
    struct Environment:Codable {
        let thermalState:Int
        let lowPower:Bool
        init() {thermalState=ProcessInfo.processInfo.thermalState.rawValue;lowPower=ProcessInfo.processInfo.isLowPowerModeEnabled}
    }
    private static var environmentStart=Environment()
    struct Frame:Codable {let kind:String;let at:Double;let milliseconds:Double;var playbackTime:Double?=nil}
    struct Lifecycle:Codable {let name:String;let at:Double}
    static var lifecycle:[Lifecycle]=[]
    private static let startupLog=OSLog(subsystem:"dev.bm.career.rendering",category:"PointsOfInterest")
    static func mark(_ name:String) {
        guard enabled else {return}
        if lifecycle.count<256 {lifecycle.append(Lifecycle(name:name,at:ProcessInfo.processInfo.systemUptime))}
        os_signpost(.event,log:startupLog,name:"InplayStartup","%{public}@",name as NSString)
    }
    struct Preparation:Codable {let endedAt:Double;let seconds:Double;let images:Int;let bytes:Int}
    struct Memory:Codable {let at:Double;let bytes:UInt64}
    static var memory:[Memory]=[]
    static func footprint()->UInt64? {
        var info=task_vm_info_data_t(),count=mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size/MemoryLayout<integer_t>.size)
        let result=withUnsafeMutablePointer(to:&info) {pointer in
            pointer.withMemoryRebound(to:integer_t.self,capacity:Int(count)) {task_info(mach_task_self_,task_flavor_t(TASK_VM_INFO),$0,&count)}
        }
        return result == KERN_SUCCESS ? info.phys_footprint:nil
    }
    private static func sampleMemory(force:Bool=false) {
        let now=ProcessInfo.processInfo.systemUptime
        guard force || now-(memory.last?.at ?? 0)>=3 else {return}
        if let bytes=footprint() {memory.append(Memory(at:now,bytes:bytes))}
    }
    static var preparations:[Preparation]=[]
    static var preparedHits=0,preparedMisses=0
    static var spriteTextureCount=0,spriteTextureSwaps=0,spriteFallbacks=0
    struct Cadence:Codable {let at:Double;let requested:Int;let scene:String;let time:Double}
    static var cadence:[Cadence]=[]
    static func recordCadence(_ fps:Int,scene:InplayFieldScene) {
        guard enabled else {return}
        cadence.append(Cadence(at:ProcessInfo.processInfo.systemUptime,requested:fps,scene:String(describing:ObjectIdentifier(scene)),time:scene.displayedTime))
        mark("cadence.request.\(fps)")
    }
    struct MotionPolicy:Codable {let effectiveReduced:Bool;let effectsReduced:Bool;let swiftUIReduced:Bool;let uiReduced:Bool;let lowPower:Bool}
    static var motionPolicy:MotionPolicy?
    static var enabled=false
    static var bodyEvaluations:[String:Int]=[:]
    static func bodyEvaluated(_ name:String) {if enabled {bodyEvaluations[name,default:0]+=1}}
    static func prepared(seconds:Double,images:FieldRasterArt.Prepared) {
        guard enabled else {return}
        preparations.append(Preparation(endedAt:ProcessInfo.processInfo.systemUptime,seconds:seconds,images:images.images.count,bytes:images.bytes))
    }
    private static var exportIndex=0
    static func exportLive(role:String) {
        guard enabled else {return}
        struct Report:Encodable {let role:String;let lifecycle:[Lifecycle];let motionPolicy:MotionPolicy?;let preparations:[Preparation];let frames:[Frame];let cadence:[Cadence];let memory:[Memory];let preparedHits:Int;let preparedMisses:Int;let spriteTextureCount:Int;let spriteTextureSwaps:Int;let spriteFallbacks:Int;let bodyEvaluations:[String:Int];let environmentStart:Environment;let environmentEnd:Environment;let drawable:MatchDrawableProbe.Snapshot}
        sampleMemory(force:true)
        let report=Report(role:role,lifecycle:lifecycle,motionPolicy:motionPolicy,preparations:preparations,frames:frames,cadence:cadence,memory:memory,preparedHits:preparedHits,preparedMisses:preparedMisses,spriteTextureCount:spriteTextureCount,spriteTextureSwaps:spriteTextureSwaps,spriteFallbacks:spriteFallbacks,bodyEvaluations:bodyEvaluations,environmentStart:environmentStart,environmentEnd:Environment(),drawable:MatchDrawableProbe.shared.snapshot())
        exportIndex+=1
        if let data=try? JSONEncoder().encode(report) {
            try? data.write(to:FileManager.default.temporaryDirectory.appending(path:"match-live-\(role)-\(exportIndex).json"),options:.atomic)
        }
    }
    private(set) static var frames:[Frame]=[]
    static func begin() -> Double? {enabled ? ProcessInfo.processInfo.systemUptime:nil}
    static func end(_ kind:String,started:Double?,playbackTime:Double?=nil) {
        guard enabled,let started else {return}
        sampleMemory()
        guard frames.count<12_000 else {return}
        frames.append(Frame(kind:kind,at:started,milliseconds:(ProcessInfo.processInfo.systemUptime-started)*1000,playbackTime:playbackTime))
    }
    static func reset() {MatchDrawableProbe.shared.reset();environmentStart=Environment();bodyEvaluations=[:];cadence=[];lifecycle=[];motionPolicy=nil;frames=[];preparations=[];preparedHits=0;preparedMisses=0;spriteTextureCount=0;spriteTextureSwaps=0;spriteFallbacks=0;memory=[];sampleMemory(force:true)}
}
#endif

// Rendering input only. All positions/times/results belong to the saved simulation.
@MainActor enum InplayReplay {
    case field(MatchDetailedPlay), homeRun(MatchHomeRun)
    var backupRoutes: [Int: FieldBackupRoutes.Route] {
        if case .field(let play) = self { return FieldBackupRoutes.make(play) }
        return [:]
    }
    var eventID:String {switch self {case .field(let p):p.eventID;case .homeRun(let h):h.eventID}}
    var duration:Double {switch self {case .field(let p):p.duration;case .homeRun(let h):h.duration}}
    var playbackSeconds:Double {switch self {case .field: max(3,duration);case .homeRun:duration}}
    var phaseMoments:[Double] {
        switch self {
        case .field(let p):FieldReplayPhaseSchedule.moments(p)
        case .homeRun(let h):[0,h.flight,h.duration]
        }
    }
    func time(elapsed:Double,reduced:Bool) -> Double {
        switch self {
        case .field(let p):FieldReplayPresentation.time(p,elapsed:elapsed,reduced:reduced,animated:true)
        case .homeRun(let h):HomeRunPresentation.time(h,elapsed:elapsed,reduced:reduced)
        }
    }
    func actors(_ sprites:FieldReplaySprites,time:Double,reduced:Bool,finished:Bool,backupRoutes:[Int:FieldBackupRoutes.Route]? = nil) -> [FieldReplaySprites.Actor] {
        switch self {
        case .field(let p):sprites.actors(p,time:time,reduced:reduced,finished:finished,backupRoutes:backupRoutes)
        case .homeRun(let h):sprites.actors(h,time:time,reduced:reduced)
        }
    }
    func ballPoint(time:Double,size:CGSize,leftIndex:Int?) -> CGPoint {
        switch self {
        case .field(let p):FieldBallPresentation.point(p,time:time,size:size,leftIndex:leftIndex)
        case .homeRun(let h):HomeRunPresentation.ballPoint(h,time:time,size:size)
        }
    }
}

// Finish mounting/render setup before starting the saved movement clock.
// Two settled frame intervals give initial rendering time to settle, not a GPU fence;
// a six-frame budget prevents a slow device from holding the start indefinitely.
struct InplayStartupReadiness {
    private(set) var frameCount=0
    private(set) var settledIntervals=0
    private(set) var isReady=false
    private var lastFrame:Double?
    mutating func observe(at time:Double) {
        guard !isReady else {return}
        if let lastFrame {settledIntervals = time>lastFrame && time-lastFrame<=1.0/20+0.000001 ? settledIntervals+1:0}
        lastFrame=time;frameCount+=1
        isReady=settledIntervals>=2 || frameCount>=6
    }
}

@MainActor final class InplayFieldScene:SKScene {
    static let fieldSize=CGSize(width:400,height:600)
    static func isOrdinaryGround(_ play:MatchDetailedPlay) -> Bool {
        play.fly == nil && play.secondThrow == nil && play.relay == nil && play.misplay == nil && (play.battedBall == nil || play.battedBall?.kind == .ground)
    }
    @MainActor private final class ActorNode {
        let root=SKNode(),body=SKSpriteNode(),shadow=SKShapeNode(ellipseOf:CGSize(width:14,height:3)),selection=SKShapeNode(ellipseOf:CGSize(width:16,height:4))
        let dust=(0..<3).map {_ in SKSpriteNode(color:UIColor(red:0.76,green:0.60,blue:0.38,alpha:1),size:CGSize(width:2,height:1))}
        var textureKey:String?
        #if DEBUG
        let contact=SKShapeNode(circleOfRadius:3)
        #endif
        init() {
            shadow.fillColor=UIColor.black.withAlphaComponent(0.25);shadow.strokeColor = .clear;shadow.position.y = -0.5
            selection.fillColor = .clear;selection.strokeColor=UIColor(GameTheme.gold);selection.lineWidth=1
            shadow.zPosition = -3;selection.zPosition = -2
            root.addChild(shadow);root.addChild(selection)
            for node in dust {node.zPosition = -1;node.anchorPoint=CGPoint(x:0,y:1);root.addChild(node)}
            root.addChild(body)
            #if DEBUG
            contact.fillColor = .clear;contact.strokeColor=UIColor(GameTheme.gold);contact.lineWidth=1;contact.zPosition=3;contact.isHidden=true;root.addChild(contact)
            #endif
        }
    }
    private let replay:InplayReplay,sprites:FieldReplaySprites,prepared:FieldRasterArt.Prepared
    private let backupRoutes: [Int: FieldBackupRoutes.Route]
    private let content=SKNode(),score=SKLabelNode(fontNamed:"Menlo-Bold")
    private let target=SKShapeNode(ellipseOf:CGSize(width:20,height:10))
    private let ball=SKSpriteNode(texture:PixelBaseball.texture),ballShadow=SKShapeNode(ellipseOf:CGSize(width:6,height:2))
    private let trail=(0..<3).map {_ in SKSpriteNode(color:UIColor(GameTheme.paper).withAlphaComponent(0.4),size:CGSize(width:2,height:2))}
    private let result=SKNode()
    private let stadium:StadiumIdentity
    private var venueScoreboard:InplayStadiumArt.Scoreboard?
    private var stadiumDress:StadiumSceneDress?
    private var actors:[ActorNode]=[]
    private var textures:[String:SKTexture]=[:]
    private var started=0.0,handoff:FieldContactHandoff?
    var onHomeRunFenceCrossed: (@MainActor () -> Void)?
    private var fenceSignaled=false
    private var reduced=false,effectsReduced=false,finished=false
    private var previewTime:Double?
    private var startup=InplayStartupReadiness()
    private var startupWaiter:CheckedContinuation<Bool,Never>?
    func waitForStartup() async -> Bool {
        await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                if Task.isCancelled {continuation.resume(returning:false)}
                else if startup.isReady {continuation.resume(returning:true)}
                else {startupWaiter=continuation}
            }
        } onCancel: {
            Task {@MainActor [weak self] in self?.cancelStartup()}
        }
    }
    private func cancelStartup() {startupWaiter?.resume(returning:false);startupWaiter=nil}
    override func didFinishUpdate() {
        #if DEBUG
        if diagnosticUpdates<=4 {MatchRenderMetrics.mark("frameEnd.\(diagnosticUpdates)")}
        #endif
        guard started == 0,startupWaiter != nil else {return}
        startup.observe(at:ProcessInfo.processInfo.systemUptime)
        if startup.isReady {
            #if DEBUG
            MatchRenderMetrics.mark(startup.settledIntervals>=2 ? "rendererReady.settled":"rendererReady.frameBudget")
            #endif
            startupWaiter?.resume(returning:true);startupWaiter=nil
        }
    }
    #if DEBUG
    private var showsContactPoints=false
    private var diagnosticUpdates=0
    override func didMove(to view:SKView) {
        MatchDrawableProbe.shared.register(view,surface:"field")
        MatchRenderMetrics.mark("sceneAttached")
    }
    func setContactPoints(_ value:Bool) {showsContactPoints=value;display(time:displayedTime,finished:finished)}
    #endif
    var canvasFrame:CGRect = .zero
    private(set) var displayedTime=0.0
    private(set) var textureChanges=0
    private(set) var fallbackTextures=0
    convenience init(play:MatchDetailedPlay,sprites:FieldReplaySprites,prepared:FieldRasterArt.Prepared,scoreText:String,stadium:StadiumIdentity = .legacy) {
        self.init(replay:.field(play),sprites:sprites,prepared:prepared,scoreText:scoreText,stadium:stadium)
    }
    convenience init(event:MatchHomeRun,sprites:FieldReplaySprites,prepared:FieldRasterArt.Prepared,scoreText:String,stadium:StadiumIdentity = .legacy) {
        self.init(replay:.homeRun(event),sprites:sprites,prepared:prepared,scoreText:scoreText,stadium:stadium)
    }
    init(replay:InplayReplay,sprites:FieldReplaySprites,prepared:FieldRasterArt.Prepared,scoreText:String,stadium:StadiumIdentity = .legacy,
         backupRoutes:[Int:FieldBackupRoutes.Route]? = nil) {
        self.replay=replay;self.sprites=sprites;self.prepared=prepared;self.stadium=stadium
        self.backupRoutes=backupRoutes ?? replay.backupRoutes
        super.init(size:Self.fieldSize)
        scaleMode = .aspectFit;backgroundColor=UIColor(GameTheme.board);addChild(content)
        if let image=InplayStadiumArt.image {
            let texture=SKTexture(image:image);texture.filteringMode = .nearest
            addBackdrop(texture,frame:InplayFieldProjection.viewport(size),depth:-1000,name:"inplay-field-base")
        }
        if let venue=stadium.backdrop,let upper=InplayStadiumArt.upperArt(venue) {
            addBackdrop(upper.texture,frame:InplayStadiumArt.upperFrame(venue,in:size),depth:-999,name:venue.imageName)
            venueScoreboard=InplayStadiumArt.scoreboard(venue,in:size)
        }
        let dress=StadiumSceneDress(stadium:stadium,size:size,camera:.field,hasVenueBackdrop:venueScoreboard != nil);dress.zPosition = 10;content.addChild(dress);stadiumDress=dress
        let isHomeRun:Bool
        switch replay {case .field:isHomeRun=false;case .homeRun:isHomeRun=true}
        let scoreFrame=venueScoreboard?.frame ?? InplayStadiumArt.legacyScoreFrame(in:size,homeRun:isHomeRun)
        let board=SKShapeNode(rectOf:scoreFrame.size)
        board.name="inplay-scoreboard"
        board.position=convertPoint(CGPoint(x:scoreFrame.midX,y:scoreFrame.midY))
        board.fillColor=UIColor(venueScoreboard?.fill ?? Color(hex:stadium.theme.panel))
        board.strokeColor=UIColor(venueScoreboard?.trim ?? Color(hex:stadium.theme.trim))
        board.lineWidth=venueScoreboard == nil ? 2:1
        content.addChild(board)
        if let venueScoreboard {
            let name=SKLabelNode(fontNamed:"AppleSDGothicNeo-Bold")
            name.name=venueScoreboard.venue.logoAsset == nil ? "inplay-school-name":"inplay-club-name"
            name.text=venueScoreboard.venue.name
            name.fontSize=venueScoreboard.nameFontSize;name.fontColor=UIColor(GameTheme.paper);name.verticalAlignmentMode = .center
            name.position=convertPoint(venueScoreboard.namePosition);name.zPosition=1;content.addChild(name)
            if let asset=venueScoreboard.venue.logoAsset,let frame=venueScoreboard.logoFrame {
                let logo=SKSpriteNode(imageNamed:asset)
                logo.name="inplay-club-logo";logo.size=frame.size
                logo.texture?.filteringMode = .nearest
                logo.position=convertPoint(CGPoint(x:frame.midX,y:frame.midY));logo.zPosition=1;content.addChild(logo)
            }
            score.position=convertPoint(venueScoreboard.scorePosition)
        } else {
            score.position=board.position
        }
        score.name="inplay-score";score.fontSize=max(12,size.width*0.028);score.fontColor=UIColor(GameTheme.paper);score.verticalAlignmentMode = .center;score.zPosition=1;content.addChild(score);setScore(scoreText)
        target.strokeColor=UIColor(GameTheme.gold).withAlphaComponent(0.8);target.lineWidth=1;target.zPosition=2;content.addChild(target)
        for _ in replay.actors(sprites,time:0,reduced:false,finished:false,backupRoutes:self.backupRoutes) {let node=ActorNode();actors.append(node);content.addChild(node.root)}
        ballShadow.fillColor=UIColor.black.withAlphaComponent(0.4);ballShadow.strokeColor = .clear;ballShadow.zPosition=1900;content.addChild(ballShadow)
        for node in trail {node.zPosition=1999;content.addChild(node)}
        ball.zPosition=2000;content.addChild(ball);configureResult();result.name="finalPlayResult";result.zPosition=3000;result.isHidden=true;content.addChild(result)
    }
    required init?(coder:NSCoder) {fatalError("init(coder:) has not been implemented")}
    private func addBackdrop(_ texture:SKTexture,frame:CGRect,depth:CGFloat,name:String) {
        let backdrop=SKSpriteNode(texture:texture)
        backdrop.name=name;backdrop.position=convertPoint(CGPoint(x:frame.midX,y:frame.midY))
        backdrop.size=frame.size;backdrop.zPosition=depth;content.addChild(backdrop)
    }
    private func configureResult() {
        let frame:CGRect,title:String,detail:String?,home:Bool
        switch replay {
        case .field(let p):
            let doublePlay=p.secondThrow?.out == true
            detail=doublePlay ? "2루 아웃 → 1루 아웃" : FieldReplayPresentation.errorDetail(p,ownTeamFielding:sprites.ownTeamFielding ?? !p.ownBatter)
            frame=CGRect(x:size.width*(detail == nil ? 0.18:0.04),y:size.height*0.27,width:size.width*(detail == nil ? 0.64:0.92),height:detail == nil ? 32:78)
            title=doublePlay ? "DOUBLE PLAY · 병살" : FieldReplayPresentation.resultTitle(p);home=false
        case .homeRun(let h):
            frame=CGRect(x:size.width*0.08,y:size.height*0.24,width:size.width*0.84,height:size.height*0.12)
            title="HOME RUN · \(h.distance)m";detail="\(h.runs)점 · \(sprites.ownTeamFielding == true ? "상대 팀":"우리 팀") 홈 도착";home=true
        }
        let panel=SKShapeNode(rectOf:frame.size);panel.position=convertPoint(CGPoint(x:frame.midX,y:frame.midY));panel.fillColor=UIColor(Color(hex:stadium.panelColor));panel.strokeColor=UIColor(Color(hex:stadium.trimColor));panel.lineWidth=home ? 3:2;result.addChild(panel)
        let label=SKLabelNode(fontNamed:"Menlo-Bold");label.text=title;label.fontSize=home ? max(16,size.width*0.052):18;label.fontColor=UIColor(home ? GameTheme.gold:GameTheme.paper);label.verticalAlignmentMode = .center
        label.position=convertPoint(CGPoint(x:frame.midX,y:detail == nil ? frame.midY:frame.minY+(home ? frame.height*0.36:16)));label.zPosition=1;result.addChild(label)
        if let detail {
            let note=SKLabelNode(fontNamed:"Menlo-Bold");note.text=detail;note.fontSize=home ? max(12,size.width*0.035):12;note.fontColor=UIColor(GameTheme.paper);note.verticalAlignmentMode = .center;note.numberOfLines=0;note.preferredMaxLayoutWidth=frame.width-12
            note.position=convertPoint(CGPoint(x:frame.midX,y:home ? frame.minY+frame.height*0.75:frame.minY+50));note.zPosition=1;result.addChild(note)
        }
    }
    func preload() async {
        for (key,image) in prepared.images {let texture=SKTexture(image:image);texture.filteringMode = .nearest;textures[key]=texture}
        let values=Array(textures.values)+content.children.compactMap {($0 as? SKSpriteNode)?.texture}
        #if DEBUG
        if MatchRenderMetrics.enabled {MatchRenderMetrics.spriteTextureCount=values.count}
        #endif
        await withCheckedContinuation {continuation in SKTexture.preload(values) {continuation.resume()}}
        display(time:displayedTime,finished:finished)
    }
    func setClock(start:Double,handoff:FieldContactHandoff?,reduced:Bool) {
        started=start;self.handoff=handoff;self.reduced=reduced
        #if DEBUG
        MatchRenderMetrics.mark("clockStarted")
        #endif
    }
    func setReduced(_ value:Bool) {reduced=value}
    func setEffectsReduced(_ value:Bool) {
        guard effectsReduced != value else {return}
        effectsReduced=value
        if value {content.position = .zero;stadiumDress?.reduceEffects()}
        display(time:displayedTime,finished:finished)
    }
    func setScore(_ text:String) {
        score.text=text
        if let venueScoreboard {score.fontSize=venueScoreboard.scoreFontSize(text)}
    }
    func setFinished(_ value:Bool) {finished=value;display(time:previewTime ?? (value ? replay.duration:displayedTime),finished:value)}
    func setPreviewTime(_ value:Double?) {
        previewTime=value
        if let value {display(time:max(0,min(replay.duration,value)),finished:finished || value>=replay.duration)}
    }
    private func convertPoint(_ point:CGPoint) -> CGPoint {CGPoint(x:point.x,y:size.height-point.y)}
    override func update(_ currentTime:TimeInterval) {
        #if DEBUG
        diagnosticUpdates+=1
        if diagnosticUpdates<=4 {MatchRenderMetrics.mark("update.\(diagnosticUpdates)")}
        #endif
        guard started>0,!finished,previewTime == nil else {return}
        #if DEBUG
        let measured=MatchRenderMetrics.begin()
        defer {MatchRenderMetrics.end(replay.metricKind,started:measured,playbackTime:displayedTime)}
        #endif
        let now=ProcessInfo.processInfo.systemUptime
        let elapsed=FieldReplayPresentation.elapsed(start:started,handoff:handoff,now:now)
        display(time:replay.time(elapsed:elapsed,reduced:reduced),finished:false)
        emitHomeRunFeedbackIfNeeded(time:displayedTime)
        if let handoff,canvasFrame.width>0,canvasFrame.height>0 {
            let point=replay.ballPoint(time:max(0,handoff.cutAt-handoff.startedAt),size:canvasFrame.size,leftIndex:leftIndex)
            let offset=FieldContactPresentation.cameraOffset(handoff,fieldPoint:point,canvas:canvasFrame,now:now,reduced:effectsReduced)
            content.position=CGPoint(x:offset.x*size.width/canvasFrame.width,y:-offset.y*size.height/canvasFrame.height)
        }
    }
    func emitHomeRunFeedbackIfNeeded(time:Double) {
        guard started>0,previewTime == nil,!finished,!fenceSignaled,
              case .homeRun(let event)=replay,time>=event.flight else {return}
        fenceSignaled=true;onHomeRunFenceCrossed?()
    }
    private var leftIndex:Int? {
        guard case .field(let play)=replay,sprites.throwingHand == "left",sprites.ownTeamFielding ?? !play.ownBatter else {return nil}
        return play.fielders.indices.first {index in sprites.ownPosition.map {DetailedFieldRules.names[index] == $0} ?? (play.ownDefense && index == play.fielder)}
    }
    func display(time:Double,finished:Bool) {
        displayedTime=time
        let samples=replay.actors(sprites,time:time,reduced:reduced,finished:finished,backupRoutes:backupRoutes)
        updateActors(samples)
        let ballVisible:Bool,trailEnd:Double
        switch replay {
        case .field(let play):
            let targetBase=time >= (play.secondThrow?.releaseAt ?? .infinity) ? 1:play.targetBase
            target.isHidden=time<play.pickupAt || play.releaseAt<=play.pickupAt
            target.position=convertPoint(InplayFieldProjection.point(DetailedFieldRules.bases[targetBase],size:size))
            let ground=InplayFieldProjection.point(FieldNode.sample(play.ball,at:time),size:size)
            ballShadow.isHidden=false;ballShadow.position=convertPoint(ground)
            let diameter=max(5,6*InplayFieldProjection.actorScale(FieldNode.sample(play.ball,at:time),size:size));ball.size=CGSize(width:diameter,height:diameter)
            ballVisible=true;trailEnd=play.ball.last?.at ?? 0
        case .homeRun(let event):
            target.isHidden=true;ballShadow.isHidden=true
            let diameter=max(6,size.width*0.016);ball.size=CGSize(width:diameter,height:diameter)
            ballVisible=time<=event.flight;trailEnd=event.flight
            if time>=event.flight {stadiumDress?.celebrate(.homeRun,reduced:effectsReduced)}
        }
        ball.isHidden = !ballVisible;ball.position=convertPoint(replay.ballPoint(time:time,size:size,leftIndex:leftIndex))
        for (index,node) in trail.enumerated() {
            node.isHidden=effectsReduced || time>=trailEnd
            let p=replay.ballPoint(time:max(0,time-Double(index+1)*0.04),size:size,leftIndex:leftIndex);node.position=convertPoint(CGPoint(x:p.x+1,y:p.y+1))
        }
        result.isHidden = !finished
        if finished {
            switch replay {
            case .homeRun:stadiumDress?.celebrate(.homeRun,reduced:effectsReduced)
            case .field(let p):if p.secondThrow?.out == true {stadiumDress?.celebrate(.doublePlay,reduced:effectsReduced)}
            }
        }
    }
    private func updateActors(_ samples:[FieldReplaySprites.Actor]) {
        let ownKit=sprites.appearance.uniformColor
        let opponentKit=sprites.appearance.opponentUniformColor
        let ownStyle=sprites.appearance.uniformStyle,opponentStyle=sprites.appearance.opponentUniformStyle
        for (index,node) in actors.enumerated() {node.root.isHidden = index >= samples.count}
        for (index,actor) in samples.enumerated() {
            let node=actors[index],scale=InplayFieldProjection.actorScale(actor.point,size:size)
            let motion=InplayFieldProjection.motion(actor.motion,at:actor.point,size:size)
            node.root.position=convertPoint(InplayFieldProjection.point(actor.point,size:size));node.root.zPosition=1000-actor.point.y+Double(index)*0.0001;node.root.alpha=actor.out ? 0.38:1
            node.shadow.setScale(scale);node.selection.setScale(scale);node.selection.isHidden = !actor.own
            let left=actor.own && sprites.throwingHand == "left"
            if let sample=FieldRasterArt.samples(motion,kind:actor.kind,left:left).first {
                let back=motion.facing.back && actor.kind != "catcher"
                let request=FieldRasterArt.Request(sample:sample,kit:actor.teamOwn ? ownKit:opponentKit,skin:actor.own ? PlayerAppearance.skinColors[sprites.appearance.skin]:0xefbe91,hair:actor.own ? PlayerAppearance.hairColors[sprites.appearance.hair]:0x263b48,number:actor.number,back:back,style:actor.teamOwn ? ownStyle:opponentStyle)
                if node.textureKey != request.key {
                    if textures[request.key] == nil,let image=FieldRasterArt.image(sample,kit:request.kit,skin:request.skin,hair:request.hair,number:actor.number,back:back,style:request.style) {let texture=SKTexture(image:image);texture.filteringMode = .nearest;textures[request.key]=texture;fallbackTextures+=1}
                    node.body.texture=textures[request.key];node.textureKey=request.key;textureChanges+=1
                    #if DEBUG
                    if MatchRenderMetrics.enabled {MatchRenderMetrics.spriteTextureSwaps+=1;MatchRenderMetrics.spriteFallbacks=fallbackTextures}
                    #endif
                }
                let f=sample.frame,u=sample.unit*scale
                node.body.anchorPoint=CGPoint(x:f.pivot[0]/f.rect[2],y:1-f.pivot[1]/f.rect[3]);node.body.size=CGSize(width:f.rect[2]*u,height:f.rect[3]*u)
                node.body.position=CGPoint(x:motion.bodyOffset.x*scale,y:-motion.bodyOffset.y*scale);node.body.xScale=sample.mirrored ? -1:1;node.body.yScale=actor.kind == "runner" && motion.runnerPose == .tagUp ? 0.9:1
            }
            #if DEBUG
            node.contact.isHidden=true
            if showsContactPoints,actor.kind != "runner",let contact=FieldRasterArt.contact(motion,kind:actor.kind,left:left,hand:motion.ballInThrowingHand) {
                node.contact.position=CGPoint(x:(contact.x+motion.bodyOffset.x)*scale,y:-(contact.y+motion.bodyOffset.y)*scale);node.contact.isHidden=false
            }
            #endif
            for (i,dust) in node.dust.enumerated() {
                dust.isHidden = effectsReduced || actor.kind != "runner" || ![.slide,.decelerate].contains(motion.runnerPose)
                dust.position=CGPoint(x:-motion.facing.vector.x*Double(i+1)*3*scale,y:-Double(i%2)*scale);dust.setScale(scale);dust.alpha=(1-motion.arrivalProgress)*0.55
            }
        }

    }
    #if DEBUG
    var visibleActorCount:Int {actors.filter {!$0.root.isHidden}.count}
    var actorIDs:[ObjectIdentifier] {actors.map {ObjectIdentifier($0.root)}}
    var actorPositions:[CGPoint] {actors.map {$0.root.position}}
    var ballPosition:CGPoint {ball.position}
    var ballVisible:Bool {!ball.isHidden}
    var resultVisible:Bool {!result.isHidden}
    var effectsVisible:Bool {trail.contains {!$0.isHidden} || actors.contains {$0.dust.contains {!$0.isHidden}}}
    var targetPosition:CGPoint {target.position}
    var contactPointCount:Int {actors.filter {!$0.contact.isHidden}.count}
    #endif
}

private struct InplayFieldSurface:View {
    @State private var lowPower=ProcessInfo.processInfo.isLowPowerModeEnabled
    private var frameRate:Int {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-inplay-30hz-comparison") {return 30}
        if ProcessInfo.processInfo.arguments.contains("-ground-60hz-comparison") {return 60}
        #endif
        return lowPower || finished || previewTime != nil || reduced ? 30:60
    }
    let scene:InplayFieldScene
    let scoreText:String
    let finished:Bool
    let reduced:Bool
    let effectsReduced:Bool
    let previewTime:Double?
    var preparing=false
    var showsContactPoints=false
    var body:some View {
        GeometryReader {geometry in
            SpriteView(scene:scene,preferredFramesPerSecond:frameRate,options:[.ignoresSiblingOrder])
                .onAppear {
                    #if DEBUG
                    MatchRenderMetrics.mark("surfaceAppeared")
                    MatchRenderMetrics.recordCadence(frameRate,scene:scene)
                    #endif
                    lowPower=ProcessInfo.processInfo.isLowPowerModeEnabled
                    scene.canvasFrame=geometry.frame(in:.global);scene.isPaused=false;scene.setScore(scoreText)
                    scene.setReduced(reduced);scene.setEffectsReduced(effectsReduced);scene.setPreviewTime(previewTime);scene.setFinished(finished)
                    #if DEBUG
                    scene.setContactPoints(showsContactPoints)
                    #endif
                }
                .onReceive(NotificationCenter.default.publisher(for:.NSProcessInfoPowerStateDidChange).receive(on:RunLoop.main)) {_ in
                    lowPower=ProcessInfo.processInfo.isLowPowerModeEnabled
                }
                .onChange(of:geometry.frame(in:.global)) {_,frame in scene.canvasFrame=frame}
                .onChange(of:scoreText) {_,value in scene.setScore(value)}
                .onChange(of:finished) {_,value in scene.setFinished(value)}
                .onChange(of:previewTime) {_,value in scene.setPreviewTime(value)}
                .onChange(of:reduced) {_,value in scene.setReduced(value);scene.setEffectsReduced(effectsReduced)}
                .onChange(of:effectsReduced) {_,value in scene.setEffectsReduced(value)}
                #if DEBUG
                .onChange(of:showsContactPoints) {_,value in scene.setContactPoints(value)}
                .onChange(of:frameRate) {_,value in MatchRenderMetrics.recordCadence(value,scene:scene)}
                #endif
                .onDisappear {scene.isPaused=true}
                .overlay {
                    if preparing {Text("수비 화면 준비 중").font(.caption.monospaced().bold()).foregroundStyle(GameTheme.paper).padding(8).background(GameTheme.navy).accessibilityIdentifier("inplayRendererPreparing")}
                }
        }
    }
}

// All text boundaries, including chained throws/errors, use the same saved clock.
enum FieldReplayPhaseSchedule {
    static func moments(_ play:MatchDetailedPlay) -> [Double] {
        let base=[0,play.flight,play.pickupAt,play.releaseAt,play.ballAt,play.controlAt,play.duration]
        let relay=play.relay.map {[$0.receiveAt,$0.releaseAt]} ?? []
        let second=play.secondThrow.map {[$0.releaseAt,$0.ballAt,$0.controlAt]} ?? []
        let errors=play.misplay.map {[$0.at,$0.scatteredAt,$0.recoveredAt]} ?? []
        return Array(Set(base+relay+second+errors+FieldMisplayAnimation.moments(play)+FieldRelayTransfer.moments(play))).sorted()
    }
}

#if DEBUG
extension InplayReplay {
    var metricKind:String {switch self {case .field:"fieldSprite";case .homeRun:"homeRunSprite"}}
}
#endif

@MainActor enum OpponentMotionArt {
    private static let cache = NSCache<NSString,NSArray>()
    // Front-camera garment regions; glove, face and catcher armour remain separate layers.
    static func torso(_ name: String, frame: Int) -> CGRect {
        let rects: [[Double]]
        if name == "opponent-pitcher-v52" {
            rects = [[0.32,0.42,0.35,0.20],[0.37,0.40,0.30,0.20],[0.40,0.40,0.30,0.23],[0.40,0.42,0.30,0.22],
                     [0.43,0.45,0.30,0.18],[0.46,0.48,0.26,0.14],[0.42,0.43,0.27,0.17],[0.37,0.40,0.30,0.20]]
        } else if name == "opponent-batter-v116" {
            rects = [[0.32,0.39,0.25,0.21],[0.31,0.40,0.25,0.20],[0.15,0.40,0.27,0.22],
                     [0.36,0.39,0.27,0.23],[0.25,0.38,0.25,0.20],[0.19,0.37,0.27,0.22]]
        } else if name == "opponent-batter-v52" {
            rects = [[0.34,0.39,0.19,0.18],[0.32,0.41,0.20,0.18],[0.15,0.43,0.23,0.17],[0.42,0.33,0.26,0.19],[0.25,0.38,0.21,0.17],[0.15,0.37,0.24,0.17]]
        } else {
            rects = [[0.22,0.46,0.57,0.27],[0.19,0.48,0.58,0.27],[0,0,0,0],[0,0,0,0]]
        }
        let r=rects[min(frame,rects.count-1)]
        return CGRect(x:r[0],y:r[1],width:r[2],height:r[3])
    }
    // 헬멧과 어깨가 같은 높이에 있어도 상의를 모자 색으로 칠하지 않는다.
    static func batterHelmet(frame: Int) -> CGRect {
        let rects: [[Double]] = [[0.40,0.14,0.34,0.24],[0.33,0.14,0.34,0.24],[0.22,0.16,0.34,0.26],
                                [0.40,0.10,0.35,0.26],[0.32,0.16,0.34,0.23],[0.23,0.16,0.34,0.23]]
        let r=rects[min(frame,rects.count-1)]
        return CGRect(x:r[0],y:r[1],width:r[2],height:r[3])
    }
    static func image(_ name:String, frame:Int, columns:Int, rows:Int, kit:Int, style:GameUniformStyle?, mirrored: Bool = false) -> UIImage? {
        guard let source=MatchArt.cell(name,column:frame%columns,row:frame/columns,columns:columns,rows:rows)?.cgImage else {return nil}
        let w=source.width,h=source.height,format=CGBitmapInfo.byteOrder32Big.rawValue|CGImageAlphaInfo.premultipliedLast.rawValue
        var data=[UInt8](repeating:0,count:w*h*4),fabric=[Bool](repeating:false,count:w*h)
        let decoded=data.withUnsafeMutableBytes { buffer -> Bool in
            guard let c=CGContext(data:buffer.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:format) else {return false}
            c.draw(source,in:CGRect(x:0,y:0,width:w,height:h));return true
        }
        guard decoded else {return nil}
        let shirt=torso(name,frame:frame), catcher=name == "catcher-parts", batter=name.hasPrefix("opponent-batter-")
        let helmet=batterHelmet(frame:frame)
        let pro = style?.pro != nil
        let garmentMirrored = pro && mirrored
        let legs = shirt.insetBy(dx: -0.12, dy: 0)
        for y in 0..<h {for x in 0..<w {
            let index=(y*w+x)*4,a=Int(data[index+3]);guard a>16 else {continue}
            let r=Double(data[index])*255/Double(a),g=Double(data[index+1])*255/Double(a),b=Double(data[index+2])*255/Double(a)
            let p=CGPoint(x:Double(x)/Double(w),y:Double(y)/Double(h))
            let blue=b>36 && b>r*1.35 && b>g*1.1
            let white=min(r,g,b)>110 && max(r,g,b)-min(r,g,b)<65
            var color:Int?,shade=1.0
            if blue {
                fabric[y*w+x]=true
                if let style {
                    if batter {
                        if helmet.contains(p) {color=p.y > helmet.maxY-0.035 ? style.brim:style.cap}
                        else if shirt.contains(p) {color=style.shirt(x:(p.x-shirt.minX)/shirt.width,y:(p.y-shirt.minY)/shirt.height,mirrored:garmentMirrored)}
                        else if p.y > shirt.maxY+0.035 && p.y < 0.81 {
                            color = pro ? style.leg(base: style.pants, x: (p.x - legs.minX) / legs.width,
                                                    y: (p.y - shirt.maxY) / 0.24, mirrored: garmentMirrored) : style.trim
                        } else {color = p.y >= 0.81 ? style.gear ?? style.sleeves : style.sleeves}
                    } else if catcher { color = style.gear ?? style.sleeves }
                    else if p.y < shirt.minY {color=p.y > shirt.minY-0.09 ? style.brim:style.cap}
                    else if shirt.contains(p) { color=style.shirt(x:(p.x-shirt.minX)/shirt.width,y:(p.y-shirt.minY)/shirt.height) }
                    else {color = p.y >= 0.81 ? style.gear ?? style.sleeves : style.sleeves}
                } else {color=kit}
                shade=max(0.25,min(1.45,b/135))
            } else if let style, white {
                if pro && catcher && frame < 2 {
                    let sleeve = (0.47...0.66).contains(p.y) && ((0.22...0.33).contains(p.x) || (0.67...0.78).contains(p.x))
                    if sleeve { color = style.sleeve(base: style.sleeves, y: (p.y - 0.47) / 0.19) }
                    else if (0.78...0.86).contains(p.y) && (0.36...0.63).contains(p.x) { color = style.pants }
                } else if pro && batter && shirt.contains(p) && !helmet.contains(p) {
                    // The opponent atlas has a painted light band on each sleeve.
                    color = style.sleeve(base: style.sleeves, y: 1)
                } else if catcher && frame < 2 && shirt.contains(p) {
                    color=style.shirt(x:(p.x-shirt.minX)/shirt.width,y:(p.y-shirt.minY)/shirt.height)
                } else if !catcher && p.y > shirt.maxY+0.035 && p.y < 0.81 {
                    color = pro ? style.leg(base: style.pants, x: (p.x - legs.minX) / legs.width,
                                            y: (p.y - shirt.maxY) / 0.24, mirrored: garmentMirrored) : style.pants
                }
                shade=max(0.35,min(1.1,(r+g+b)/735))
            }
            if let color {for c in 0..<3 {data[index+c]=UInt8(min(255,Int(Double((color >> ((2-c)*8))&255)*shade))*a/255)}}
        }}
        if let style, !catcher {
            // Only paint onto original cloth pixels, never across the glove or exposed skin.
            let chest=CGPoint(x:(shirt.midX+(garmentMirrored ? -0.055 : 0.055))*Double(w),y:(shirt.minY+0.07)*Double(h))
            style.drawMark(at:chest,unit:1,mirrored:garmentMirrored,eligible:fabric,bytes:&data,width:w,height:h)
            let capCenters: [[Double]] = name == "opponent-pitcher-v52"
                ? [[0.49,0.19],[0.51,0.17],[0.56,0.22],[0.59,0.20],[0.64,0.26],[0.68,0.36],[0.66,0.33],[0.52,0.15]]
                : [[0.58,0.25],[0.51,0.26],[0.38,0.28],[0.60,0.20],[0.51,0.27],[0.40,0.27]]
            let cap=capCenters[frame]
            style.drawMark(at:CGPoint(x:cap[0]*Double(w),y:cap[1]*Double(h)),unit:1,mirrored:garmentMirrored,eligible:fabric,bytes:&data,width:w,height:h)
        }
        guard let provider=CGDataProvider(data:Data(data) as CFData),let image=CGImage(width:w,height:h,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:format),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else {return nil}
        return UIImage(cgImage:image)
    }
    static func textures(_ name:String,columns:Int,rows:Int,ownKit:Int,opponent:Bool = true,teamColor:Int? = nil,style:GameUniformStyle? = nil,mirrored: Bool = false) -> [SKTexture] {
        let kit=teamColor ?? (opponent ? FieldReplayPresentation.opponentKit(ownKit):ownKit)
        let garmentMirrored = style?.pro != nil && mirrored
        let orientation = garmentMirrored ? ":mirrored-garment" : ""
        let key="\(name):\(kit):\(style?.id ?? "legacy")\(orientation)" as NSString
        if let result=cache.object(forKey:key) as? [SKTexture] {return result}
        let result=(0..<(columns*rows)).compactMap { frame -> SKTexture? in
            guard let image=image(name,frame:frame,columns:columns,rows:rows,kit:kit,style:style,mirrored:garmentMirrored) else {return nil}
            let texture=SKTexture(image:image);texture.filteringMode = .nearest;return texture
        }
        cache.totalCostLimit=24*1024*1024
        cache.setObject(result as NSArray,forKey:key,cost:result.count*512*512*4)
        return result
    }
}
