import SwiftUI
import CoreText

/// Presentation only: dates and thresholds never change the saved calendar or fatigue.
enum ManagementDisplay {
    static func date(_ raw: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let value = formatter.date(from: raw) else { return raw }
        formatter.dateFormat = "M월 d일 (E)"
        return formatter.string(from: value)
    }
    static func fatigueLabel(_ value: Int) -> String { value <= 40 ? "양호" : value < 60 ? "주의" : "높음" }
    static func fatigueColor(_ value: Int) -> Color {
        Color(hex: value <= 40 ? 0x6bc291 : value < 60 ? 0xf0c35d : 0xf08d80)
    }
}

struct ManagementFacility: Identifiable {
    let id: String
    let title: String
    let status: String
    let x: CGFloat
    let y: CGFloat
    var recommended = false
    var prop: ManagementPropPlacement? = nil
    var preview: [String] = []
}

enum ManagementPropKind { case sign, radar, notebook, document, day, calendar }

struct ManagementPropPlacement {
    let x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat
    var kind = ManagementPropKind.sign
    var angle: Double = 0
    var titleOffset = CGSize.zero
    var bodyOffset = CGSize.zero
    var titleWidth: CGFloat = 0.22
    var bodyWidth: CGFloat = 0.20
    static func at(_ id: String) -> Self {
        switch id {
        case "clubhouse-game": .init(x: 0.5, y: 0.095, width: 0.25, height: 0)
        case "clubhouse-training": .init(x: 0.157, y: 0.203, width: 0.18, height: 0, angle: 18)
        case "clubhouse-career": .init(x: 0.855, y: 0.214, width: 0.29, height: 0, angle: -17, titleWidth: 0.25)
        case "clubhouse-player": .init(x: 0.884, y: 0.494, width: 0.23, height: 0, angle: 6, titleWidth: 0.21)
        case "clubhouse-rest": .init(x: 0.19, y: 0.712, width: 0.13, height: 0, angle: -10, titleOffset: .init(width: 0.013, height: 0), titleWidth: 0.11)
        case "facility-calendar": .init(x: 0.345, y: 0.666, width: 0.12, height: 0, kind: .day, bodyOffset: .init(width: -0.01, height: 0))
        case "facility-abilities": .init(x: 0.255, y: 0.347, width: 0.43, height: 0.16, kind: .radar)
        case "facility-profile": .init(x: 0.614, y: 0.237, width: 0.18, height: 0, titleWidth: 0.14)
        case "facility-traits": .init(x: 0.828, y: 0.419, width: 0.24, height: 0, titleWidth: 0.185)
        case "facility-records": .init(x: 0.349, y: 0.642, width: 0.30, height: 0.13, kind: .notebook, titleOffset: .init(width: 0, height: 0.039), bodyOffset: .init(width: 0, height: -0.020), titleWidth: 0.26)
        case "facility-positions": .init(x: 0.795, y: 0.642, width: 0.30, height: 0.13, kind: .notebook, titleOffset: .init(width: 0, height: 0.039), titleWidth: 0.25)
        case "facility-observation": .init(x: 0.542, y: 0.20, width: 0.38, height: 0.108, kind: .document, titleOffset: .init(width: 0, height: -0.038), bodyOffset: .init(width: 0, height: 0.014), titleWidth: 0.21, bodyWidth: 0.33)
        case "facility-goals": .init(x: 0.542, y: 0.308, width: 0.38, height: 0.108, kind: .document, titleOffset: .init(width: 0, height: -0.039), bodyOffset: .init(width: 0, height: 0.013), titleWidth: 0.21, bodyWidth: 0.33)
        case "facility-observation-calendar": .init(x: 0.416, y: 0.416, width: 0.13, height: 0.07, kind: .calendar, titleOffset: .init(width: 0, height: -0.024), bodyOffset: .init(width: 0, height: 0.006), titleWidth: 0.10, bodyWidth: 0.09)
        case "facility-review": .init(x: 0.544, y: 0.54, width: 0.25, height: 0.088, kind: .document, titleOffset: .init(width: 0, height: -0.023), bodyOffset: .init(width: -0.022, height: 0.003), titleWidth: 0.20, bodyWidth: 0.17)
        default: .init(x: 0.793, y: 0.55, width: 0.23, height: 0.088, kind: .document, titleOffset: .init(width: 0, height: -0.017), bodyOffset: .init(width: -0.022, height: 0.011), titleWidth: 0.18, bodyWidth: 0.17)
        }
    }
}

