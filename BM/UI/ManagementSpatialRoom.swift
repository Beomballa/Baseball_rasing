import SwiftUI
import CoreText

/// Presentation only: dates and thresholds never change the saved calendar or fatigue.
enum ManagementDisplay {
    static func date(_ raw: String) -> String { date(raw, includeYear: false) }
    static func date(_ raw: String, includeYear: Bool) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "ko_KR")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let value = formatter.date(from: raw) else { return raw }
        formatter.dateFormat = includeYear ? "yyyy년 M월 d일 (E)" : "M월 d일 (E)"
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

enum ManagementPropKind { case sign, radar, notebook, document, day, calendar, roomSign, roomNote, roomChalk, trainingBook }

struct ManagementPropPlacement {
    let x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat
    var kind = ManagementPropKind.sign
    var angle: Double = 0
    var titleOffset = CGSize.zero
    var bodyOffset = CGSize.zero
    var titleWidth: CGFloat = 0.22
    var bodyWidth: CGFloat = 0.20
    func hitRect(in size: CGSize) -> CGRect {
        let w = max(ManagementTheme.Control.hit, size.width * width)
        let h = max(ManagementTheme.Control.hit, size.height * height)
        let cx = min(size.width - w / 2, max(w / 2, size.width * x))
        let cy = min(size.height - h / 2, max(h / 2, size.height * y))
        return CGRect(x: cx - w / 2, y: cy - h / 2, width: w, height: h)
    }
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
    static func object(_ id: String, _ title: String, _ status: String, x: CGFloat, y: CGFloat, width: CGFloat, height: CGFloat = 0.06,
                       kind: ManagementPropKind = .roomSign, preview: [String] = [], recommended: Bool = false) -> Self {
        let prop = ManagementPropPlacement(x: x, y: y, width: width, height: height, kind: kind)
        return .init(id: id, title: title, status: status, x: x, y: y, recommended: recommended, prop: prop, preview: preview)
    }
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
    static func readable(_ type: ManagementType) -> Font {
        name.map { .custom($0, size: type.size, relativeTo: type.relativeTo) } ?? .system(type.relativeTo, design: .monospaced)
    }
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

struct ManagementPropButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
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
struct ManagementSpatialRoom<Header: View>: View {
    let asset: String
    let title: String
    let facilities: [ManagementFacility]
    @Binding var selection: ManagementTab
    let choose: (String) -> Void
    let home: () -> Void
    @ViewBuilder let header: Header
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .caption2) private var matchupRoleWidth = 51.0
    @ScaledMetric(relativeTo: .caption2) private var matchupVenueWidth = 34.0
    var propAbilities: [HomeAbilityValue] = []
    var homeVenue: StadiumIdentity? = nil
    var todayAction: ClubhouseTodayAction? = nil
    private var usesProps: Bool { asset.hasSuffix("V59") || asset.hasSuffix("V62") }

    var body: some View {
        if selection == .home, let todayAction { clubhouse(todayAction) }
        else if usesProps { propRoom }
        else { legacyRoom }
    }
    func spatialAbilities(_ values: [HomeAbilityValue]) -> Self {
        var copy = self; copy.propAbilities = values; return copy
    }
    func spatialHomeVenue(_ stadium: StadiumIdentity?) -> Self {
        var copy = self; copy.homeVenue = stadium; return copy
    }
    func spatialTodayAction(_ action: ClubhouseTodayAction) -> Self {
        var copy = self; copy.todayAction = action; return copy
    }
    private static var clubhouseShortcutIDs: [String] {
        ["clubhouse-training", "clubhouse-rest", "facility-calendar", "clubhouse-player"]
    }
    private var clubhouseSigns: [ManagementFacility] {
        let ids = ["clubhouse-game", "clubhouse-training", "clubhouse-career", "clubhouse-player", "clubhouse-rest"]
        return ids.compactMap { id in facilities.first { $0.id == id } }
    }
    private var clubhouseShortcuts: [ManagementFacility] {
        Self.clubhouseShortcutIDs.compactMap { id in facilities.first { $0.id == id } }
    }
    private var clubhouseExtraFacilities: [ManagementFacility] {
        facilities.filter { ["facility-observation", "facility-review"].contains($0.id) }
    }
    private func clubhouse(_ today: ClubhouseTodayAction) -> some View {
        GeometryReader { viewport in
            VStack(spacing: 0) {
                if typeSize.isAccessibilitySize || viewport.size.width < 340 {
                    clubhouseReadingLayout(today, width: viewport.size.width)
                } else {
                    header
                    GeometryReader { stage in
                        ScrollView {
                            let width = min(520, stage.size.width)
                            // On short phones the scene can scroll, so the bottom board does not hide the room signs.
                            let height = max(560, stage.size.height)
                            VStack(spacing: 0) {
                                clubhouseScene(today, width: width, height: height)
                                facilityList(columns: 2, items: clubhouseExtraFacilities)
                            }.frame(width: width).frame(maxWidth: .infinity)
                        }.accessibilityIdentifier("roomFacilityList")
                    }
                }
                ManagementTabBar(selection: $selection)
            }
        }.foregroundStyle(ManagementTheme.Spatial.onCanvas)
            .background(ManagementTheme.Spatial.canvas.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar).preferredColorScheme(.dark)
    }
    private func clubhouseReadingLayout(_ today: ClubhouseTodayAction, width: CGFloat) -> some View {
        ScrollView {
            VStack(spacing: 12) {
                clubhouseReadingTitle.padding(.horizontal, 12)
                clubhouseTodayPanel(today, stacked: true).padding(.horizontal, 12)
                Button("휴식") { choose("clubhouse-rest") }
                    .buttonStyle(ManagementButtonStyle(variant: .secondary))
                    .padding(.horizontal, 12).accessibilityIdentifier("clubhouse-rest")
                header
                clubhouseArt.frame(width: width)
                let items = clubhouseShortcuts.filter { $0.id != "clubhouse-rest" } + clubhouseExtraFacilities
                    + clubhouseSigns.filter { $0.id == "clubhouse-game" || $0.id == "clubhouse-career" }
                facilityList(columns: 1, items: items)
            }.padding(.top, 6)
        }.accessibilityIdentifier("roomFacilityList")
    }

