import CoreGraphics
import SpriteKit
import UIKit

/// 도트 원화의 발·손 기준점이다. 경기 판정 좌표와 분리된 연출용 정보다.
struct PitcherPresentationPose {
  let width: Double
  private(set) var pivot: CGPoint
  private(set) var hand: CGPoint
  private(set) var foot: CGPoint
  /// 화면 역할과 투구 손에 맞춘 정규화 몸 이동량을 계산한다.
  static func travel(role: PlayerRole, phase: Double, hand: String) -> CGPoint {
    // 자세가 바뀌어도 몸 이동은 연속으로 계산하고 앞발 착지는 원화 기준점을 따른다.
    let p = min(role == .pitcher ? 5 : 7, max(0, phase))
    let progress = min(1, max(0, (p - 1) / (role == .pitcher ? 3 : 4)))
    let ease = progress * progress * (3 - 2 * progress)
    return CGPoint(
      x: role == .pitcher ? (hand == "left" ? 1 : -1) * 0.012 * ease : 0,
      y: role == .pitcher ? -0.014 * ease : 0.009 * ease)
  }
  /// 해당 카메라의 유효 프레임을 받아 원화 기준점을 설정하고 좌투를 반전한다.
  init(role: PlayerRole, frame: Int, hand throwingHand: String) {
    if role == .pitcher {
      let pivots = [
        CGPoint(x: 0.70, y: 0.90), CGPoint(x: 0.57, y: 0.90), CGPoint(x: 0.74, y: 0.90),
        CGPoint(x: 0.41, y: 0.85), CGPoint(x: 0.40, y: 0.85), CGPoint(x: 0.42, y: 0.85),
      ]
      let hands = [
        CGPoint(x: 0.42, y: 0.56), CGPoint(x: 0.38, y: 0.52), CGPoint(x: 0.72, y: 0.37),
        CGPoint(x: 0.78, y: 0.11), CGPoint(x: 0.50, y: 0.65), CGPoint(x: 0.40, y: 0.55),
      ]
      width = 0.52
      pivot = pivots[frame]
      hand = hands[frame]
      // 2번 자세의 앞발(x=.29) 착지 지점을 릴리스까지 유지해 발이 뒤로 밀리지 않게 한다.
      foot = CGPoint(x: frame < 3 ? 0.76 : 0.526, y: frame < 3 ? 0.870 : 0.850)
    } else {
      width = 0.20
      let pivots = [0.5, 0.53, 0.65, 0.65, 0.55, 0.52, 0.50, 0.5]
      pivot = CGPoint(x: pivots[frame], y: 0.965)
      hand = frame == 4 ? CGPoint(x: 0.35, y: 0.08) : CGPoint(x: 0.35, y: 0.42)
      foot = CGPoint(x: 0.50, y: 0.375)
    }
    if throwingHand == "left" {
      if role == .pitcher { self.foot.x = 1 - self.foot.x }
      self.pivot = CGPoint(x: 1 - pivot.x, y: pivot.y)
      self.hand = CGPoint(x: 1 - hand.x, y: hand.y)
    }
  }
}

/// 몸통과 팔다리 길이를 유지한 채 각도만 연결한다. 좌표를 따로 늘이는 보간은 하지 않는다.
/// 첨부 영상의 착지→회전→팔 가속→감속 순서를 게임 시각에 맞춘 수작업 근사다.
struct PitcherContinuousPose {
  let hip: CGPoint
  let chest: CGPoint
  let throwingShoulder: CGPoint
  let gloveShoulder: CGPoint
  let leadHip: CGPoint
  let rearHip: CGPoint
  let elbow: CGPoint
  let wrist: CGPoint
  let gloveElbow: CGPoint
  let glove: CGPoint
  let knee: CGPoint
  let ankle: CGPoint
  let rearKnee: CGPoint
  let rearAnkle: CGPoint
  let lean: Double
  let turn: Double
  static let release = 1.0
  static let plant = 0.76
  static let upperArmLength = 64.0
  static let forearmLength = 66.0
  static let gloveUpperLength = 58.0
  static let gloveForearmLength = 54.0
  static let thighLength = 70.0
  static let shinLength = 74.0
  static let trunkLength = 80.0

