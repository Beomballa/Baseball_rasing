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
    var season: AnnualLeague? = nil
    var seasonError: String? = nil
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
                    ClubRecruitmentSummary(clubs: choices.filter { $0.name == name })
                    Text(seasonError ?? ClubSeasonDisplay.summary(name: name, league: season))
                        .font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                        .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("clubSeason-" + name)
                    ForEach(choices.filter { $0.name == name }) { club in
                        Button { selectedID = club.id } label: {
                            ClubRoleChoice(club: club, selected: selectedID == club.id)
                        }.buttonStyle(ClubRoleButtonStyle(selected: selectedID == club.id))
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

/// Reads the current career season only. Other leagues are not fabricated or simulated here.
enum ClubSeasonDisplay {
    static func summary(name: String, league: AnnualLeague?) -> String {
        guard let identity = ClubIdentity.resolve(name: name), let league,
              let row = league.displayStandings.first(where: { ClubIdentity.resolve(name: CareerTeamDirectory.name($0.id))?.id == identity.id }) else {
            return "리그 순위 · 우승팀 미집계 — 이 커리어에 해당 리그 기록 없음"
        }
        let rank = row.rank.map { "\($0)위" } ?? "순위 대기"
        let leader = league.isComplete ? "우승" : "현재 선두"
        let names = league.displayStandings.filter { $0.rank == 1 }.map { CareerTeamDirectory.name($0.id) }
        return "\(league.year)년 · \(CareerTeamDirectory.name(row.id)) · \(rank) · \(row.wins)승 \(row.losses)패 \(row.draws)무\n" +
            (names.isEmpty ? "우승팀 미정 · 경기 기록 대기" : leader + " · " + names.joined(separator: " / ")) +
            (league.isComplete ? " · 시즌 확정" : " · 진행 중, 우승 미확정")
    }
}

struct ClubRecruitmentSummary: View {
    let clubs: [CareerTargetClub]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "person.crop.rectangle.badge.plus").accessibilityHidden(true)
                Text("모집 기회 · " + opportunities).font(.subheadline.bold())
            }.foregroundStyle(GameTheme.growth)
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "scope").accessibilityHidden(true)
                Text("준비할 점 · " + (clubs.flatMap(\.blockers).first ?? "역할 기준·공식 경기 표본 확인"))
                    .font(.subheadline)
            }.foregroundStyle(GameTheme.gold)
        }.fixedSize(horizontal: false, vertical: true).padding(12)
            .frame(maxWidth: .infinity, alignment: .leading).background(GameTheme.board)
    }
    private var opportunities: String {
        let vacancies = clubs.filter { $0.demand == RecruitmentDemand.vacancy.label }.map { DomesticContractOffer.roleName($0.roleID) }
        if !vacancies.isEmpty { return vacancies.joined(separator: "·") + " 공석" }
        let depth = clubs.filter { $0.demand == RecruitmentDemand.depth.label }.map { DomesticContractOffer.roleName($0.roleID) }
        return depth.isEmpty ? "현재 모집 없음" : depth.joined(separator: "·") + " 뎁스 보강"
    }
}

private struct ClubRoleChoice: View {
    let club: CareerTargetClub
    let selected: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                Rectangle().strokeBorder(selected ? GameTheme.gold : GameTheme.boardMuted, lineWidth: 2)
                if selected { Image(systemName: "checkmark").font(.system(size: 12, weight: .heavy)) }
            }.frame(width: 20, height: 20).accessibilityHidden(true)
            let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout(alignment: .center, spacing: 12))
            layout {
                VStack(alignment: .leading, spacing: 6) {
                    Text(DomesticContractOffer.roleName(club.roleID)).font(.headline)
                    Text(club.demand).font(.subheadline).foregroundStyle(GameTheme.boardMuted)
                }.frame(maxWidth: .infinity, alignment: .leading)
                VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: 4) {
                    Text("관찰 기준").font(.caption).foregroundStyle(GameTheme.boardMuted)
                    Text(club.criterion.map { String(format: "%.1f", $0) } ?? "대기")
                        .font(.headline.monospacedDigit())
                }.fixedSize(horizontal: true, vertical: false)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ClubRoleButtonStyle: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.padding(.horizontal, 16).padding(.vertical, 14)
            .frame(maxWidth: .infinity, minHeight: 76, alignment: .leading)
            .foregroundStyle(GameTheme.boardInk)
            .background(selected ? GameTheme.navy : GameTheme.board)
            .overlay(Rectangle().strokeBorder(selected ? GameTheme.gold : GameTheme.boardLine, lineWidth: selected ? 2 : 1))
            .contentShape(Rectangle()).opacity(configuration.isPressed ? 0.7 : 1)
    }
}