    private var clubhouseReadingTitle: some View {
        let heading = Text(title).managementFont(.sectionTitle).accessibilityAddTraits(.isHeader)
        return ViewThatFits(in: .horizontal) {
            HStack {
                heading.fixedSize(horizontal: true, vertical: false)
                Spacer(minLength: 8)
                if typeSize.isAccessibilitySize { ManagementSettingsButton { choose("clubhouse-settings") } }
            }
            VStack(alignment: .leading, spacing: 6) {
                heading.fixedSize(horizontal: false, vertical: true)
                if typeSize.isAccessibilitySize { ManagementSettingsButton { choose("clubhouse-settings") } }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    private func clubhouseScene(_ today: ClubhouseTodayAction, width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 0) {
            GeometryReader { scene in
                let restSign = ManagementPropPlacement.at("clubhouse-rest")
                let clearance = ManagementTheme.Control.hit / 2 + 8
                // Reserve room for the lowest sign's full tap area even when the task board wraps.
                let artHeight = min(height, max(scene.size.height, (scene.size.height - clearance) / restSign.y))
                propScene(width: width, height: artHeight, items: clubhouseSigns, distinguishesShortcuts: true)
            }
            VStack(spacing: 8) {
                clubhouseTodayPanel(today, stacked: false)
                HStack(spacing: 6) {
                    ForEach(clubhouseShortcuts) { facility in clubhouseShortcut(facility) }
                }
            }.padding(.horizontal, 12).padding(.bottom, 10)
        }
        .frame(width: width, height: height)
        .background {
            Image(asset).resizable().interpolation(.none).frame(width: width, height: height)
                .accessibilityHidden(true)
        }.clipped()
    }
    private func clubhouseShortcut(_ facility: ManagementFacility) -> some View {
        Button { choose(facility.id) } label: {
            VStack(spacing: 4) {
                ClubhouseShortcutIcon(facilityID: facility.id).frame(width: 36, height: 28)
                Text(facility.title).font(ManagementPixelFont.readable(.helper))
                    .lineLimit(2).minimumScaleFactor(0.75).multilineTextAlignment(.center)
            }.padding(.vertical, 5).frame(maxWidth: .infinity, minHeight: 58)
                .contentShape(Rectangle())
                .foregroundStyle(ManagementTheme.Spatial.onCanvas)
                .background(Color(hex: 0x32241e), in: ManagementStepFrame())
                .overlay { ManagementStepFrame().strokeBorder(GameTheme.gold, lineWidth: 2) }
        }.buttonStyle(ManagementPropButtonStyle()).accessibilityLabel(facility.title)
            .accessibilityHint(facility.status).accessibilityIdentifier(facility.id)
    }
    private func clubhouseTodayPanel(_ today: ClubhouseTodayAction, stacked: Bool) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text("오늘 할 일").font(ManagementPixelFont.readable(.label)).accessibilityAddTraits(.isHeader)
                if !stacked, let heading = today.heading {
                    Spacer(minLength: 0)
                    clubhouseTodayHeading(heading)
                }
            }
            if stacked {
                clubhouseTodayButton(today, compact: false)
                if let heading = today.heading { clubhouseTodayHeading(heading) }
                clubhouseTodayDetails(today)
            } else {
                Rectangle().fill(GameTheme.boardLine).frame(height: 1).accessibilityHidden(true)
                HStack(spacing: 10) {
                    clubhouseTodayDetails(today).frame(maxWidth: .infinity, alignment: .leading)
                    Rectangle().fill(GameTheme.boardLine).frame(width: 1, height: 44).accessibilityHidden(true)
                    clubhouseTodayButton(today, compact: true).frame(width: 105)
                }
            }
        }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: 0x0e293d).opacity(0.97), in: ManagementStepFrame())
            .overlay { ManagementStepFrame().strokeBorder(GameTheme.boardLine, lineWidth: 2) }
            .accessibilityElement(children: .contain).accessibilityIdentifier("homeTodayPanel")
    }
    private func clubhouseTodayHeading(_ heading: String) -> some View {
        Text(heading).font(ManagementPixelFont.readable(.helper)).foregroundStyle(GameTheme.boardInk)
            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("homeTodayStatus")
    }
    @ViewBuilder private func clubhouseTodayDetails(_ today: ClubhouseTodayAction) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            if !today.matchup.isEmpty { clubhouseMatchup(today.matchup) }
            if let detail = today.detail {
                Text(detail).font(.footnote).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("homeTodayDetail")
            }
            if let attempts = today.trainingAttempts {
                Text("\(attempts)/5회 완료").font(.caption.monospacedDigit())
                    .accessibilityIdentifier("homeTodayProgress")
                HStack(spacing: 3) {
                    ForEach(0..<5) { index in
                        Rectangle().fill(index < attempts ? GameTheme.growth : GameTheme.boardLine)
                    }
                }.frame(maxWidth: 110).frame(height: 5).accessibilityHidden(true)
            }
        }
    }
    private func clubhouseMatchup(_ rows: [ClubhouseTodayAction.MatchupRow]) -> some View {
        VStack(spacing: 3) {
            ForEach(Array(rows.enumerated()), id: \.offset) { index, row in
                if index > 0 {
                    Rectangle().fill(GameTheme.boardLine.opacity(0.55)).frame(height: 1)
                        .accessibilityHidden(true)
                }
                if typeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            matchupRole(row)
                            Spacer(minLength: 8)
                            matchupVenue(row)
                        }
                        matchupName(row)
                    }.padding(.vertical, 4)
                } else {
                    HStack(spacing: 7) {
                        matchupRole(row).frame(width: matchupRoleWidth, alignment: .leading)
                        matchupName(row)
                        matchupVenue(row)
                    }
                }
            }
        }.foregroundStyle(GameTheme.boardInk)
    }

    private func matchupRole(_ row: ClubhouseTodayAction.MatchupRow) -> some View {
        HStack(spacing: 4) {
            Rectangle().fill(row.isOwn ? GameTheme.gold : Color.clear)
                .frame(width: 5, height: 5).accessibilityHidden(true)
            Text(row.isOwn ? "내 팀" : "상대 팀")
                .font(.caption2.weight(.semibold))
                .fixedSize(horizontal: !typeSize.isAccessibilitySize, vertical: true)
                .accessibilityIdentifier(row.isOwn ? "homeTodayOwnRole" : "homeTodayOpponentRole")
        }
    }

    private func matchupName(_ row: ClubhouseTodayAction.MatchupRow) -> some View {
        Text(row.team).font(ManagementPixelFont.readable(.helper))
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1)
            .accessibilityIdentifier(row.isOwn ? "homeTodayOwnTeam" : "homeTodayOpponent")
    }

    private func matchupVenue(_ row: ClubhouseTodayAction.MatchupRow) -> some View {
        Text(row.isHome ? "홈" : "원정")
            .font(.caption2.weight(.semibold)).fixedSize(horizontal: true, vertical: false)
            .padding(.horizontal, typeSize.isAccessibilitySize ? 6 : 0).padding(.vertical, 2)
            .frame(width: typeSize.isAccessibilitySize ? nil : matchupVenueWidth)
            .background(Color(hex: 0x29495d), in: ManagementStepFrame())
            .accessibilityIdentifier(row.isOwn ? "homeTodayOwnSide" : "homeTodayOpponentSide")
    }
    private func clubhouseTodayButton(_ today: ClubhouseTodayAction, compact: Bool) -> some View {
        Button(today.buttonTitle) { choose("homeTodayAction") }
            .buttonStyle(ManagementButtonStyle(compact: compact)).accessibilityIdentifier("homeTodayAction")
    }
    private var clubhouseArt: some View {
        let art = homeVenue.flatMap { ManagementHomeVenueArt.art(asset: asset, selection: .home, stadium: $0) }
        return GeometryReader { geometry in
            let width = geometry.size.width
            let height = width * (1660.0 / 948)
            (art.map { Image(uiImage: $0.image) } ?? Image(asset))
                .resizable().interpolation(.none).frame(width: width, height: height)
                .offset(y: -max(0, height - geometry.size.height) * 0.31)
                .accessibilityHidden(true)
        }.frame(height: typeSize.isAccessibilitySize ? 136 : 188).clipped()
            .overlay(ManagementStepFrame().strokeBorder(GameTheme.boardLine, lineWidth: 1).allowsHitTesting(false))
            .padding(.horizontal, 12)
            .accessibilityElement(children: .ignore)
            .accessibilityIdentifier(art.flatMap { _ in homeVenue.map { "managementHomeVenue-" + $0.key } } ?? "managementRoomScene-home")
            .accessibilityLabel("클럽하우스")
            .accessibilityValue(art?.venueName ?? "")
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
                    ManagementTabBar(selection: $selection)
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
                    ScrollView { VStack(spacing: 12) { header; roomToolbar; facilityList(columns: 1) } }
                        .accessibilityIdentifier("roomFacilityList")
                } else {
                    header
                    GeometryReader { stage in
                        let ratio: CGFloat = 1660.0 / 948
                        let scrolling = stage.size.width * ratio > stage.size.height
                        let width = stage.size.width
                        let height = width * ratio
                        ZStack(alignment: .top) {
                            if scrolling {
                                ScrollViewReader { proxy in
                                    ScrollView(.vertical) {
                                        propScene(width: width, height: height).id("propSceneTop")
                                    }
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
                                ManagementSettingsButton { choose("clubhouse-settings") }
                            }.buttonStyle(.plain).foregroundStyle(ManagementTheme.Spatial.onCanvas)

                        }
                        .clipped()
                    }
                }
                ManagementTabBar(selection: $selection)
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }.background(ManagementTheme.Spatial.canvas.ignoresSafeArea()).toolbar(.hidden, for: .navigationBar).preferredColorScheme(.dark)
    }
    private func propScene(width: CGFloat, height: CGFloat, items: [ManagementFacility]? = nil,
                           distinguishesShortcuts: Bool = false) -> some View {
        let venue = homeVenue.flatMap { stadium in
            ManagementHomeVenueArt.art(asset: asset, selection: selection, stadium: stadium)
                .map { (stadium: stadium, art: $0) }
        }
        return ZStack(alignment: .topLeading) {
            (venue.map { Image(uiImage: $0.art.image) } ?? Image(asset))
                .resizable().interpolation(.none).frame(width: width, height: height).accessibilityHidden(true)
            ForEach(items ?? facilities) { facility in
                if let p = facility.prop {
                    Button { choose(facility.id) } label: {
                        ZStack {
                            if p.kind == .trainingBook {
                                ZStack {
                                    Rectangle().fill(ManagementTheme.Spatial.wood)
                                    HStack(spacing: 2) {
                                        Rectangle().fill(GameTheme.gold).frame(width: 5)
                                        Text(facility.title).font(ManagementPixelFont.font(13)).multilineTextAlignment(.center)
                                            .foregroundStyle(GameTheme.navy).frame(maxWidth: .infinity, maxHeight: .infinity)
                                            .background(GameTheme.boardInk)
                                    }.padding(4)
                                }.frame(width: width * p.width, height: height * p.height)
                                    .rotationEffect(.degrees(-8))
                            } else if [.roomSign, .roomNote, .roomChalk].contains(p.kind) {
                                VStack(spacing: 4) {
                                    Text(facility.title).font(ManagementPixelFont.font(13)).lineLimit(1).minimumScaleFactor(0.75)
                                    if !facility.preview.isEmpty {
                                        ForEach(facility.preview, id: \.self) { line in Text(line).font(ManagementPixelFont.font(12)).lineLimit(2) }
                                    }
                                }.foregroundStyle(p.kind == .roomNote ? GameTheme.navy : GameTheme.boardInk)
                                    .multilineTextAlignment(.center).frame(width: width * p.width * 0.88)
                            } else if p.kind == .radar {
                                if propAbilities.count >= 3 {
                                    ManagementChalkRadar(values: propAbilities).frame(width: width * 0.405, height: width * 0.27)
                                } else { Text("자료 확인").font(ManagementPixelFont.font(12)) }
                            } else {
                                if p.kind != .day {
                                    Text(facility.title).font(ManagementPixelFont.font(facility.id == "clubhouse-rest" ? 16 : max(12, min(p.kind == .notebook ? 16 : 14, width * 0.036))))
                                        .kerning(facility.id == "clubhouse-player" ? -0.8 : -0.2)
                                        .lineLimit(1).foregroundStyle(Color(hex: 0xfff0ce))
                                        .frame(width: width * p.titleWidth).rotationEffect(.degrees(distinguishesShortcuts
                                            ? atan(tan(p.angle * .pi / 180) * Double(height / width) / (1659.0 / 948)) * 180 / .pi
                                            : p.angle))
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
                        }
                        // Keep artwork centered on the prop even when the minimum hit target is clamped at an edge.
                        .offset(x: width * p.x - p.hitRect(in: .init(width: width, height: height)).midX,
                                y: height * p.y - p.hitRect(in: .init(width: width, height: height)).midY)
                        .frame(width: max(44, width * p.width), height: max(44, height * p.height)).contentShape(Rectangle())
                    }.buttonStyle(ManagementPropButtonStyle()).foregroundStyle(ManagementTheme.Spatial.onCanvas)
                        .accessibilityLabel(facility.title + " · " + facility.status)
                        .accessibilityHint("상세 열기")
                        .accessibilityIdentifier(distinguishesShortcuts && Self.clubhouseShortcutIDs.contains(facility.id)
                            ? facility.id.replacingOccurrences(of: "clubhouse-", with: "clubhouseSign-") : facility.id)
                        .position(x: p.hitRect(in: .init(width: width, height: height)).midX,
                                  y: p.hitRect(in: .init(width: width, height: height)).midY)
                }
            }
        }.frame(width: width, height: height)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier(venue.map { "managementHomeVenue-" + $0.stadium.key } ?? "managementRoomScene-" + selection.rawValue)
            .accessibilityLabel(title)
            .accessibilityValue(venue?.art.venueName ?? "")
    }
    private var roomToolbar: some View {
        HStack {
            if selection != .home {
                Button(action: home) { Text("‹ 클럽하우스").font(.subheadline.bold()).padding(.horizontal, 12).frame(minHeight: 44) }
                    .buttonStyle(.plain).accessibilityIdentifier("roomBackHome")
            }
            if usesProps { ManagementSettingsButton { choose("clubhouse-settings") } }
            Spacer()
            Text(title).font(.subheadline.bold()).padding(.horizontal, 12)
        }.foregroundStyle(ManagementTheme.Spatial.onCanvas).background(ManagementTheme.Spatial.canvas.opacity(0.86))
    }
    private func facilityList(columns: Int, items: [ManagementFacility]? = nil) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: columns), spacing: 16) {
            ForEach(items ?? facilities) { facility in facilityButton(facility) }
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

private struct ClubhouseShortcutIcon: View {
    let facilityID: String

    private var rows: [String] {
        switch facilityID {
        case "clubhouse-training":
            ["................", ".NNNNNNNNNNNNN..", ".NGGGGGGGGGGGN..", ".NG.G.G.G.G.GN..",
             ".NGGGGGGGGGGGN..", ".NG.G.G.G.G.GN..", ".NGGGGGGGGGGGN..", ".NG.G.G.G.WWGN..",
             ".NGGGGGGGWRWWN..", ".NG.G.G.GWWWWN..", ".NNNNNNNNNWWNN..", "................"]
        case "clubhouse-rest":
            ["................", "..NNNNNNNNNNNN..", ".NOOOOBBOOOOON..", ".NOBBBNBBBBOON..",
             ".NOBBBNBBBBOON..", "NNOBBBNBBBONNNN.", "NOOOOOOOOOOOOON.", "NOBBBBBBBBBBBON.",
             "NOOOOOOOOOOOOON.", ".NNNNNNNNNNNNN..", ".NO.........NO..", "................"]
        case "facility-calendar":
            ["................", "....N...N...N...", "..NNNNNNNNNNNN..", ".NRRRRRRRRRRRN..",
             ".NWWWWWWWWWWWN..", ".NWCWCWCWCWCWN..", ".NWWWWWWWWWWWN..", ".NWCWRWCWCWCWN..",
             ".NWWWWWWWWWWWN..", ".NWCWCWCWCWCWN..", ".NNNNNNNNNNNNN..", "................"]
        default:
            ["................", ".NNNNNNNNNNNNNN.", ".NBBBNBBBNBBBBN.",
             ".NUBBNUBBNUBBBN.", ".NUBBNUBBNUBBBN.", ".NUBBNUBBNUBBBN.", ".NUWBNUWBNUBWBN.",
             ".NUBBNUBBNUBBBN.", ".NUBBNUBBNUBBBN.", ".NUBBNUBBNUBBBN.", ".NNNNNNNNNNNNNN.", "................"]
        }
    }

    private static let colors: [Character: Color] = [
        "N": Color(hex: 0x122335), "G": Color(hex: 0x5ac194), "O": Color(hex: 0xd78651),
        "B": Color(hex: 0x3568a5), "U": Color(hex: 0x62a0d0), "W": Color(hex: 0xf8ebce),
        "C": Color(hex: 0xa9916d), "R": Color(hex: 0xc35b50)
    ]

    var body: some View {
        Canvas { context, size in
            let unit = max(1, floor(min(size.width / 16, size.height / 12)))
            let origin = CGPoint(x: (size.width - 16 * unit) / 2, y: (size.height - 12 * unit) / 2)
            for (row, pixels) in rows.enumerated() {
                for (column, pixel) in pixels.enumerated() {
                    guard let color = Self.colors[pixel] else { continue }
                    let rect = CGRect(x: origin.x + CGFloat(column) * unit, y: origin.y + CGFloat(row) * unit,
                                      width: unit, height: unit)
                    context.fill(Path(rect), with: .color(color))
                }
            }
        }.accessibilityHidden(true)
    }
}

struct ManagementSpatialHeader: View {
    let player: CareerPlayer
    let affiliation: String
    var uniformTeamID: String? = nil
    var currentAffiliation: String? = nil
    var originSchoolName: String? = nil
    var appearanceOverride: PlayerAppearance? = nil
    let age: Int
    let used: Bool
    let pending: Bool
    var compact = false
    var settings: (() -> Void)? = nil
    let profile: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    private var fatigueColor: Color { ManagementDisplay.fatigueColor(player.fatigue) }
    private var date: some View {
        Text(ManagementDisplay.date(player.gameDate)).font(ManagementPixelFont.readable(compact ? .helper : .label))
            .multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("calendarDate")
    }
    private var team: some View {
        HStack(alignment: .center, spacing: 5) {
            if originSchoolName == nil, let school = SchoolCatalog.bundled.first(where: { $0.id == player.schoolID }) {
                SchoolCrest(school: school).frame(width: 16, height: 18).accessibilityHidden(true)
            }
            Text(currentAffiliation ?? affiliation).font(.caption).fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel(affiliation).accessibilityIdentifier("homeSchool")
        }
    }
    private var ageAndRole: some View {
        Text("\(age)세 · \(player.role.label) · \(player.roleDetail)")
            .font(.caption).foregroundStyle(GameTheme.boardMuted)
            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("homeAge")
    }
    private var identity: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("\(player.name)  #\(player.jerseyNumber)")
                .font(ManagementPixelFont.readable(.sectionTitle))
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("homePlayerName")
            if compact && !typeSize.isAccessibilitySize {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 5) { team; Text("·").accessibilityHidden(true); ageAndRole }
                        .fixedSize(horizontal: true, vertical: false)
                    VStack(alignment: .leading, spacing: 4) { team; ageAndRole }
                }
            } else { team; ageAndRole }
            if let originSchoolName {
                HStack(alignment:.center,spacing:5) {
                    if let school=SchoolCatalog.bundled.first(where:{$0.id == player.schoolID}) {
                        SchoolCrest(school:school).frame(width:18,height:20)
                    }
                    Text("출신 "+originSchoolName).font(.caption).fixedSize(horizontal:false,vertical:true)
                }.foregroundStyle(GameTheme.boardMuted).accessibilityHidden(true)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private var fatigueGauge: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(GameTheme.boardLine.opacity(0.35))
                Rectangle().fill(fatigueColor).frame(width: geometry.size.width * CGFloat(min(100, max(0, player.fatigue))) / 100)
            }
        }.frame(width: typeSize.isAccessibilitySize ? 120 : compact ? 54 : 96, height: 5).accessibilityHidden(true)
    }
    private var fatigue: some View {
        let inline = compact && !typeSize.isAccessibilitySize
        let label = "피로 \(player.fatigue)/100"
        let condition = ManagementDisplay.fatigueLabel(player.fatigue)
        let layout = inline ? AnyLayout(HStackLayout(spacing: 5)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 4))
        return layout {
            Text(inline ? label : label + " · " + condition)
                .font(.caption.bold()).foregroundStyle(fatigueColor).accessibilityIdentifier("homeFatigue")
                .accessibilityLabel(label + " · " + condition)
            fatigueGauge
        }
    }
    private var action: some View {
        HStack(spacing: 6) {
            Rectangle().fill(used ? Color.clear : GameTheme.gold)
                .frame(width: 7, height: 7).overlay(Rectangle().strokeBorder(GameTheme.gold, lineWidth: 1)).accessibilityHidden(true)
            Text(pending ? "훈련 이어하기" : "행동 \(used ? 0 : 1)/1")
                .font(ManagementPixelFont.readable(.helper)).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("calendarAction")
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 10) {
                Button(action: profile) {
                    ManagementPlayerPortrait(appearance: appearanceOverride ?? player.appearance.wearing(teamID: uniformTeamID ?? player.schoolID), role: player.role, number: player.jerseyNumber)
                        .frame(width: compact ? 44 : 50, height: compact ? 48 : 64)
                        .background(GameTheme.boardPanel)
                        .overlay(ManagementStepFrame().strokeBorder(GameTheme.boardLine, lineWidth: 1))
                }.buttonStyle(.plain).accessibilityLabel("선수 선택 · 프로필").accessibilityIdentifier("roomProfile")
                identity
                if compact && !typeSize.isAccessibilitySize, let settings { ManagementSettingsButton(action: settings) }
                if !compact && !typeSize.isAccessibilitySize { date.frame(width: 82) }
            }
            if !compact && typeSize.isAccessibilitySize { date }
            Rectangle().fill(GameTheme.boardLine.opacity(0.7)).frame(height: 1).accessibilityHidden(true)
            if compact {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 8) {
                        date.fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                        fatigue.fixedSize(horizontal: true, vertical: false)
                        Spacer(minLength: 0)
                        action.fixedSize(horizontal: true, vertical: false)
                    }
                    VStack(alignment: .leading, spacing: 4) {
                        date
                        ViewThatFits(in: .horizontal) {
                            HStack(spacing: 10) { fatigue; action }.fixedSize(horizontal: true, vertical: false)
                            VStack(alignment: .leading, spacing: 4) { fatigue; action }
                        }
                    }
                }
            } else {
                let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
                layout {
                    fatigue
                    if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                    action
                }
            }
        }.padding(.horizontal, 12).padding(.vertical, 9)
            .foregroundStyle(ManagementTheme.Spatial.onCanvas)
            .background(ManagementTheme.Spatial.canvas)
            .overlay(alignment: .top) { Rectangle().fill(GameTheme.gold).frame(height: 1).allowsHitTesting(false).accessibilityHidden(true) }
            .overlay(alignment: .bottom) { Rectangle().fill(GameTheme.boardLine).frame(height: 1).allowsHitTesting(false).accessibilityHidden(true) }
            .accessibilityElement(children: .contain).accessibilityIdentifier("managementPlayerHUD")
    }
}