  private struct Key {
    let time: Double
    // 골반 x/y, 몸 기울기, 투구 팔 두 각도, 글러브 팔 두 각도, 앞발 x/y, 뒷발 x/y, 회전.
    let values: [Double]
    init(_ time: Double, _ values: [Double]) { self.time = time; self.values = values }
  }
  // 앞발 착지 전에는 상체를 세우고, 착지 이후 몸통 회전과 짧은 팔 가속을 이어간다.
  // 각도는 회전 방향을 유지해 기록한다. 끝 자세의 -285도는 준비 자세의 75도와 같다.
  private static let keys: [Key] = [
    Key(0, [294, 320, 0, 75, -150, 80, -70, 215, 450, 354, 450, 0]),
    Key(0.12, [299, 318, -0.02, 65, -150, 55, -50, 225, 415, 354, 450, -0.04]),
    Key(0.28, [304, 315, -0.04, 5, -150, -45, 0, 252, 345, 354, 450, -0.12]),
    Key(0.36, [303, 315, -0.04, -15, -150, -70, 20, 260, 330, 354, 450, -0.14]),
    Key(0.44, [296, 319, -0.02, 20, -75, -100, -60, 245, 365, 354, 450, -0.12]),
    Key(0.55, [275, 326, 0, 70, 20, -135, -150, 195, 410, 354, 450, -0.08]),
    Key(0.68, [245, 328, 0.02, 10, -55, -150, -150, 140, 438, 345, 442, -0.04]),
    Key(0.76, [234, 326, 0.05, -15, -95, -150, -150, 128, 440, 335, 432, 0.02]),
    Key(0.86, [230, 324, 0.1, -25, -105, -200, -60, 128, 440, 330, 415, 0.16]),
    Key(0.94, [224, 322, 0.18, -35, -110, -230, -60, 128, 440, 332, 400, 0.3]),
    Key(1, [219, 320, 0.3, -65, -125, -245, -70, 128, 440, 339, 383, 0.42]),
    Key(1.045, [216, 320, 0.52, -120, -200, -255, -80, 128, 440, 342, 360, 0.48]),
    Key(1.1, [215, 320, 0.68, -185, -260, -260, -85, 128, 440, 346, 330, 0.5]),
    Key(1.22, [216, 320, 0.8, -225, -280, -260, -85, 128, 440, 350, 302, 0.48]),
    Key(1.38, [220, 321, 0.75, -240, -275, -260, -85, 128, 440, 345, 308, 0.4]),
    Key(1.55, [226, 322, 0.62, -250, -260, -265, -85, 128, 440, 318, 373, 0.3]),
    Key(1.85, [232, 328, 0.34, -270, -195, -275, -80, 128, 440, 302, 440, 0.14]),
    Key(2.15, [263, 322, 0.12, -285, -155, -280, -70, 185, 450, 330, 450, 0.04]),
    Key(2.65, [294, 320, 0, -285, -150, -280, -70, 215, 450, 354, 450, 0]),
  ]

  init(progress: Double) {
    let t = min(Self.keys.last!.time, max(0, progress))
    let i = min(Self.keys.count - 2, Self.keys.lastIndex(where: { $0.time <= t }) ?? 0)
    let a = Self.keys[i], b = Self.keys[i + 1]
    let previous = Self.keys[max(0, i - 1)], next = Self.keys[min(Self.keys.count - 1, i + 2)]
    let span = b.time - a.time, u = min(1, (t - a.time) / span)
    func sample(_ column: Int) -> Double {
      let av = a.values[column], bv = b.values[column], slope = (bv - av) / span
      // 각도 경계를 넘는 튕김을 막고, 방향이 바뀌는 지점에서만 속도를0으로 연결한다.
      func tangent(_ left: Double, _ right: Double) -> Double {
        guard left * right > 0 else { return 0 }
        return 2 * left * right / (left + right)
      }
      let before = i == 0 ? 0 : (av - previous.values[column]) / (a.time - previous.time)
      let after = i + 2 == Self.keys.count ? 0 : (next.values[column] - bv) / (next.time - b.time)
      let m0 = tangent(before, slope) * span, m1 = tangent(slope, after) * span
      let u2 = u * u, u3 = u2 * u
      return (2*u3 - 3*u2 + 1)*av + (u3 - 2*u2 + u)*m0 + (-2*u3 + 3*u2)*bv + (u3 - u2)*m1
    }
    let v = (0..<12).map(sample)
    func move(_ origin: CGPoint, angle: Double, length: Double) -> CGPoint {
      let wrapped = angle - floor(angle / 360) * 360, radians = wrapped * .pi / 180
      return CGPoint(x: origin.x + cos(radians)*length, y: origin.y + sin(radians)*length)
    }
    func joint(_ root: CGPoint, _ target: CGPoint) -> CGPoint {
      let dx = target.x - root.x, dy = target.y - root.y
      let distance = max(0.001, hypot(dx,dy))
      let along = (Self.thighLength*Self.thighLength - Self.shinLength*Self.shinLength + distance*distance) / (2*distance)
      let height = sqrt(max(0, Self.thighLength*Self.thighLength - along*along))
      return CGPoint(x: root.x + dx/distance*along - dy/distance*height,
                     y: root.y + dy/distance*along + dx/distance*height)
    }
    hip = CGPoint(x:v[0],y:v[1]); lean = v[2]; turn = v[11]
    let up = CGPoint(x:-sin(lean),y:-cos(lean)), right = CGPoint(x:cos(lean),y:-sin(lean))
    chest = CGPoint(x:hip.x + up.x*Self.trunkLength,y:hip.y + up.y*Self.trunkLength)
    throwingShoulder = CGPoint(x:chest.x + right.x*32,y:chest.y + right.y*32)
    gloveShoulder = CGPoint(x:chest.x - right.x*32,y:chest.y - right.y*32)
    leadHip = CGPoint(x:hip.x - 20,y:hip.y)
    rearHip = CGPoint(x:hip.x + 20,y:hip.y)
    elbow = move(throwingShoulder,angle:v[3],length:Self.upperArmLength)
    wrist = move(elbow,angle:v[4],length:Self.forearmLength)
    gloveElbow = move(gloveShoulder,angle:v[5],length:Self.gloveUpperLength)
    glove = move(gloveElbow,angle:v[6],length:Self.gloveForearmLength)
    ankle = t >= Self.plant && t <= 1.85 ? CGPoint(x:128,y:440) : CGPoint(x:v[7],y:v[8])
    rearAnkle = CGPoint(x:v[9],y:v[10])
    knee = joint(leadHip,ankle); rearKnee = joint(rearHip,rearAnkle)
  }
}