extension ManagementFacility {
    static func spatial(_ id: String, _ title: String, _ status: String, preview: [String] = [], recommended: Bool = false) -> Self {
        let prop = ManagementPropPlacement.at(id)
        return .init(id: id, title: title, status: status, x: prop.x, y: prop.y, recommended: recommended, prop: prop, preview: preview)
    }
}

/// Official OFL font is registered once from the bundled data asset, without changing Info.plist.
enum ManagementPixelFont {
    static let name: String? = {
        guard let data = NSDataAsset(name: "ManagementPixelFontV59")?.data,
              let provider = CGDataProvider(data: data as CFData), let font = CGFont(provider),
              let name = font.postScriptName as String? else { return nil }
        var error: Unmanaged<CFError>?
        guard CTFontManagerRegisterGraphicsFont(font, &error) else { return nil }
        return name
    }()
    static func font(_ size: CGFloat) -> Font {
        name.map { .custom($0, fixedSize: size) } ?? .system(size: size, weight: .semibold, design: .monospaced)
    }
}

struct ManagementChalkRadar: View {
    let values: [HomeAbilityValue]
    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size, center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = max(10, min(size.width / 2 - 24, size.height / 2 - 19))
            ZStack {
                Canvas { context, _ in
                    func point(_ i: Int, _ radius: Double) -> CGPoint {
                        let angle = Double(i) * 2 * .pi / Double(max(1, values.count)) - .pi / 2
                        return .init(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
                    }
                    for k in [0.25, 0.5, 0.75, 1.0] {
                        let r = radius * k
                        context.stroke(Path(ellipseIn: CGRect(x: center.x-r, y: center.y-r, width: r*2, height: r*2)), with: .color(Color(hex: 0xbfd3b1).opacity(0.4)))
                    }
                    var shape = Path()
                    for (i, value) in values.enumerated() {
                        var axis = Path(); axis.move(to: center); axis.addLine(to: point(i, radius))
                        context.stroke(axis, with: .color(Color(hex: 0xbfd3b1).opacity(0.4)))
                        let p = point(i, radius * min(100, max(0, value.current)) / 100)
                        if i == 0 { shape.move(to: p) } else { shape.addLine(to: p) }
                    }
                    shape.closeSubpath(); context.fill(shape, with: .color(GameTheme.gold.opacity(0.4))); context.stroke(shape, with: .color(GameTheme.gold), lineWidth: 2)
                }
                ForEach(Array(values.enumerated()), id: \.element.id) { i, value in
                    let angle = Double(i) * 2 * .pi / Double(max(1, values.count)) - .pi / 2
                    Text(value.id == "homeVelocity" ? "구속" : value.label).font(ManagementPixelFont.font(12))
                        .foregroundStyle(Color(hex: 0xfff4d4)).fixedSize()
                        .position(x: center.x + cos(angle) * (radius + 13), y: center.y + sin(angle) * (radius + 13))
                }
            }
        }.accessibilityHidden(true)
    }
}

struct ManagementFacilityStyle: ButtonStyle {
    let recommended: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.horizontal, 10).padding(.vertical, 8)
            .frame(minHeight: 44)
            .foregroundStyle(ManagementTheme.Spatial.onCanvas)
            .background(ManagementTheme.Spatial.wood, in: ManagementStepFrame())
            .overlay(ManagementStepFrame().stroke(recommended ? GameTheme.gold : Color(hex: 0xb48243), lineWidth: recommended ? 3 : 2))
            .offset(y: configuration.isPressed ? 2 : 0)
    }
}