enum ManagementRoomDetail: Equatable, Identifiable {
    case player(ManagementPlayerSection), training(ManagementTrainingSection)
    case game(ManagementGameSection), career(ManagementCareerSection)
    case profile, gameEntry, pitchLibrary, trainingEntry, observationCalendar, observationGrowth
    var id: String {
        switch self {
        case .player: "player"
        case .training: "training"
        case .game: "game"
        case .career: "career"
        case .profile: "profile"
        case .gameEntry: "gameEntry"
        case .pitchLibrary: "pitchLibrary"
        case .trainingEntry: "trainingEntry"
        case .observationCalendar: "observationCalendar"
        case .observationGrowth: "observationGrowth"
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
        case .pitchLibrary: "구종 보관함"
        case .trainingEntry: "훈련 기록"
        case .observationCalendar: "관찰 일정"
        case .observationGrowth: "성장 비교"
        }
    }
}

/// The sheet identity remains stable while its selected section changes.
struct ManagementLiveDetail<Content: View>: View {
    @Binding var detail: ManagementRoomDetail?
    @Binding var trainingKind: TrainingKind
    let fallback: ManagementRoomDetail
    @ViewBuilder let content: (ManagementRoomDetail, TrainingKind) -> Content
    var body: some View { content(detail ?? fallback, trainingKind) }
}

