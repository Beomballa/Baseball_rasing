import SwiftUI
import UIKit
import SpriteKit

// Presentation geometry never changes the saved pitch, timing window or RNG.
enum MatchArt {
    static let names = ["batter-view-clean", "stadium-clean", "batter-actions", "pitcher-delivery-v2", "catcher-parts",
                        "grip-fastball", "grip-slider", "grip-changeup", "grips-extra", "inplay-stadium-arcade-v1"]
    private static let images: [String: UIImage] = Dictionary(uniqueKeysWithValues: names.compactMap { name in
        guard let url = Bundle.main.url(forResource: name, withExtension: "png", subdirectory: "MatchArt"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        return (name, image)
    })
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
    struct Frame: Decodable {
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
    struct Sample {let frame:Frame;let weight:Double;let unit:Double;let mirrored:Bool}
    static let directions=["n","ne","e","se","s","sw","w","nw"]
    static let manifest: Manifest? = {
        guard let url=Bundle.main.url(forResource:"field-runtime-v1",withExtension:"json",subdirectory:"MatchArt"),
              let data=try? Data(contentsOf:url) else {return nil}
        return try? JSONDecoder().decode(Manifest.self,from:data)
    }()
    private static let cache: NSCache<NSString,UIImage> = {let c=NSCache<NSString,UIImage>();c.totalCostLimit=48*1024*1024;return c}()
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
            return Sample(frame:frame,weight:weight,unit:authoredUnit,mirrored:left != frame.sourceLeft)
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
    static func image(_ sample:Sample,kit:Int,skin:Int,hair:Int,number:Int,back:Bool) -> UIImage? {
        let f=sample.frame
        let key="\(f.file):\(f.rect):\(kit):\(skin):\(hair):\(number):\(back):\(sample.mirrored)" as NSString
        if let result=cache.object(forKey:key) {return result}
        guard let url=Bundle.main.url(forResource:f.file,withExtension:nil,subdirectory:"MatchArt"),
              let original=UIImage(contentsOfFile:url.path)?.cgImage,
              let crop=original.cropping(to:CGRect(x:f.rect[0],y:f.rect[1],width:f.rect[2],height:f.rect[3])) else {return nil}
        let w=crop.width,h=crop.height,format=CGBitmapInfo.byteOrder32Big.rawValue|CGImageAlphaInfo.premultipliedLast.rawValue
        var bytes=[UInt8](repeating:0,count:w*h*4)
        let ok=bytes.withUnsafeMutableBytes {buffer -> Bool in
            guard let c=CGContext(data:buffer.baseAddress,width:w,height:h,bitsPerComponent:8,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:format) else {return false}
            c.draw(crop,in:CGRect(x:0,y:0,width:w,height:h));return true
        }
        guard ok else {return nil}
        var bounds=[(Int,Int)](repeating:(0,0),count:h)
        for row in f.clipRows where row.count==3 && row[0]<h {bounds[row[0]]=(row[1],row[1]+row[2])}
        for y in 0..<h {for x in 0..<w {
            let i=(y*w+x)*4,a=Int(bytes[i+3])
            guard x>=bounds[y].0 && x<bounds[y].1 else {bytes[i+3]=0;bytes[i]=0;bytes[i+1]=0;bytes[i+2]=0;continue}
            guard a>128 else {continue}
            let r=Double(bytes[i])*255/Double(a),g=Double(bytes[i+1])*255/Double(a),b=Double(bytes[i+2])*255/Double(a)
            var color:Int?,shade=1.0
            if b>40 && b>r*1.35 && b>g*1.08 {color=kit;shade=max(0.3,min(1.5,b/155))}
            // Keep the glove's brown leather independent from skin recoloring.
            else if (f.file.hasPrefix("runner-") || abs(Double(x)-f.glove[0])>Double(w)*0.16 || abs(Double(y)-f.glove[1])>Double(h)*0.18) && r>185 && r>g*1.13 && g>b*1.12 && g>95 {color=skin;shade=max(0.45,min(1.2,r/240))}
            else if Double(y)>Double(h)*0.19 && Double(y)<Double(h)*0.36 && Double(x)>Double(w)*0.23 && Double(x)<Double(w)*0.77 && r<65 && abs(r-g)<22 && abs(g-b)<22 {color=hair;shade=max(0.5,(r+g+b)/100)}
            if let color {for (offset,shift) in [(0,16),(1,8),(2,0)] {bytes[i+offset]=UInt8(min(255,Double((color>>shift)&255)*shade)*Double(a)/255)}}
        }}
        if back {
            PlayerMotionArt.drawNumber(number,at:CGPoint(x:f.numberCenter?[0] ?? Double(w)*0.5,y:f.numberCenter?[1] ?? Double(h)*0.49),angle:0,
                mirrored:sample.mirrored,unit:max(2,w/60),bytes:&bytes,width:w,height:h)
        }
        guard let provider=CGDataProvider(data:Data(bytes) as CFData),let cg=CGImage(width:w,height:h,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:w*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:format),provider:provider,decode:nil,shouldInterpolate:false,intent:.defaultIntent) else {return nil}
        let result=UIImage(cgImage:cg);cache.setObject(result,forKey:key,cost:w*h*4);return result
    }
    @discardableResult static func draw(in context:GraphicsContext,at point:CGPoint,scale:Double,motion:FieldSpriteMotion,
            kind:String,kit:Int,skin:Int,hair:Int,number:Int,left:Bool,selected:Bool,out:Bool) -> Bool {
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
            guard let image=image(sample,kit:kit,skin:skin,hair:hair,number:number,back:motion.facing.back && kind != "catcher") else {return false}
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
        let ratio: CGFloat = role == .batter ? 1 : 1219 / 1290
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
        let names = ["four-seam": "포심", "slider": "슬라이더", "changeup": "체인지업", "fork": "포크"]
        return result.pitchCode.flatMap { names[$0] } ?? "구종 미기록"
    }
}

enum MatchBallPath {
    static func point(from start: CGPoint, to end: CGPoint, size: CGSize, role: PlayerRole,
                      hand: String, code: String, progress: Double) -> CGPoint {
        let t = min(1, max(0, progress))
        let depth = role == .batter ? t / (2.4 - 1.4 * t) : 2.4 * t / (1 + 1.4 * t)
        let bend = depth * depth - depth
        let lateral = (code == "slider" ? 0.07 : code == "changeup" ? -0.04 : 0) * (hand == "left" ? -1.0 : 1)
        let drop = code == "fork" ? 0.13 : code == "changeup" ? 0.08 : 0.025
        return CGPoint(x: start.x + (end.x - start.x) * depth + lateral * size.width * bend,
                       y: start.y + (end.y - start.y) * depth - drop * size.height * bend)
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
    var body: some View {
        let image = code == "fork" ? MatchArt.cell("grips-extra", column: 2, row: 1, columns: 4, rows: 2)
            : MatchArt.image(code == "slider" ? "grip-slider" : code == "changeup" ? "grip-changeup" : "grip-fastball")
        if let image {
            Image(uiImage: image).resizable().interpolation(.none).scaledToFit()
                .scaleEffect(x: hand == "left" ? -1 : 1, y: 1)
                .accessibilityLabel(hand == "left" ? "왼손 구종 그립" : "오른손 구종 그립")
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

@MainActor enum PlayerMotionArt {
    private static let cache: NSCache<NSString, NSArray> = {
        let cache = NSCache<NSString, NSArray>(); cache.totalCostLimit = 32 * 1024 * 1024
        return cache
    }()
    struct Pose {
        let shirt: [CGPoint]
        let hair: CGRect
        let skin: [CGRect]
        let number: CGPoint
        var angle: Double = 0
        var erase: CGRect = .zero
    }
    private static func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> CGRect { CGRect(x: x, y: y, width: w, height: h) }
    private static func polygon(_ pairs: [(Double, Double)]) -> [CGPoint] { pairs.map { CGPoint(x: $0.0, y: $0.1) } }
    static func pose(role: PlayerRole, frame: Int) -> Pose {
        if role == .pitcher {
            let hair = [rect(235,177,102,44),rect(218,166,102,44),rect(221,201,97,41),rect(222,174,103,42),rect(147,198,91,45),rect(216,185,102,43)]
            let skin = [[rect(215,172,136,61),rect(199,266,38,44)], [rect(204,160,132,57),rect(181,253,46,37)],
                        [rect(202,191,139,57),rect(153,239,48,43),rect(331,163,66,96)],
                        [rect(208,161,137,64),rect(204,251,46,50),rect(329,38,97,125)],
                        [rect(133,190,113,61),rect(200,282,105,78)], [rect(180,171,150,70),rect(173,258,75,51),rect(329,270,35,38)]]
            let centers = [CGPoint(x:303,y:266),CGPoint(x:291,y:251),CGPoint(x:301,y:286),CGPoint(x:299,y:245),CGPoint(x:264,y:244),CGPoint(x:288,y:252)]
            let erase = [rect(264,237,76,57),rect(253,222,77,59),rect(262,255,76,60),rect(264,216,76,58),rect(220,208,87,66),rect(252,223,76,58)]
            return Pose(shirt: [], hair: hair[frame], skin: skin[frame], number: centers[frame], angle: frame == 4 ? -0.5 : 0, erase: erase[frame])
        }
        let shirts = [polygon([(198,180),(230,178),(270,201),(278,264),(251,291),(154,279),(164,237),(179,200)]),
                      polygon([(163,196),(203,187),(258,204),(262,270),(238,303),(153,298),(164,258)]),
                      polygon([(143,203),(195,209),(238,231),(244,280),(200,316),(112,303),(122,246)]),
                      polygon([(197,151),(265,169),(337,199),(339,243),(304,270),(211,266),(198,216)]),
                      polygon([(158,182),(207,183),(260,208),(271,246),(241,280),(118,270),(132,224)]),
                      polygon([(151,187),(205,186),(260,209),(269,248),(239,281),(116,275),(129,227)])]
        let hair = [rect(248,168,58,25),rect(209,177,62,33),rect(178,180,78,36),rect(255,143,70,32),rect(215,177,72,35),rect(210,179,72,35)]
        let skin = [[rect(258,160,68,47),rect(264,188,85,60)], [rect(210,174,79,44),rect(85,164,78,65)],
                    [rect(171,181,110,46),rect(248,231,81,59)], [rect(252,142,90,49),rect(180,90,65,51)],
                    [rect(210,175,97,53),rect(231,225,114,52)], [rect(203,176,100,53),rect(230,223,111,55)]]
        let centers = [CGPoint(x:202,y:240),CGPoint(x:232,y:266),CGPoint(x:162,y:262),CGPoint(x:273,y:226),CGPoint(x:165,y:240),CGPoint(x:163,y:242)]
        return Pose(shirt: shirts[frame], hair: hair[frame], skin: skin[frame], number: centers[frame])
    }
    static func textures(role: PlayerRole, appearance: PlayerAppearance, number: Int, hand: String) -> [SKTexture] {
        let key = ([role.rawValue, hand] + [appearance.skin,appearance.hair,appearance.kit,appearance.hairStyle,appearance.expression,number].map(String.init)).joined(separator: ":") as NSString
        if let cached = cache.object(forKey: key) as? [SKTexture] { return cached }
        let result = (0..<6).compactMap { frame -> SKTexture? in
            guard let image = image(role: role, frame: frame, appearance: appearance, number: number, hand: hand) else { return nil }
            let texture = SKTexture(image: image); texture.filteringMode = .nearest; return texture
        }
        if result.count == 6 { cache.setObject(result as NSArray, forKey: key, cost: 6 * 512 * 512 * 4) }
        return result
    }
    // Semantic regions use the original 512px cells. Source sheets, alpha, pose geometry and saved state stay unchanged.
    static func image(role: PlayerRole, frame: Int, appearance: PlayerAppearance, number: Int, hand: String) -> UIImage? {
        guard (0..<6).contains(frame), appearance.isValid, (0...99).contains(number),
              let original = MatchArt.cell(role == .pitcher ? "pitcher-delivery-v2" : "batter-actions", column: frame % 3, row: frame / 3, columns: 3, rows: 2)?.cgImage, original.width == 512, original.height == 512 else { return nil }
        let width = original.width, height = original.height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let format = CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue
        let decoded = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: format) else { return false }
            context.draw(original, in: CGRect(x: 0, y: 0, width: width, height: height)); return true
        }
        guard decoded else { return nil }
        let pose = pose(role: role, frame: frame)
        let shirt = CGMutablePath(); if let first = pose.shirt.first { shirt.move(to: first); pose.shirt.dropFirst().forEach { shirt.addLine(to: $0) }; shirt.closeSubpath() }
        let kit = PlayerAppearance.kitColors[appearance.kit], skin = PlayerAppearance.skinColors[appearance.skin], hair = PlayerAppearance.hairColors[appearance.hair]
        func rgb(_ hex: Int, _ shade: Double) -> (Int,Int,Int) {
            (min(255,Int(Double((hex >> 16) & 255) * shade)), min(255,Int(Double((hex >> 8) & 255) * shade)), min(255,Int(Double(hex & 255) * shade)))
        }
        var shirtShade = [Double](repeating: 0.95, count: height)
        if role == .pitcher {
            for y in Int(pose.erase.minY)..<Int(pose.erase.maxY) {
                var sum = 0.0, count = 0.0
                for x in Int(pose.erase.minX)..<Int(pose.erase.maxX) {
                    let i = (y * width + x) * 4, a = Int(bytes[i+3]); guard a > 128 else { continue }
                    let r = Double(bytes[i]) * 255 / Double(a), g = Double(bytes[i+1]) * 255 / Double(a), b = Double(bytes[i+2]) * 255 / Double(a)
                    if b > 36 && b > r * 1.35 && b > g * 1.1 { sum += b / 135; count += 1 }
                }
                if count > 0 { shirtShade[y] = max(0.25,min(1.6,sum / count)) }
            }
        }
        let mouths = [CGPoint(x:303,y:193),CGPoint(x:264,y:206),CGPoint(x:262,y:218),CGPoint(x:314,y:180),CGPoint(x:273,y:205),CGPoint(x:270,y:206)]
        let mouth = mouths[frame]
        for y in 0..<height { for x in 0..<width {
            let index = (y * width + x) * 4, alpha = Int(bytes[index + 3])
            guard alpha > 16 else { continue }
            let r = Int(bytes[index]) * 255 / alpha, g = Int(bytes[index + 1]) * 255 / alpha, b = Int(bytes[index + 2]) * 255 / alpha
            let point = CGPoint(x: x, y: y), high = max(r,g,b), low = min(r,g,b)
            var color: (Int,Int,Int)?
            if role == .pitcher && pose.erase.contains(point) && high > 100 && high - low < 105 {
                color = rgb(kit, shirtShade[y])
            } else if b > 36 && Double(b) > Double(r) * 1.35 && Double(b) > Double(g) * 1.1 {
                color = rgb(kit, max(0.25,min(1.6,Double(b) / 135)))
            } else if role == .batter && low > 90 && high - low < 70 && shirt.contains(point) {
                color = rgb(kit, max(0.35,Double(r + g + b) / 720))
            } else if pose.hair.contains(point) && high > 22 && high - low < 34 {
                let shaved = appearance.hairStyle == 1 && Double(x) < pose.hair.minX + pose.hair.width * 0.25
                color = rgb(shaved ? skin : hair, max(0.35,min(1.15,Double(high) / 52)))
            } else if pose.skin.contains(where: { $0.contains(point) }) && r > 175 && Double(r) > Double(g) * 1.12 && Double(g) > Double(b) * 1.12 {
                color = rgb(skin, max(0.5,min(1.15,Double(r) / 247)))
            }
            if appearance.hairStyle == 2 && pose.hair.contains(point) && Double(y) > pose.hair.maxY - 7 && high > 30 && high - low < 90 && (x / 6) % 2 == 0 {
                color = rgb(hair, 0.8)
            }
            if role == .batter && appearance.expression > 0 {
                if abs(Double(x) - mouth.x) <= 3 && abs(Double(y) - mouth.y) <= (appearance.expression == 2 ? 2 : 0) && r > 175 && Double(r) > Double(g) * 1.12 && Double(g) > Double(b) * 1.12 {
                    color = rgb(0x85442e, 0.8)
                }
            }
            if let color {
                bytes[index] = UInt8(color.0 * alpha / 255); bytes[index + 1] = UInt8(color.1 * alpha / 255); bytes[index + 2] = UInt8(color.2 * alpha / 255)
            }
        } }
        drawNumber(number, at: pose.number, angle: pose.angle, mirrored: role == .pitcher && hand == "left", unit: role == .pitcher ? 7 : 5, bytes: &bytes, width: width, height: height)
        guard let provider = CGDataProvider(data: Data(bytes) as CFData), let image = CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: colorSpace, bitmapInfo: CGBitmapInfo(rawValue: format), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent) else { return nil }
        return UIImage(cgImage: image)
    }
    static let digits = ["111101101101111", "010110010010111", "111001111100111", "111001111001111", "101101111001001", "111100111001111", "111100111101111", "111001001001001", "111101111101111", "111101111001111"]
    fileprivate static func drawNumber(_ number: Int, at center: CGPoint, angle: Double, mirrored: Bool, unit: Int, bytes: inout [UInt8], width: Int, height: Int) {
        let masks = String(number).compactMap { $0.wholeNumberValue }.map { Array(digits[$0]) }
        let columns = masks.count * 4 - 1, textWidth = Double(columns * unit), textHeight = Double(5 * unit)
        let cosine = cos(angle), sine = sin(angle)
        for y in max(0,Int(center.y)-70)..<min(height,Int(center.y)+70) {
            for x in max(0,Int(center.x)-70)..<min(width,Int(center.x)+70) {
                let dx = Double(x) - center.x, dy = Double(y) - center.y
                let localX = (dx * cosine + dy * sine) * (mirrored ? -1 : 1) + textWidth / 2
                let localY = dy * cosine - dx * sine + textHeight / 2
                guard localX >= 0, localX < textWidth, localY >= 0, localY < textHeight else { continue }
                let col = Int(localX) / unit, row = Int(localY) / unit
                guard col % 4 < 3, masks[col / 4][row * 3 + col % 4] == "1" else { continue }
                let i = (y * width + x) * 4
                guard bytes[i + 3] > 128 else { continue }
                let a = Int(bytes[i + 3]); bytes[i] = UInt8(244*a/255); bytes[i+1] = UInt8(240*a/255); bytes[i+2] = UInt8(219*a/255)
            }
        }
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
        if FieldMisplayAnimation.ballIsLoose(play,time:time) {return .zero}
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
            return CGPoint(x:p.x+motion.bodyOffset.x,y:p.y+motion.bodyOffset.y)
        }
        return .zero
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
        let position=FieldNode.sample(play.ball,at:time)
        let motionIndex=play.fielders.indices.first {FieldNode.sample(play.fielders[$0],at:time).distance(to:position)<0.9}
        let scale=InplayFieldProjection.actorScale(position,size:size)
        var offset=FieldSpriteAnimation.ballOffset(play,time:time,leftIndex:leftIndex)
        if let index=motionIndex {
            let display=InplayFieldProjection.motion(FieldSpriteAnimation.motion(play,index:index,time:time),at:position,size:size)
            // Preserve the gather interpolation while using the projected screen-facing pose.
            let left=index == leftIndex
            func anchor(_ motion:FieldSpriteMotion) -> CGPoint {
                var p=motion.glove(left:left)
                if motion.ballInThrowingHand {p=motion.throwingHand(left:left)}
                else if motion.stage == .gather && motion.willThrow {
                    let hand=motion.throwingHand(left:left)
                    p=CGPoint(x:p.x+(hand.x-p.x)*motion.progress,y:p.y+(hand.y-p.y)*motion.progress)
                }
                if let raster=FieldRasterArt.contact(motion,kind:index == 1 ? "catcher":"fielder",left:left,hand:motion.ballInThrowingHand) {p=raster}
                return CGPoint(x:p.x+motion.bodyOffset.x,y:p.y+motion.bodyOffset.y)
            }
            if offset != .zero {
                let b=anchor(display)
                offset=b
            }
        }
        return CGPoint(x:offset.x*scale,y:offset.y*scale)
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
}

struct DetailedFieldReplayBoard: View {
    let play: MatchDetailedPlay
    let appearance: PlayerAppearance
    var animated = true
    var jerseyNumber = 1
    var ownPosition: String? = nil
    var throwingHand = "right"
    var ownTeamFielding: Bool? = nil
    var scoreText = "IN PLAY"
    var previewTime:Double? = nil
    var handoff:FieldContactHandoff? = nil
    var showsContactPoints = false
    var onResolved: @MainActor () -> Void = {}
    let complete: @MainActor () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var start: Date?
    @State private var resolved = false
    private var seconds: Double {FieldReplayPresentation.seconds(play,reduced:reduced,animated:animated)}
    var body: some View {
        TimelineView(.animation(minimumInterval:reduced ? 0.15:1.0/30,paused:previewTime != nil || !animated || resolved)) { timeline in
            let now=ProcessInfo.processInfo.systemUptime
            let elapsed=handoff?.elapsed(at:now) ?? start.map {timeline.date.timeIntervalSince($0)} ?? 0
            let time=previewTime.map {max(0,min(play.duration,$0))} ?? (resolved ? play.duration:FieldReplayPresentation.time(play,elapsed:elapsed,reduced:reduced,animated:animated))
            let finished=previewTime.map {$0>=play.duration} ?? (!animated || resolved)
            let phase=FieldReplayPresentation.phase(play,time:time,finished:finished)
            let second=play.secondThrow
            let target=time >= (second?.releaseAt ?? .infinity) ? 1:play.targetBase
            VStack(spacing:4) {
                Text(finished ? "플레이 완료":phase).font(.system(.headline,design:.monospaced,weight:.bold)).foregroundStyle(GameTheme.gold)
                    .lineLimit(typeSize.isAccessibilitySize ? nil:2).accessibilityIdentifier("fieldReplayPhase")
                GeometryReader { geometry in
                Canvas { context,size in
                    var context=context
                    if let handoff {
                        let cut=max(0,min(play.duration,handoff.cutAt-handoff.startedAt))
                        let ball=FieldBallPresentation.point(play,time:cut,size:size,leftIndex:ownTeamFielding == true && throwingHand == "left" ? DetailedFieldRules.names.firstIndex(of:ownPosition ?? ""):nil)
                        let offset=FieldContactPresentation.cameraOffset(handoff,fieldPoint:ball,canvas:geometry.frame(in:.global),now:now,reduced:reduced)
                        context.clip(to:Path(CGRect(origin:.zero,size:size)))
                        context.translateBy(x:offset.x,y:offset.y)
                    }
                    func point(_ p:FieldPoint) -> CGPoint {InplayFieldProjection.point(p,size:size)}
                    if let image=InplayStadiumArt.image {
                        context.draw(Image(uiImage:image).interpolation(.none),in:InplayFieldProjection.viewport(size))
                    } else {
                        context.draw(Text("구장 이미지를 불러오지 못했습니다").foregroundStyle(GameTheme.paper),at:CGPoint(x:size.width/2,y:size.height/4))
                    }
                    let viewport=InplayFieldProjection.viewport(size)
                    let scoreFrame=CGRect(x:viewport.minX+viewport.width*0.39,y:viewport.minY+viewport.height*0.123,width:viewport.width*0.22,height:viewport.height*0.039)
                    context.fill(Path(scoreFrame),with:.color(Color(hex:0x0b2030)))
                    context.stroke(Path(scoreFrame),with:.color(GameTheme.gold),lineWidth:2)
                    context.draw(Text(scoreText).font(.system(size:max(12,size.width*0.028),weight:.black,design:.monospaced)).foregroundStyle(GameTheme.paper),at:CGPoint(x:scoreFrame.midX,y:scoreFrame.midY))
                    if time>=play.pickupAt {
                        let b=point(DetailedFieldRules.bases[target]),w=max(7,size.width*0.025)
                        context.stroke(Path(ellipseIn:CGRect(x:b.x-w,y:b.y-w/2,width:w*2,height:w)),with:.color(GameTheme.gold.opacity(0.8)),lineWidth:1)
                    }
                    let ownKit=PlayerAppearance.kitColors[appearance.kit],opponent=FieldReplayPresentation.opponentKit(ownKit)
                    let defenseOwn=ownTeamFielding ?? !play.ownBatter
                    var actors:[(point:FieldPoint,motion:FieldSpriteMotion,own:Bool,teamOwn:Bool,number:Int,out:Bool,kind:String)]=[]
                    for index in play.fielders.indices {
                        let own=defenseOwn && (ownPosition.map {DetailedFieldRules.names[index] == $0} ?? (play.ownDefense && index==play.fielder))
                        actors.append((FieldNode.sample(play.fielders[index],at:time),FieldSpriteAnimation.motion(play,index:index,time:time),own,defenseOwn,own ? jerseyNumber:index+1,false,index == 1 ? "catcher":"fielder"))
                    }
                    for runner in play.runners {
                        let display=FieldSpriteAnimation.runner(runner,play:play,time:time,reduced:reduced)
                        actors.append((display.point,display.motion,runner.profile.own,!defenseOwn,runner.profile.own ? jerseyNumber:runner.from+10,FieldReplayPresentation.retired(runner,finished:finished),"runner"))
                    }
                    for actor in actors.sorted(by:{$0.point.y>$1.point.y}) {
                        let raster=FieldRasterArt.draw(in:context,at:point(actor.point),scale:InplayFieldProjection.actorScale(actor.point,size:size),motion:InplayFieldProjection.motion(actor.motion,at:actor.point,size:size),kind:actor.kind,
                            kit:actor.teamOwn ? ownKit:opponent,skin:actor.own ? PlayerAppearance.skinColors[appearance.skin]:0xefbe91,
                            hair:actor.own ? PlayerAppearance.hairColors[appearance.hair]:0x263b48,number:actor.number,
                            left:actor.own && throwingHand == "left",selected:actor.own,out:actor.out)
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
                    for i in 1...3 where !reduced && time<Double(play.ball.last?.at ?? 0) {
                        let p=ballPoint(max(0,time-Double(i)*0.04))
                        context.fill(Path(CGRect(x:p.x,y:p.y,width:2,height:2)),with:.color(GameTheme.paper.opacity(0.4)))
                    }
                    if showsContactPoints {
                        for index in play.fielders.indices {
                            let at=FieldNode.sample(play.fielders[index],at:time)
                            let motion=InplayFieldProjection.motion(FieldSpriteAnimation.motion(play,index:index,time:time),at:at,size:size)
                            let hand=[FieldSpriteStage.windup,.release].contains(motion.stage)
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
                }.aspectRatio(2.0/3,contentMode:.fit).accessibilityLabel(finished ? "도트 수비 주루 재생 · "+play.summary:"인플레이 · "+(play.fly == nil ? "땅볼":"공중 타구"))
                    .accessibilityValue(finished ? FieldReplayPresentation.errorDetail(play,ownTeamFielding:ownTeamFielding ?? !play.ownBatter) ?? "플레이 완료":"진행 \(Int(min(1,time/max(0.001,play.duration))*100))%")
                    .accessibilityIdentifier("fieldReplayCanvas").id("fieldGraphic")
            }.padding(4).background(GameTheme.board)
                .overlay(Rectangle().strokeBorder(GameTheme.boardLine,lineWidth:2))
        }
        .task(id:play.eventID + (animated ? ":live":":still")) {
            guard previewTime == nil else {return}
            start=Date();resolved=false
            guard animated else {return}
            let elapsed=handoff?.elapsed(at:ProcessInfo.processInfo.systemUptime) ?? 0
            do {try await Task.sleep(for:.seconds(max(0,seconds-elapsed)))} catch {return}
            guard !Task.isCancelled else {return}
            resolved=true;onResolved()
            if animated {
                do {try await Task.sleep(for:.seconds(DeliveryPresentation.receipt(reduced:reduced,match:true)))} catch {return}
            }
            if !Task.isCancelled {complete()}
        }
    }
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
    static func flight(_ duration: Double, reduced: Bool, role: PlayerRole = .batter) -> Double { reduced && role == .batter ? 0.15 : duration }
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
    static func marker(x: Double, y: Double, size: CGSize) -> CGPoint {
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
    var scoreText="IN PLAY"
    var handoff:FieldContactHandoff?=nil
    var animated=true
    var previewTime:Double?=nil
    var onResolved:@MainActor () -> Void = {}
    var complete:@MainActor () -> Void = {}
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var start=ProcessInfo.processInfo.systemUptime
    @State private var resolved=false
    var body:some View {
        TimelineView(.animation(minimumInterval:reduced ? 0.15:1.0/30,paused:previewTime != nil || !animated || resolved)) {_ in
            let now=ProcessInfo.processInfo.systemUptime
            let elapsed=handoff?.elapsed(at:now) ?? max(0,now-start)
            let time=previewTime.map {max(0,min(event.duration,$0))} ?? (resolved || !animated ? event.duration:HomeRunPresentation.time(event,elapsed:elapsed,reduced:reduced))
            let finished=previewTime.map {$0>=event.duration} ?? (resolved || !animated)
            VStack(spacing:8) {
                Text(HomeRunPresentation.phase(event,time:time,finished:finished)).font(.headline.monospaced()).foregroundStyle(GameTheme.gold)
                    .accessibilityIdentifier("homeRunPhase")
                GeometryReader {geometry in
                    Canvas {context,size in
                        var context=context
                        if let handoff {
                            let cut=max(0,min(event.duration,handoff.cutAt-handoff.startedAt))
                            let offset=FieldContactPresentation.cameraOffset(handoff,fieldPoint:HomeRunPresentation.ballPoint(event,time:cut,size:size),canvas:geometry.frame(in:.global),now:now,reduced:reduced)
                            context.clip(to:Path(CGRect(origin:.zero,size:size)));context.translateBy(x:offset.x,y:offset.y)
                        }
                        if let image=InplayStadiumArt.image {context.draw(Image(uiImage:image).interpolation(.none),in:InplayFieldProjection.viewport(size))}
                        let ownKit=PlayerAppearance.kitColors[appearance.kit],opponent=FieldReplayPresentation.opponentKit(ownKit)
                        var actors:[(FieldPoint,FieldSpriteMotion,Bool,Bool,Int,String)]=[]
                        for index in 0..<9 {
                            let p=event.defender(index,at:time),previous=event.defender(index,at:max(0,time-0.08)),next=event.defender(index,at:time+0.08)
                            let moving=index>=6 && time<event.flight && p.distance(to:next)>0.001
                            let motion=FieldSpriteMotion(facing:.direction(dx:next.x-previous.x,dy:next.y-previous.y),stage:moving && !reduced ? .run:.ready,gait:time*12)
                            let own=ownTeamFielding && event.ownDefender == index
                            actors.append((p,motion,own,ownTeamFielding,own ? jerseyNumber:index+1,index == 1 ? "catcher":"fielder"))
                        }
                        for runner in event.runners where time<=runner.arrival+0.6 || runner.from == 0 {
                            let (p,motion)=HomeRunPresentation.runner(runner,time:time,reduced:reduced)
                            actors.append((p,motion,runner.profile.own,!ownTeamFielding,runner.profile.own ? jerseyNumber:runner.from+10,"runner"))
                        }
                        for (p,motion,own,teamOwn,number,kind) in actors.sorted(by:{$0.0.y>$1.0.y}) {
                            _=FieldRasterArt.draw(in:context,at:InplayFieldProjection.point(p,size:size),scale:InplayFieldProjection.actorScale(p,size:size),motion:InplayFieldProjection.motion(motion,at:p,size:size),kind:kind,
                                kit:teamOwn ? ownKit:opponent,skin:own ? PlayerAppearance.skinColors[appearance.skin]:0xefbe91,
                                hair:own ? PlayerAppearance.hairColors[appearance.hair]:0x263b48,number:number,left:own && throwingHand == "left",selected:own,out:false)
                        }
                        let scoreboard=CGRect(x:size.width*0.38,y:size.height*0.14,width:size.width*0.24,height:size.height*0.04)
                        context.fill(Path(scoreboard),with:.color(GameTheme.navy))
                        context.draw(Text(scoreText).font(.system(size:max(12,size.width*0.027),weight:.bold,design:.monospaced)).foregroundStyle(GameTheme.paper),at:CGPoint(x:scoreboard.midX,y:scoreboard.midY))
                        if time<=event.flight {
                            let p=HomeRunPresentation.ballPoint(event,time:time,size:size)
                            for i in 1...3 where !reduced {
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
                }.aspectRatio(2.0/3,contentMode:.fit)
                    .accessibilityElement(children:.ignore)
                    .accessibilityLabel(finished ? "홈런 · \(event.distance)m · \(event.runs)점":"타구 비행과 주자 베이스 일주")
                    .accessibilityValue(finished ? "홈 도착 완료":"진행 \(Int(time/event.duration*100))%")
                    .accessibilityIdentifier("homeRunCanvas")
                if finished {Text("HOME RUN · \(event.distance)m · \(event.runs)점").font(.headline.monospaced()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("homeRunCelebration")}
            }.padding(4).background(GameTheme.board).overlay(Rectangle().strokeBorder(GameTheme.boardLine,lineWidth:2))
        }
        .task(id:event.eventID+(animated ? ":live":":still")) {
            guard previewTime == nil,animated else {return}
            start=ProcessInfo.processInfo.systemUptime;resolved=false
            let elapsed=handoff?.elapsed(at:start) ?? 0
            do {try await Task.sleep(for:.seconds(max(0,event.duration-elapsed)))} catch {return}
            guard !Task.isCancelled else {return};resolved=true;onResolved()
            do {try await Task.sleep(for:.seconds(DeliveryPresentation.receipt(reduced:reduced,match:true)))} catch {return}
            if !Task.isCancelled {complete()}
        }
    }
}