/// 같은 크기의 전신 원화만 교체한다. 분리한 머리·팔·다리 노드나 늘어나는 부위를 만들지 않는다.
enum PitcherMotionPlayback {
    static let followThrough = 0.42
    static let recovery = 0.70
    static var duration:Double {followThrough+recovery}
    static func progress(elapsed:Double)->Double {
        let t=max(0,elapsed)
        if t<=followThrough {return 1+0.78*t/followThrough}
        return 1.78+0.87*min(1,(t-followThrough)/recovery)
    }
}

@MainActor final class FullBodyPitcherNode: SKNode {
    private let body = SKSpriteNode()
    private let art: FullBodyPitcherArt.Prepared
    private(set) var handPoint = CGPoint.zero
    private(set) var leadFoot = CGPoint.zero
    private(set) var frameIndex = 0
    var hasVisibleHand: Bool { art.camera.frames[frameIndex].handVisible }
    var usesRefinedDelivery: Bool { art.refined != nil }
    var authoredCanvas: Double? { art.refined.map { Double($0.cell) } }
    var registrationAnchor: CGPoint {
        let f=art.camera.frames[0]
        return CGPoint(x:f.rearFoot[0]+f.offset[0],y:1-f.rearFoot[1]-f.offset[1])
    }
    init?(role: PlayerRole, appearance: PlayerAppearance, number: Int, hand: String) {
        let refined = role == .pitcher ? FullBodyPitcherArt.prepareRefined(appearance: appearance, number: number, hand: hand) : nil
        guard let art = refined ?? FullBodyPitcherArt.prepare(role:role,appearance:appearance,number:number,hand:hand) else { return nil }
        self.art = art
        super.init()
        name = "fullBodyPitcher"
        body.name = "pitcherWholeBody"
        addChild(body)
        // 투구 도중 처음 등장하는 자세가 텍스처 업로드를 기다리지 않게 한다.
        SKTexture.preload(art.textures) {}
    }
    required init?(coder:NSCoder) { fatalError("Storyboard initialization is not used") }
    static func recoveryOffset(progress:Double,camera:FullBodyPitcherArt.Camera) -> CGPoint {
        let frame=camera.frames[FullBodyPitcherArt.index(progress:progress)]
        guard progress>1.78 else {return CGPoint(x:frame.offset[0],y:frame.offset[1])}
        // 앞발 기준에서 준비 축발 기준으로 순간 이동하지 않고 전신만 제자리로 회수한다.
        let start=camera.frames[27].offset,end=camera.frames[31].offset
        let t=min(1,max(0,(progress-1.78)/(2.65-1.78))),ease=t*t*(3-2*t)
        return CGPoint(x:start[0]+(end[0]-start[0])*ease,y:start[1]+(end[1]-start[1])*ease)
    }
    func apply(progress:Double,canvas:Double,anchor:CGPoint) {
        if let refined = art.refined {
            frameIndex = refined.progress.lastIndex(where: { $0 <= progress }) ?? 0
        } else {
            frameIndex = FullBodyPitcherArt.index(progress:progress)
        }
        let frame = art.camera.frames[frameIndex]
        let texture = art.textures[frameIndex]
        if body.texture !== texture { body.texture = texture }
        let size = CGSize(width:canvas,height:canvas)
        if body.size != size { body.size = size }
        if body.anchorPoint != anchor { body.anchorPoint = anchor }
        // The V143 body atlas already includes the fixed-foot placement for every raster pose.
        let offset = usesRefinedDelivery ? CGPoint.zero : Self.recoveryOffset(progress:progress,camera:art.camera)
        let position = CGPoint(x:offset.x*canvas,y:-offset.y*canvas)
        if body.position != position { body.position = position }
        func point(_ value:[Double])->CGPoint {
            CGPoint(x:(value[0]+offset.x-anchor.x)*canvas,
                    y:(1-value[1]-offset.y-anchor.y)*canvas)
        }
        handPoint = point(frame.hand)
        leadFoot = point(frame.leadFoot)
    }
}