/// A small scene-side entry; opening it never confirms a training or advances a date.
struct ManagementSceneActionStyle: ButtonStyle {
    var secondary = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(ManagementPixelFont.readable(.label))
            .foregroundStyle(secondary ? GameTheme.boardInk : GameTheme.navy)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(minHeight: 44)
            .background(secondary ? GameTheme.boardPanel : Color(hex: 0xf2dfb0), in: ManagementStepFrame())
            .overlay { ManagementStepFrame().stroke(GameTheme.gold, lineWidth: 1) }
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}

/// Stadium navigation is a read-only projection. The existing destinations own all commands.
struct ManagementStadiumRoom<Header: View>: View {
    @Binding var selection: ManagementTab
    let scheduleTitle: String
    let date: String
    let teams: [String]
    let fixtureNumber: Int?
    let schools: [School]
    let entryTitle: String
    let entryStatus: String
    var stadium: StadiumIdentity? = nil
    let choose: (String) -> Void
    @ViewBuilder let header: Header
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        GeometryReader { geometry in
            VStack(spacing: 0) {
                if typeSize.isAccessibilitySize {
                    ScrollView {
                        VStack(spacing: 16) {
                            header
                            toolbar
                            venueHeader
                            scoreboard.padding(.horizontal, 16)
                            ForEach([("facility-analysis", "더그아웃 · 상대 분석"), ("facility-gameRecords", "기록석 · 경기 기록")], id: \.0) { id, title in
                                Button { choose(id) } label: {
                                    HStack { Text(title); Spacer(); Text("›") }.frame(maxWidth: .infinity, minHeight: 44)
                                }.buttonStyle(ManagementButtonStyle(variant: .secondary)).accessibilityIdentifier(id)
                            }.padding(.horizontal, 16)
                        }.padding(.bottom, 16)
                    }.accessibilityIdentifier("stadiumFacilityList")
                    entryButton
                        .font(ManagementPixelFont.readable(.label))
                        .buttonStyle(ManagementPropButtonStyle())
                        .foregroundStyle(GameTheme.boardInk)
                        .padding(.horizontal, 16).padding(.vertical, 6)
                } else {
                    header
                    GeometryReader { stage in
                        ScrollView(.vertical) {
                            stadium(width: stage.size.width)
                        }.accessibilityIdentifier("stadiumSceneScroll")
                            .overlay(alignment: .top) { toolbar }
                    }
                }
                ManagementTabBar(selection: $selection)
            }.frame(width: geometry.size.width, height: geometry.size.height)
        }.background(GameTheme.boardPanel.ignoresSafeArea())
            .toolbar(.hidden, for: .navigationBar).preferredColorScheme(.dark)
    }
    private var toolbar: some View {
        HStack {
            Spacer()
            ManagementSettingsButton { choose("clubhouse-settings") }
        }.buttonStyle(.plain).foregroundStyle(GameTheme.boardInk)
    }
    private var scoreboard: some View {
        VStack(spacing: typeSize.isAccessibilitySize ? 4 : 0) {
            let headingLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
            headingLayout {
                ledText(fixtureNumber.map { scheduleTitle + " · " + String($0) + "차전" } ?? scheduleTitle, color: GameTheme.gold)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 4) }
                ledText(date, color: GameTheme.gold).accessibilityIdentifier("stadiumScheduleDate")
            }.frame(maxWidth: .infinity, alignment: .leading)
                .font(typeSize.isAccessibilitySize ? ManagementPixelFont.readable(.helper) : ManagementPixelFont.font(11))
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Color(hex: 0x304e63))
            let teamsLayout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))
            teamsLayout {
                if teams.count == 2 {
                    teamCell(teams[0], designation: "원정")
                    ledText("VS", color: GameTheme.gold).font(typeSize.isAccessibilitySize ? ManagementPixelFont.readable(.helper) : ManagementPixelFont.font(10))
                    teamCell(teams[1], designation: "홈")
                } else { ledText(teams.first ?? "일정 확인").frame(maxWidth: .infinity) }
            }.font(typeSize.isAccessibilitySize ? ManagementPixelFont.readable(.label) : ManagementPixelFont.font(12))
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .combine).accessibilityIdentifier("stadiumMatchup")
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background {
                    Color(hex: 0x203b52)
                    StadiumLEDDots(pitch: 3, diameter: 0.7).fill(Color(hex: 0x8fa8af).opacity(0.12))
                        .accessibilityHidden(true).allowsHitTesting(false)
                }
            Rectangle().fill(Color(hex: 0x6f8b95)).frame(height: 1).accessibilityHidden(true)
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 8))
            layout {
                Button { choose("facility-calendar") } label: { ledText("일정 ›").frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle()) }
                    .accessibilityIdentifier("facility-calendar")
                Button { choose("facility-standings") } label: { ledText("순위 ›").frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle()) }
                    .accessibilityIdentifier("facility-standings").accessibilityLabel("리그 순위")
                if !typeSize.isAccessibilitySize { entryButton }
            }.font(typeSize.isAccessibilitySize ? ManagementPixelFont.readable(.label) : ManagementPixelFont.font(11))
                .buttonStyle(ManagementPropButtonStyle())
                .padding(.horizontal, 10)
                .background(Color(hex: 0x304e63))
        }.foregroundStyle(GameTheme.boardInk)
            .padding(6)
            .background(Color(hex: 0x526f80))
            .overlay {
                ZStack {
                    Rectangle().strokeBorder(Color(hex: 0x152d42), lineWidth: 2)
                    VStack(spacing: 0) {
                        Rectangle().fill(Color(hex: 0xb9b699)).frame(height: 2)
                        Spacer(minLength: 0)
                        Rectangle().fill(Color(hex: 0x263e53)).frame(height: 3)
                    }.padding(2)
                    Rectangle().inset(by: 6).strokeBorder(Color(hex: 0x162e42), lineWidth: 1)
                }.accessibilityHidden(true).allowsHitTesting(false)
            }
    }
    private var entryButton: some View {
        Button { choose("roomPrimary") } label: {
            ledText(entryTitle + " ›", color: GameTheme.gold)
                .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
        }.accessibilityIdentifier("roomPrimary").accessibilityHint(entryStatus)
    }
    private func teamCell(_ name: String, designation: String) -> some View {
        VStack(spacing: 3) {
            Text(designation).font(typeSize.isAccessibilitySize ? ManagementPixelFont.readable(.helper) : ManagementPixelFont.font(9))
                .foregroundStyle(Color(hex: 0xc8d8db))
            HStack(spacing: 4) {
                if !typeSize.isAccessibilitySize {
                    if let school = schools.first(where: { $0.name == name }) {
                        SchoolCrest(school: school).frame(width: 18, height: 18).accessibilityHidden(true)
                    } else if let club = ClubIdentity.resolve(name: name) {
                        Image(club.asset).resizable().interpolation(.none).scaledToFit().frame(width: 18, height: 18).accessibilityHidden(true)
                    }
                }
                ledText(name)
            }
        }.frame(maxWidth: .infinity).padding(.vertical, 4).padding(.horizontal, 3)
    }
    private func ledText(_ value: String, color: Color = GameTheme.boardInk) -> some View {
        Text(value).modifier(StadiumLEDLettering(color: color, textured: !typeSize.isAccessibilitySize))
    }
    private func stadium(width: CGFloat) -> some View {
        VStack(spacing: 16) {
            venueHeader
            scoreboard.padding(.horizontal, 16)
            VStack(spacing: 10) {
                ForEach([("facility-analysis", "더그아웃 · 상대 분석"), ("facility-gameRecords", "기록석 · 경기 기록")], id: \.0) { id, title in
                    Button { choose(id) } label: {
                        HStack { Text(title); Spacer(); Text("›") }.frame(maxWidth: .infinity, minHeight: 44)
                    }.buttonStyle(ManagementButtonStyle(variant: .secondary)).accessibilityIdentifier(id)
                }
            }.padding(.horizontal, 16)
        }.padding(.bottom, 20).frame(width: width)
    }
    @ViewBuilder private var venueHeader: some View {
        if let stadium { ManagementVenueBanner(stadium: stadium, compact: false) }
    }
    private func structure(_ id: String, _ title: String, x: CGFloat, y: CGFloat, width: CGFloat, size: CGFloat, scene: CGSize) -> some View {
        Button { choose(id) } label: {
            Text(title).font(ManagementPixelFont.font(size)).multilineTextAlignment(.center)
                .frame(width: width, height: 44).contentShape(Rectangle())
        }.buttonStyle(ManagementPropButtonStyle()).foregroundStyle(GameTheme.boardInk)
            .accessibilityLabel(id == "facility-standings" ? "리그 순위" : title.replacingOccurrences(of: " ›", with: ""))
            .accessibilityHint("상세 열기").accessibilityIdentifier(id)
            .position(x: scene.width * x, y: scene.height * y)
    }
}

