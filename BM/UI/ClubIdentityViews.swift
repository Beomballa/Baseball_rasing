import SwiftUI

struct ClubBadge: View {
    let name: String
    var size: CGFloat = 68
    var body: some View {
        Group {
            if let club = ClubIdentity.resolve(name: name) {
                Image(club.asset).interpolation(.none).resizable().scaledToFit()
            } else {
                Image(systemName: "sportscourt").resizable().scaledToFit().padding(14).foregroundStyle(GameTheme.boardMuted)
            }
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct ClubFileHeader: View {
    let name: String
    let subtitle: String
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
        layout {
            ClubBadge(name: name)
            VStack(alignment: .leading, spacing: 6) {
                if let club = ClubIdentity.resolve(name: name) {
                    Text(club.league.label + " · 가상 구단").font(.caption.bold()).foregroundStyle(GameTheme.boardMuted)
                }
                Text(name).font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                Text(subtitle).font(.subheadline).foregroundStyle(GameTheme.gold).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct ClubAbilityComparison: View {
    let mine: Double?
    let criterion: Double?
    var mineLabel = "내 역할 기량"
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            bar(mineLabel, value: mine, color: GameTheme.growth)
            bar("구단 관찰 기준", value: criterion, color: GameTheme.gold)
        }.accessibilityElement(children: .combine)
    }
    private func bar(_ label: String, value: Double?, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(label).font(.subheadline)
                Spacer(minLength: 0)
                Text(value.map { String(format: "%.1f", $0) } ?? "자료 없음").font(.headline.monospacedDigit()).foregroundStyle(color)
            }
            if let value, value.isFinite {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Rectangle().fill(GameTheme.boardLine.opacity(0.25))
                        Rectangle().fill(color).frame(width: g.size.width * min(1, max(0, value / 100)))
                    }
                }.frame(height: 8).accessibilityHidden(true)
            }
        }
    }
}

struct ClubDirectoryView: View {
    @State private var league = ClubIdentity.League.kbo
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("구단을 알아보세요").font(.title2.bold())
                Text("가상 구단 30개 · 계약 참가 18개").font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("clubDirectorySummary")
                leagueTabs
                Text("참가 구단의 관심·모집 기준은 내 고정 보고서에서 확인합니다. 미참여 구단은 도감만 제공하며 목표 지정·계약·경기가 열리지 않습니다.").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .top), count: typeSize.isAccessibilitySize ? 1 : 2), spacing: 12) {
                    ForEach(ClubIdentity.all.filter { $0.league == league }) { club in
                        VStack(spacing: 10) {
                            ClubBadge(name: club.name, size: 100)
                            Text(club.name).font(.headline).multilineTextAlignment(.center)
                            Text(club.motif).font(.subheadline).foregroundStyle(GameTheme.boardMuted).multilineTextAlignment(.center)
                            Text(club.participates ? "참가 · 관찰 대상" : "미참여 · 도감 전용")
                                .font(.subheadline.bold()).foregroundStyle(club.participates ? GameTheme.growth : GameTheme.gold)
                        }.padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                            .background(GameTheme.boardPanel).overlay(ManagementStepFrame().stroke(GameTheme.boardLine, lineWidth: 1))
                            .accessibilityElement(children: .combine).accessibilityIdentifier("clubDirectory-" + club.id)
                    }
                }
            }.padding(16)
        }.background(GameTheme.board).foregroundStyle(GameTheme.boardInk).navigationTitle("가상 구단 도감").navigationBarTitleDisplayMode(.inline)
    }
    private var leagueTabs: some View {
        HStack(spacing: 8) {
            ForEach(ClubIdentity.League.allCases) { value in
                Button { league = value } label: { Text((league == value ? "◆ " : "") + value.label).font(.subheadline.bold()).frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(MatchPixelButtonStyle(primary: league == value)).accessibilityIdentifier("clubLeague-" + value.id)
                    .accessibilityAddTraits(league == value ? .isSelected : [])
            }
        }
    }
}

/// Selects only rows already present in the frozen report, never directory-only teams.
struct CareerTargetClubPicker: View {
    let clubs: [CareerTargetClub]
    let reportDate: String
    @Binding var selectedID: String
    @State private var path = "국내 프로 관찰"
    @Environment(\.dynamicTypeSize) private var typeSize
    private var choices: [CareerTargetClub] { clubs.filter { $0.path == path } }
    private var names: [String] { choices.reduce(into: [String]()) { if !$0.contains($1.name) { $0.append($1.name) } } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("목표 구단 변경").font(.title3.bold())
            Text(ManagementDisplay.date(reportDate) + " 고정 보고서의 모집 역할").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
            LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 140))], spacing: 8) {
                ForEach(["국내 프로 관찰"] + OverseasRoute.allCases.map(\.label), id: \.self) { value in
                    Button { if path != value { selectedID = "" }; path = value } label: { Text((path == value ? "◆ " : "") + value).font(.subheadline.bold()).fixedSize(horizontal: false, vertical: true).padding(10).frame(maxWidth: .infinity, minHeight: 44) }
                        .buttonStyle(MatchPixelButtonStyle(primary: path == value)).accessibilityIdentifier("targetRoute-" + value)
                        .accessibilityAddTraits(path == value ? .isSelected : [])
                }
            }
            if choices.isEmpty { Text("이 보고서에는 해당 경로의 모집 자료가 없습니다.").font(.subheadline) }
            ForEach(names, id: \.self) { name in
                VStack(alignment: .leading, spacing: 12) {
                    ClubFileHeader(name: name, subtitle: "모집 역할 선택")
                    ForEach(choices.filter { $0.name == name }) { club in
                        Button { selectedID = club.id } label: {
                            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(spacing: 10))
                            layout {
                                HStack(alignment: .top, spacing: 10) {
                                    Text(selectedID == club.id ? "◆" : "◇").accessibilityHidden(true)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(DomesticContractOffer.roleName(club.roleID)).bold()
                                        Text(club.demand).foregroundStyle(GameTheme.boardMuted)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Text(club.criterion.map { String(format: "기준 %.1f", $0) } ?? "기준 대기").monospacedDigit()
                            }.font(.subheadline).fixedSize(horizontal: false, vertical: true).padding(12).frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(MatchPixelButtonStyle(primary: selectedID == club.id))
                            .accessibilityIdentifier("targetChoice-" + club.id).accessibilityAddTraits(selectedID == club.id ? .isSelected : [])
                    }
                }.padding(12).background(GameTheme.boardPanel)
            }
            Text("선택만으로 저장되지 않습니다. 아래에서 목표를 확정하세요. 관심·지원·계약을 예약하는 기능은 아닙니다.").font(.subheadline).foregroundStyle(GameTheme.boardMuted)
        }.onAppear {
            if let selected = clubs.first(where: { $0.id == selectedID }) { path = selected.path }
        }
    }
}
