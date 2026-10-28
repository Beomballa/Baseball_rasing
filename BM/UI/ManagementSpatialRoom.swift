import SwiftUI

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

    var body: some View {
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
    private var roomToolbar: some View {
        HStack {
            if selection != .home {
                Button(action: home) { Text("‹ 클럽하우스").font(.subheadline.bold()).padding(.horizontal, 12).frame(minHeight: 44) }
                    .buttonStyle(.plain).accessibilityIdentifier("roomBackHome")
            }
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