/// Current-team identity for menus; actual games keep their saved home-team venue.
struct ManagementVenueBanner: View {
    let stadium: StadiumIdentity
    var compact = true
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if let venue = stadium.backdrop, let art = InplayStadiumArt.upperArt(venue, stadium: stadium) {
            VStack(alignment: .leading, spacing: 0) {
                Image(uiImage: art.image).resizable().interpolation(.none).scaledToFill()
                    .frame(maxWidth: .infinity).frame(height: compact ? 54 : 152).clipped().accessibilityHidden(true)
                HStack(spacing: 8) {
                    if let logo = venue.logoAsset {
                        Image(logo).resizable().interpolation(.none).scaledToFit().frame(width: 22, height: 22).accessibilityHidden(true)
                    }
                    Text(venue.name + " · 홈 구장").font(compact ? .caption.bold() : .headline)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }.padding(.horizontal, 12).padding(.vertical, compact ? 6 : 12)
                    .foregroundStyle(GameTheme.boardInk).background(GameTheme.boardPanel)
            }.accessibilityElement(children: .combine)
                .accessibilityIdentifier("managementVenue-" + stadium.key)
        }
    }
}

/// Static LED cells; no timer, animation, or game-state work is attached to the panel.
private struct StadiumLEDDots: Shape {
    let pitch: CGFloat
    let diameter: CGFloat
    func path(in rect: CGRect) -> Path {
        var path = Path()
        for y in stride(from: rect.minY + pitch / 2, to: rect.maxY, by: pitch) {
            for x in stride(from: rect.minX + pitch / 2, to: rect.maxX, by: pitch) {
                path.addEllipse(in: CGRect(x: x - diameter / 2, y: y - diameter / 2, width: diameter, height: diameter))
            }
        }
        return path
    }
}