/// A full room with controls in safe areas. Short screens use a readable facility list.
struct ManagementSpatialRoom<Header: View, Action: View>: View {
    let asset: String
    let title: String
    let facilities: [ManagementFacility]
    @Binding var selection: ManagementTab
    let choose: (String) -> Void
    let home: () -> Void
    @ViewBuilder let header: Header
    @ViewBuilder let action: Action
    @Environment(\.dynamicTypeSize) private var typeSize
    var propAbilities: [HomeAbilityValue] = []
    private var usesProps: Bool { asset.hasSuffix("V59") }

    var body: some View {
        if usesProps { propRoom } else { legacyRoom }
    }
    func spatialAbilities(_ values: [HomeAbilityValue]) -> Self {
        var copy = self; copy.propAbilities = values; return copy
    }
    private var legacyRoom: some View {
        GeometryReader { geometry in
            ZStack {
                Image(asset).resizable().interpolation(.none).scaledToFill()
                    .frame(width: geometry.size.width, height: geometry.size.height)
                    .clipped()
                    .accessibilityHidden(true)
                LinearGradient(colors: [ManagementTheme.Spatial.canvas, .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 210).frame(maxHeight: .infinity, alignment: .top).ignoresSafeArea(edges: .top).allowsHitTesting(false)
                VStack(spacing: 0) {
                    if typeSize.isAccessibilitySize {
                        ScrollView {
                            VStack(spacing: 0) {
                                header
                                roomToolbar
                                facilityList(columns: 1)
                            }
                        }.accessibilityIdentifier("roomFacilityList")
                    } else {
                        header
                        roomToolbar
                        if geometry.size.height < ManagementTheme.Spatial.shortContentHeight {
                            ScrollView { facilityList(columns: 2) }.accessibilityIdentifier("roomFacilityList")
                        } else {
                            GeometryReader { room in
                                ForEach(facilities) { facility in
                                    facilityButton(facility).frame(width: min(ManagementTheme.Spatial.facilityMaxWidth, room.size.width * 0.4))
                                        .position(x: max(82, min(room.size.width - 82, room.size.width * facility.x)),
                                                  y: max(40, min(room.size.height - 42, room.size.height * facility.y)))
                                }
                            }
                        }
                    }
                    VStack(spacing: 8) {
                        action.frame(minHeight: ManagementTheme.Control.primaryHeight).padding(.horizontal, ManagementTheme.Spatial.screenInset)
                        ManagementTabBar(selection: $selection)
                    }.dynamicTypeSize(...DynamicTypeSize.accessibility1)
                        .padding(.top, 8).background(ManagementTheme.Spatial.canvas.opacity(0.97))
                }
            }.frame(width: geometry.size.width, height: geometry.size.height).clipped()
        }
        .background(ManagementTheme.Spatial.canvas.ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .preferredColorScheme(.dark)
    }
    private var propRoom: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if typeSize.isAccessibilitySize {
                    ScrollView { VStack(spacing: 0) { header; roomToolbar; facilityList(columns: 1) } }
                        .accessibilityIdentifier("roomFacilityList")
                } else {
                    header
                    GeometryReader { stage in
                        let ratio: CGFloat = 1660.0 / 948
                        let scrolling = stage.size.height / max(1, stage.size.width) < 1.4
                        let width = scrolling ? stage.size.width : max(stage.size.width, stage.size.height / ratio)
                        let height = width * ratio
                        ZStack(alignment: .top) {
                            if scrolling {
                                ScrollViewReader { proxy in
                                    ScrollView(.vertical) { propScene(width: width, height: height).id("propSceneTop") }
                                        .onChange(of: selection) { _, _ in proxy.scrollTo("propSceneTop", anchor: .top) }
                                        .accessibilityIdentifier("roomPropScroll")
                                }
                            } else {
                                propScene(width: width, height: height)
                                    .position(x: stage.size.width / 2, y: stage.size.height / 2)
                            }
                            HStack {
                                if selection != .home {
                                    Button { home() } label: { Text("‹ 홈").font(ManagementPixelFont.font(14)).padding(.horizontal, 10).frame(minHeight: 44).background(ManagementTheme.Spatial.canvas.opacity(0.85)) }
                                        .accessibilityIdentifier("roomBackHome")
                                }
                                Spacer()
                                Button { choose("clubhouse-settings") } label: { Text("설정").font(ManagementPixelFont.font(14)).padding(.horizontal, 10).frame(minHeight: 44).background(ManagementTheme.Spatial.canvas.opacity(0.85)) }
                                    .accessibilityIdentifier("clubhouse-settings")
                            }.buttonStyle(.plain).foregroundStyle(ManagementTheme.Spatial.onCanvas)

                        }.clipped()
                    }
                }
                VStack(spacing: 8) {
                    action.frame(minHeight: ManagementTheme.Control.primaryHeight).padding(.horizontal, 12)
                    ManagementTabBar(selection: $selection)
                }.dynamicTypeSize(...DynamicTypeSize.accessibility1).padding(.top, 8).background(ManagementTheme.Spatial.canvas)
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }.background(ManagementTheme.Spatial.canvas.ignoresSafeArea()).toolbar(.hidden, for: .navigationBar).preferredColorScheme(.dark)
    }
    private func propScene(width: CGFloat, height: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            Image(asset).resizable().interpolation(.none).frame(width: width, height: height).accessibilityHidden(true)
            ForEach(facilities) { facility in
                if let p = facility.prop {
                    Button { choose(facility.id) } label: {
                        ZStack {
                            if p.kind == .radar {
                                if propAbilities.count >= 3 {
                                    ManagementChalkRadar(values: propAbilities).frame(width: width * 0.405, height: width * 0.27)
                                } else { Text("자료 확인").font(ManagementPixelFont.font(12)) }
                            } else {
                                if p.kind != .day {
                                    Text(facility.title).font(ManagementPixelFont.font(facility.id == "clubhouse-rest" ? 16 : max(12, min(p.kind == .notebook ? 16 : 14, width * 0.036))))
                                        .kerning(facility.id == "clubhouse-player" ? -0.8 : -0.2)
                                        .lineLimit(1).foregroundStyle(Color(hex: 0xfff0ce))
                                        .frame(width: width * p.titleWidth).rotationEffect(.degrees(p.angle))
                                        .offset(x: width * p.titleOffset.width, y: height * p.titleOffset.height)
                                }
                                if !facility.preview.isEmpty {
                                    VStack(spacing: p.kind == .calendar ? 0 : 2) {
                                        ForEach(Array(facility.preview.enumerated()), id: \.offset) { _, line in Text(line).lineLimit(1).truncationMode(.tail) }
                                    }.font(ManagementPixelFont.font(p.kind == .day ? 18 : 12))
                                        .foregroundStyle(Color(hex: 0x19394b))
                                        .frame(width: width * p.bodyWidth)
                                        .rotationEffect(.degrees(p.kind == .day ? -8 : 0))
                                        .offset(x: width * p.bodyOffset.width, y: height * p.bodyOffset.height)
                                }
                            }
                        }.frame(width: max(44, width * p.width), height: max(44, height * p.height)).contentShape(Rectangle())
                    }.buttonStyle(.plain).foregroundStyle(ManagementTheme.Spatial.onCanvas)
                        .accessibilityLabel(facility.title + " · " + facility.status)
                        .accessibilityHint("상세 열기").accessibilityIdentifier(facility.id)
                        .position(x: width * p.x, y: height * p.y)
                }
            }
        }.frame(width: width, height: height)
    }
    private var roomToolbar: some View {
        HStack {
            if selection != .home {
                Button(action: home) { Text("‹ 클럽하우스").font(.subheadline.bold()).padding(.horizontal, 12).frame(minHeight: 44) }
                    .buttonStyle(.plain).accessibilityIdentifier("roomBackHome")
            }
            if usesProps { Button("설정") { choose("clubhouse-settings") }.frame(minHeight: 44).accessibilityIdentifier("clubhouse-settings") }
            Spacer()
            Text(title).font(.subheadline.bold()).padding(.horizontal, 12)
        }.foregroundStyle(ManagementTheme.Spatial.onCanvas).background(ManagementTheme.Spatial.canvas.opacity(0.86))
    }
    private func facilityList(columns: Int) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 16) {
            ForEach(facilities) { facility in facilityButton(facility) }
        }.padding(16)
    }
    private func facilityButton(_ facility: ManagementFacility) -> some View {
        Button { choose(facility.id) } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(facility.title).managementFont(.label)
                    Spacer(minLength: 0)
                    Text("›").font(.headline)
                }
                Text(facility.status).font(.caption).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(ManagementFacilityStyle(recommended: facility.recommended))
            .accessibilityIdentifier(facility.id)
            .accessibilityHint("시설 상세 열기")
    }
}