private struct StadiumLEDLettering: ViewModifier {
    let color: Color
    let textured: Bool
    @Environment(\.colorSchemeContrast) private var contrast
    func body(content: Content) -> some View {
        if textured && contrast != .increased {
            content.foregroundStyle(color)
                .mask { StadiumLEDDots(pitch: 1, diameter: 0.9).fill(.white) }
                .background {
                    content.foregroundStyle(color.opacity(0.75))
                        .accessibilityHidden(true).allowsHitTesting(false)
                }
                .shadow(color: color.opacity(0.6), radius: 1)
        } else {
            content.foregroundStyle(color)
        }
    }
}

/// The home room looks out onto the affiliated team's distant stands, not a second scene above the room.
@MainActor enum ManagementHomeVenueArt {
    final class Artwork {
        let image: UIImage
        let venueName: String

        init(image: UIImage, venueName: String) {
            self.image = image
            self.venueName = venueName
        }
    }
    static let roomAsset = "ClubhouseRoomV59"
    static let referenceSize = CGSize(width: 948, height: 1659)
    // Inside the vertical part of the arch, above the existing field and all foreground rails.
    static let standsBounds = CGRect(x: 327, y: 374, width: 294, height: 140)
    private static let skyBlend = CGGradient(colorSpace: CGColorSpaceCreateDeviceGray(),
                                              colorComponents: [0, 0, 0, 1], locations: [0, 1], count: 2)
    private static let cache: NSCache<NSString, Artwork> = {
        let cache = NSCache<NSString, Artwork>()
        cache.totalCostLimit = 24 * 1024 * 1024; cache.countLimit = 3
        return cache
    }()

    static func backdrop(for stadium: StadiumIdentity) -> StadiumBackdrop? {
        venueIdentity(for: stadium)?.backdrop
    }

    private static func venueIdentity(for stadium: StadiumIdentity) -> StadiumIdentity? {
        if stadium.backdrop != nil { return stadium }
        // Development teams share the parent club artwork in the clubhouse.
        let parentID: String
        if CareerTeamDirectory.expandedDomesticIDs.contains(stadium.key) {
            parentID = "pro-" + stadium.key.dropFirst("dev-".count)
        } else if CareerTeamDirectory.americanDevelopmentIDs.contains(stadium.key) {
            parentID = "us-pro-" + stadium.key.dropFirst("us-dev-".count)
        } else {
            return nil
        }
        return StadiumIdentity(homeTeamID: parentID)
    }

    static func art(asset: String, selection: ManagementTab, stadium: StadiumIdentity) -> Artwork? {
        guard selection == .home, asset == roomAsset, let renderedStadium = venueIdentity(for: stadium),
              let venue = renderedStadium.backdrop else { return nil }
        let key = "v168-home-2:\(stadium.key):\(venue.imageName)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        guard let original = UIImage(named: roomAsset), original.size == referenceSize,
              let upper = InplayStadiumArt.upperArt(venue, stadium: renderedStadium)?.image else { return nil }
        let scale = max(standsBounds.width / upper.size.width, standsBounds.height / upper.size.height)
        let size = CGSize(width: upper.size.width * scale, height: upper.size.height * scale)
        let target = CGRect(x: standsBounds.midX - size.width / 2, y: standsBounds.maxY - size.height,
                            width: size.width, height: size.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1; format.opaque = true; format.preferredRange = .standard
        let image = UIGraphicsImageRenderer(size: referenceSize, format: format).image { renderer in
            let context = renderer.cgContext; context.interpolationQuality = .none
            original.draw(in: CGRect(origin: .zero, size: referenceSize))
            context.saveGState(); context.clip(to: standsBounds)
            drawStands(upper, in: target, context: context)
            drawIdentity(venue, in: target, context: context)
            context.restoreGState()
        }
        let art = Artwork(image: image, venueName: venue.name)
        cache.setObject(art, forKey: key, cost: Int(referenceSize.width * referenceSize.height) * 4)
        return art
    }

    private static func drawStands(_ upper: UIImage, in target: CGRect, context: CGContext) {
        guard let skyBlend else { upper.draw(in: target); return }
        // Finish the sky transition before the original board starts at y391.
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        upper.draw(in: target)
        context.saveGState(); context.setBlendMode(.destinationIn)
        context.drawLinearGradient(skyBlend,
                                   start: CGPoint(x: standsBounds.midX, y: standsBounds.minY),
                                   end: CGPoint(x: standsBounds.midX, y: 390),
                                   options: [.drawsAfterEndLocation])
        context.restoreGState()
        context.endTransparencyLayer()
    }

    private static func drawIdentity(_ venue: StadiumBackdrop, in target: CGRect, context: CGContext) {
        // Backdrop board coordinates use the shared 1024px scene, including the 768px pro source.
        let board = CGRect(x: target.minX + venue.board.minX * target.width / 1024,
                           y: target.minY + venue.board.minY * target.height / venue.height,
                           width: venue.board.width * target.width / 1024,
                           height: venue.board.height * target.height / venue.height).integral
        context.setFillColor(UIColor(Color(hex: venue.panel)).cgColor); context.fill(board)
        context.setStrokeColor(UIColor(Color(hex: venue.trim)).cgColor)
        context.setLineWidth(1); context.stroke(board.insetBy(dx: 0.5, dy: 0.5))
        var textRect = board.insetBy(dx: 3, dy: 2)
        if let logoName = venue.logoAsset, let logo = UIImage(named: logoName) {
            let side = max(1, min(textRect.height, textRect.width * 0.25))
            logo.draw(in: CGRect(x: textRect.minX, y: textRect.midY - side / 2, width: side, height: side))
            textRect.origin.x += side + 2; textRect.size.width -= side + 2
        }
        let style = NSMutableParagraphStyle(); style.alignment = .center; style.lineBreakMode = .byClipping
        let size = min(textRect.height * 0.65, textRect.width / CGFloat(max(1, venue.name.count)))
        let font = UIFont.systemFont(ofSize: max(1, size), weight: .heavy)
        let label = NSString(string: venue.name)
        let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor(white: 0.96, alpha: 1), .paragraphStyle: style]
        let labelSize = label.size(withAttributes: attributes)
        label.draw(in: CGRect(x: textRect.minX, y: textRect.midY - labelSize.height / 2,
                              width: textRect.width, height: labelSize.height), withAttributes: attributes)
    }
}