struct ManagementSpatialHeader: View {
    let player: CareerPlayer
    let affiliation: String
    let age: Int
    let used: Bool
    let pending: Bool
    let profile: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 10) {
                Button(action: profile) {
                    PixelPlayer(appearance: player.appearance).frame(width: 40, height: 48)
                }.accessibilityLabel("선수 선택 · 프로필").accessibilityIdentifier("roomProfile")
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(player.name)  #\(player.jerseyNumber)").font(.headline).accessibilityIdentifier("homePlayerName")
                    HStack(spacing: 6) {
                        if let school = SchoolCatalog.bundled.first(where: { $0.id == player.schoolID }) {
                            SchoolCrest(school: school).frame(width: 24, height: 26)
                        }
                        Text(affiliation).font(.caption).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("homeSchool")
                    }
                    Text("\(age)세 · \(player.role.label) · \(player.roleDetail)").font(.caption).accessibilityIdentifier("homeAge")
                }.frame(maxWidth: .infinity, alignment: .leading)
                if !typeSize.isAccessibilitySize {
                    Text(ManagementDisplay.date(player.gameDate)).font(.subheadline.bold()).accessibilityIdentifier("calendarDate")
                }
            }
            if typeSize.isAccessibilitySize {
                Text(ManagementDisplay.date(player.gameDate)).font(.body.bold()).accessibilityIdentifier("calendarDate")
            }
            let statusLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(spacing: 8))
            statusLayout {
                Text("피로 \(player.fatigue)/100 · \(ManagementDisplay.fatigueLabel(player.fatigue))")
                    .foregroundStyle(ManagementDisplay.fatigueColor(player.fatigue)).accessibilityIdentifier("homeFatigue")
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Text(pending ? "훈련 이어하기" : "행동 \(used ? 0 : 1)/1").accessibilityIdentifier("calendarAction")
            }.font(.caption.bold())
        }.padding(.horizontal, 12).padding(.vertical, 8)
            .foregroundStyle(ManagementTheme.Spatial.onCanvas).background(ManagementTheme.Spatial.canvas.opacity(0.94))
    }
}

enum ManagementRoomDetail: Equatable, Identifiable {
    case player(ManagementPlayerSection), training(ManagementTrainingSection)
    case game(ManagementGameSection), career(ManagementCareerSection)
    case profile, gameEntry
    var id: String {
        switch self {
        case .player: "player"
        case .training: "training"
        case .game: "game"
        case .career: "career"
        case .profile: "profile"
        case .gameEntry: "gameEntry"
        }
    }
    var title: String {
        switch self {
        case .player: "선수 수첩"
        case .training: "훈련 준비"
        case .game: "경기장 안내"
        case .career: "스카우트 서류"
        case .profile: "나의 선수"
        case .gameEntry: "오늘 경기"
        }
    }
}
