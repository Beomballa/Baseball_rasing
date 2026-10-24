import SwiftUI
import SwiftData

#if DEBUG
// Value-only screen samples: no model context, career store, clock or evaluation engine.
struct ScoutingContractPreview: View {
    enum Scenario: String, CaseIterable, Identifiable {
        case school = "고교 관찰", offers = "제의 도착", none = "제의 없음"
        var id: String { rawValue }
    }
    enum Route: Hashable { case report, offers, detail(Int), compare, career }
    @State private var scenario = Scenario.school
    @State private var pitcher = false
    @State private var showControls = false
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var decision: String?
    @State private var receipt: String?
    @State private var careerChoice: String?
    @Environment(\.dynamicTypeSize) private var typeSize
    @ScaledMetric(relativeTo: .subheadline) private var scaledTextGap: CGFloat = 8
    @ScaledMetric(relativeTo: .body) private var scaledSectionGap: CGFloat = 16
    private var textGap: CGFloat { min(scaledTextGap, 16) }
    private var sectionGap: CGFloat { min(scaledSectionGap, 24) }
    private let clubs = ["인천 하버스", "대전 코멧츠"]
    private var large: Bool { typeSize.isAccessibilitySize }
    private var role: String { pitcher ? "선발 투수" : "유격수 · 우타" }
    private var isSchool: Bool { scenario == .school }
    private var date: String { isSchool ? "2026.04.01" : scenario == .none ? "2030.04.08" : "2030.04.01" }
    private var nextReport: String { isSchool ? "04.29" : scenario == .none ? "05.06" : "04.29" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: sectionGap) {
                notice
                Button(showControls ? "시안 설정 접기 −" : "시안 설정 · \(scenario.rawValue) / \(pitcher ? "투수" : "타자") +") { showControls.toggle() }
                    .buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("scoutPreviewControls")
                if showControls {
                (large ? AnyLayout(VStackLayout(spacing: 6)) : AnyLayout(HStackLayout(spacing: 6))) {
                    ForEach(Scenario.allCases) { sample in
                        Button(sample.rawValue) { scenario = sample; receipt = nil; careerChoice = nil }
                            .buttonStyle(MatchPixelButtonStyle(primary: sample == scenario))
                            .accessibilityIdentifier("scoutScenario-" + sample.id)
                            .accessibilityAddTraits(sample == scenario ? .isSelected : [])
                    }
                }
                HStack(spacing: 6) {
                    Button("타자") { pitcher = false }.buttonStyle(MatchPixelButtonStyle(primary: !pitcher))
                        .accessibilityIdentifier("scoutRole-batter").accessibilityAddTraits(!pitcher ? .isSelected : [])
                    Button("투수") { pitcher = true }.buttonStyle(MatchPixelButtonStyle(primary: pitcher))
                        .accessibilityIdentifier("scoutRole-pitcher").accessibilityAddTraits(pitcher ? .isSelected : [])
                }
                }
                office
                profile
                interest
                if scenario == .offers {
                    NavigationLink { destination(.offers) } label: { Text("도착한 제의 2건 확인") }.buttonStyle(MatchPixelButtonStyle(primary: true)).accessibilityIdentifier("scoutOpenOffers")
                } else if isSchool {
                    Text("성장 관찰 단계 · 20세 이전에는 계약 대신 보고서를 확인하세요.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                } else {
                    GamePanel(title: "이번 평가 · 정식 제의 없음", onBoard: true, contentSpacing: sectionGap) {
                        Text(isSchool ? "16세 · 프로 계약은 20세부터 검토" : "기량 조건 충족 · 전력 심사 표본 부족").font(.subheadline.bold())
                        Text(isSchool ? "관심 보고서를 보고 다음 훈련 목표를 정하세요." : "미달 이유와 다음 진로를 확인할 수 있습니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                        NavigationLink { destination(isSchool ? .report : .career) } label: { Text(isSchool ? "관찰 보고서 보기" : "제의 없음 · 진로 확인") }
                            .buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("scoutOpenCareer")
                    }
                }
            }.padding(12)
        }
        .lineSpacing(large ? 5 : 3)
        .background(GameTheme.board).foregroundStyle(GameTheme.boardInk)
        .navigationTitle("선수 홈 · 스카우트 시안").navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(GameTheme.board, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar).tint(GameTheme.gold)
        .sheet(item: Binding(get: { decision.map(Decision.init) }, set: { decision = $0?.title })) { item in
            ScrollView { VStack(alignment: .leading, spacing: 16) {
                Text("계약 선택 · 화면 확인").font(.headline).foregroundStyle(GameTheme.gold)
                Text(item.title).font(.title3.bold())
                Text("실제 계약·소속·날짜·피로에는 반영되지 않습니다.")
                Button("시안에서 선택 확인") { receipt = item.title + " · 시안 확인 완료"; decision = nil }
                    .buttonStyle(MatchPixelButtonStyle(primary: true)).accessibilityIdentifier("scoutConfirmDecision")
                Button("돌아가기") { decision = nil }.buttonStyle(MatchPixelButtonStyle())
            }.padding(20) }.presentationDetents([.large]).presentationDragIndicator(.visible)
                .background(GameTheme.board).foregroundStyle(GameTheme.boardInk)
        }
    }
    private var office: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image = ScoutOfficeArt.image {
                Image(uiImage: image).resizable().interpolation(.none).aspectRatio(contentMode: .fit)
                    .accessibilityHidden(true)
            }
            HStack {
                VStack(alignment: .leading, spacing: textGap) {
                    Text("SCOUTING ROOM").font(.caption.monospaced().bold()).foregroundStyle(GameTheme.gold)
                    Text(scenario == .offers ? "당신에게 도착한 새로운 기회" : "한 경기 너머의 가능성을 봅니다").font(.subheadline.bold())
                }
                Spacer(minLength: 4)
                Image(systemName: scenario == .offers ? "envelope.badge.fill" : "binoculars.fill").foregroundStyle(GameTheme.gold)
            }.padding(14).background(GameTheme.boardPanel)
        }.overlay(Rectangle().strokeBorder(GameTheme.boardLine, lineWidth: 2))
            .accessibilityElement(children: .ignore).accessibilityLabel("스카우트 관찰실 · 구장과 관찰 노트")
            .accessibilityIdentifier("scoutOfficeScene")
    }
    private func clubIdentity(_ index: Int, paper: Bool = false) -> some View {
        HStack(spacing: 10) {
            Image(systemName: index == 0 ? "sailboat.fill" : "sparkles")
                .font(.title2).frame(width: 42, height: 42).foregroundStyle(.white)
                .background(index == 0 ? ScoutDossierInk.green : Color(red:0.52,green:0.23,blue:0.17))
                .overlay(Rectangle().strokeBorder(paper ? ScoutDossierInk.ink : GameTheme.boardLine))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: textGap) {
                Text(index == 0 ? "HARBORS  /  PLAYER DEVELOPMENT" : "COMETS  /  FIRST TEAM").font(.caption2.monospaced().bold())
                Text(index == 0 ? "함께 성장할 선수를 찾습니다" : "다음 시즌의 경쟁에 초대합니다").font(.caption)
            }.foregroundStyle(paper ? ScoutDossierInk.ink : GameTheme.boardInk)
        }
    }
    private func paperRow(_ key: String, _ value: String) -> some View {
        (large ? AnyLayout(VStackLayout(alignment:.leading,spacing:textGap)) : AnyLayout(HStackLayout(alignment:.top,spacing:10))) {
            Text(key).font(.caption).foregroundStyle(ScoutDossierInk.muted).frame(minWidth: large ? 0 : 82, alignment: .leading)
            if !large { Spacer(minLength: 0) }
            Text(value).font(.subheadline.monospaced()).foregroundStyle(ScoutDossierInk.ink).multilineTextAlignment(large ? .leading : .trailing)
        }.fixedSize(horizontal:false,vertical:true).padding(.vertical,4).accessibilityElement(children:.combine)
    }
    private struct Decision: Identifiable { let title: String; var id: String { title } }
    private var notice: some View {
        Text("화면 시안 · 모든 선수/구단/수치는 샘플 · 저장 안 함")
            .font(.caption.bold()).foregroundStyle(GameTheme.gold).fixedSize(horizontal: false, vertical: true)
            .accessibilityIdentifier("scoutPreviewNotice")
    }
    private var profile: some View {
        HStack(spacing: 12) {
            PixelPlayer(appearance: PlayerAppearance()).frame(width: 38, height: 54).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: textGap) {
                Text("박루키  #17").font(.title3.monospaced().bold())
                Text("\(isSchool ? "16세 · 한빛고(가상)" : "20세 · 무소속") / \(role)").font(.subheadline)
                Text(date + " · 샘플 날짜").font(.caption.monospaced()).foregroundStyle(GameTheme.boardMuted)
            }
        }.padding(16).frame(maxWidth: .infinity, alignment: .leading).background(GameTheme.boardPanel)
            .overlay(Rectangle().strokeBorder(GameTheme.boardLine))
    }
    private var interest: some View {
        GamePanel(title: "관찰 파일 · 관심 구단", onBoard: true, contentSpacing: sectionGap) {
            HStack(alignment: .top, spacing: 16) {
                ScoutPixelEmblem().frame(width: 40, height: 44).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: textGap) {
                    Text("\(scenario == .none ? "1" : "2")개 구단 · \(scenario == .offers ? "제의 검토" : "관찰 중")").font(.headline).foregroundStyle(GameTheme.gold)
                    Text(clubs[0] + " · " + (pitcher ? "선발 육성" : "내야 수비 / 출루")).font(.subheadline)
                    Text(isSchool ? "아직 완성형은 아니지만 성장 가능성을 지켜보고 있습니다." : "최근 경기와 성장 추이를 함께 검토하고 있습니다.").font(.caption).foregroundStyle(GameTheme.boardMuted).padding(.top,4)
                }
            }
            row("다음 관찰 보고서", nextReport + " · 28일 주기")
            row("계약 평가 창", isSchool ? "20세 이후 자격 검토" : scenario == .offers ? "4월 창 · 04.01~04.14" : "4·7·11월 / 다음 07.01")
            Text("우선 보완 · " + (pitcher ? "제구 / 이닝 표본 / 지구력" : "선구안 / 타석 표본 / 수비"))
                .font(.caption).foregroundStyle(GameTheme.boardMuted)
            NavigationLink { destination(.report) } label: { Text("스카우트 보고서") }.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("scoutOpenReport")
        }
    }
    private func destination(_ route: Route) -> AnyView {
        AnyView(ScrollView {
            VStack(alignment: .leading, spacing: sectionGap) {
                notice
                switch route {
                case .report: report
                case .offers: offerList
                case .detail(let index): offerDetail(index)
                case .compare: comparison
                case .career: career
                }
            }.padding(12)
        }.lineSpacing(large ? 5 : 3).defaultScrollAnchor(.top).id(route).background(GameTheme.board).foregroundStyle(GameTheme.boardInk)
            .navigationTitle(title(route)).navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GameTheme.board, for: .navigationBar).toolbarBackground(.visible, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar))
    }
    private func title(_ route: Route) -> String {
        switch route { case .report: "관찰 보고서"; case .offers: "도착한 계약 제의"; case .detail: "계약 제의 상세"; case .compare: "제의 비교"; case .career: "제의 없음 · 진로" }
    }
    private var report: some View {
        Group {
            ScoutDossier(title: clubs[0] + " · 관찰 보고서", code: "FIELD REPORT  /  017", stamp: "관찰 중") {
                paperRow("평가 기준일", date)
                paperRow("모집 역할", pitcher ? "선발 육성 후보" : "수비형 유격수 후보")
                paperRow("현재 단계", isSchool ? "관찰 / 계약 연령 미충족" : "국내 육성 검토")
                Text("최근 365일 · 같은 수준/역할의 성적만 평가").font(.caption).foregroundStyle(ScoutDossierInk.muted)
                metric("현재 기량 H", value: isSchool ? 56.4 : 71.8, target: 70)
                metric("2년 육성 전망", value: 76.2, target: 72)
                Text("진한 선은 구단 기준 · 초록은 샘플 평가값").font(.caption).foregroundStyle(ScoutDossierInk.muted)
            }
            GamePanel(title: "평가 근거 · 조건 확인", onBoard: true, contentSpacing: sectionGap) {
                row("구단 기준 C", "70.0 · 샘플 모집 기준")
                row("실전 보정 P", isSchool ? "산정 대기" : "+1.2 · 같은 수준 성적")
                row("적합 여유 F", isSchool ? "계약 심사 전" : "+3.0 · 참고 표시")
                row("표본", scenario == .offers ? (pitcher ? "32.0이닝 / 전력 25.0이닝" : "128타석 / 전력 100타석") : (pitcher ? "18.0이닝 / 전력 25.0이닝" : "62타석 / 전력 100타석"))
                row("신뢰도", scenario == .offers ? "전력 표본 충족 · 샘플" : "표본 축적 중 · 샘플")
                row("권리·자격", isSchool ? "20세 미만 · 정식 제의 불가" : "국내 신규 계약 검토 가능")
                Text("육성 심사와 즉시 전력 심사의 표본 기준은 다릅니다. 수치와 제의는 화면 설명용이며 엔진 산출 결과가 아닙니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
            }
            GamePanel(title: "다음 관찰까지 보완할 것", onBoard: true, contentSpacing: sectionGap) {
                Text(pitcher ? "01 제구 보완\n02 실제 등판 표본 축적\n03 지구력 성장 확인" : "01 선구안 보완\n02 실제 출전 표본 축적\n03 유격수 수비 성장 확인").font(.subheadline).lineSpacing(7)
                Text("다음 보고서 " + nextReport + " · 열람/재접속으로 평가를 다시 뽑지 않음").font(.caption).foregroundStyle(GameTheme.gold)
            }
        }
    }
    private var offerList: some View {
        Group {
            Label("구단에서 도착한 제의 2건", systemImage: "envelope.badge.fill").font(.headline).foregroundStyle(GameTheme.gold)
                .transition(.opacity.combined(with: .offset(y: reduced ? 0 : 8)))
            Text("발행 2030.04.01 · 04.07까지 회신").font(.caption.monospaced()).foregroundStyle(GameTheme.boardMuted)
            ForEach(0..<2, id: \.self) { index in
                GamePanel(title: clubs[index], onBoard: true, contentSpacing: sectionGap) {
                    clubIdentity(index)
                    row("모집", role)
                    row("조건", index == 0 ? "육성 · 1년 / 지수118" : "전력 경쟁 · 2년 / 지수130")
                    Text("출전·승격 보장 없음").font(.caption).foregroundStyle(GameTheme.boardMuted)
                    NavigationLink { destination(.detail(index)) } label: { Text("제의 상세 보기") }.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("scoutOffer-\(index)")
                }
            }
            NavigationLink { destination(.compare) } label: { Text("2개 제의 비교") }.buttonStyle(MatchPixelButtonStyle(primary: true)).accessibilityIdentifier("scoutCompare")
            Text("현 소속 갱신 없음 · 무소속 샘플 / 구단은 가상 명칭").font(.caption).foregroundStyle(GameTheme.boardMuted)
        }
    }
    private func offerDetail(_ index: Int) -> some View {
        Group {
            ScoutDossier(title: clubs[index], code: "CONTRACT OFFER  /  0\(index + 1)", stamp: "답신 대기") {
                clubIdentity(index, paper: true)
                paperRow("리그 / 역할", "국내 프로형 / " + role)
                paperRow("종류 / 배치", index == 0 ? "육성 계약 / 2군 육성" : "전력 계약 / 1군 경쟁")
                paperRow("계약 기간", index == 0 ? "1년 · 04.01~2031.03.31" : "2년 · 04.01~2032.03.31")
                paperRow("발효 예정", "2030.04.01 · 일정/권리 확인 후")
                paperRow("연봉지수", index == 0 ? "118 · 국내 육성 기준100" : "130 · 국내 전력 기준100")
                paperRow("제의 만료", "2030.04.07 포함 · 게임 날짜")
                paperRow("필요 승인", "현재 샘플: 별도 이적 승인 없음")
                paperRow("예상 경쟁", index == 0 ? "육성 자리 / 단계별 평가" : "동일 포지션 경쟁 / 선발 미보장")
                Text("지수는 해당 리그·계약종류 기준입니다. 서로 다른 기준의 실제 연봉 금액을 뜻하지 않습니다.").font(.caption).foregroundStyle(ScoutDossierInk.muted)
            }
            if let receipt { Text(receipt).font(.subheadline.bold()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("scoutDecisionReceipt") }
            Button("수락 흐름 보기") { decision = clubs[index] + " 수락" }.buttonStyle(MatchPixelButtonStyle(primary: true)).accessibilityIdentifier("scoutAccept")
            Button("거절 흐름 보기") { decision = clubs[index] + " 거절" }.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("scoutDecline")
            NavigationLink { destination(.compare) } label: { Text("다른 제의와 비교") }.buttonStyle(MatchPixelButtonStyle())
        }
    }
    private var comparison: some View {
        GamePanel(title: "제의 비교 · 국내 2개 구단", onBoard: true, contentSpacing: sectionGap) {
            ForEach(0..<2,id:\.self) { index in
                NavigationLink { destination(.detail(index)) } label: { Text(clubs[index] + " 상세") }.buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("scoutCompareDetail-\(index)")
            }

            compareRow("구단",clubs[0],clubs[1])
            compareRow("배치","2군 육성","1군 전력 경쟁")
            compareRow("기간","1년","2년")
            compareRow("연봉지수","118 / 육성 기준","130 / 전력 기준")
            compareRow("발효","2030.04.01","2030.04.01")
            compareRow("종료","2031.03.31","2032.03.31")
            compareRow("만료","2030.04.07","2030.04.07")
            compareRow("출전 보장","없음","없음")
            Text("배치·기회·기간을 비교하세요. 육성/전력 기준이 달라 지수만으로 유불리를 정렬하지 않습니다.").font(.caption).foregroundStyle(GameTheme.gold)
        }
    }
    private var career: some View {
        Group {
            GamePanel(title: "이번 창 · 제의가 없습니다", onBoard: true, contentSpacing: sectionGap) {
                Text("게임은 계속됩니다").font(.title3.bold()).foregroundStyle(GameTheme.gold)
                row("충족", "20세 · 국내 신규 계약 자격 / 기량 기준")
                row("전력 심사 대기", pitcher ? "18.0 / 25.0이닝" : "62 / 100타석")
                row("육성 제의 없음", "이번 모집 자리 / 후보 경쟁")
                row("다음 기회", "관찰 05.06 / 계약 창 07.01")
                Text("다시 열어도 이번 창의 결과는 바뀌지 않습니다.").font(.caption).foregroundStyle(GameTheme.boardMuted)
            }
            GamePanel(title: "다음 진로 · 화면 선택", onBoard: true, contentSpacing: sectionGap) {
                ForEach(["대학 진학 검토", "무소속으로 재도전"],id:\.self) { option in
                    Button(option) { careerChoice = option }.buttonStyle(MatchPixelButtonStyle(primary: careerChoice == option)).accessibilityIdentifier("scoutCareer-" + option)
                }
                Text("대학: 입단 자격·모집 여부 확인 필요\n무소속: 훈련·평가전으로 다음 심사 준비").font(.subheadline).lineSpacing(6)
                if let careerChoice { Text(careerChoice + " · 선택 미리보기 / 실제 학적·소속은 변경되지 않습니다.").font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("scoutCareerReceipt") }
            }
            NavigationLink { destination(.report) } label: { Text("부족한 조건 다시 보기") }.buttonStyle(MatchPixelButtonStyle())
        }
    }
    private func row(_ key: String, _ value: String) -> some View {
        (large ? AnyLayout(VStackLayout(alignment:.leading,spacing:textGap)) : AnyLayout(HStackLayout(alignment:.top,spacing:10))) {
            Text(key).font(.caption).foregroundStyle(GameTheme.boardMuted).frame(minWidth: large ? 0 : 82,alignment:.leading)
            if !large { Spacer(minLength: 0) }
            Text(value).font(.subheadline.monospaced()).multilineTextAlignment(large ? .leading : .trailing)
        }.fixedSize(horizontal:false,vertical:true).padding(.vertical,4).accessibilityElement(children:.combine)
    }
    private func metric(_ label: String, value: Double, target: Double) -> some View {
        VStack(alignment:.leading,spacing:textGap) {
            paperRow(label,String(format:"%.1f / 100",value))
            GeometryReader { g in
                ZStack(alignment:.leading) {
                    Rectangle().fill(ScoutDossierInk.rule)
                    Rectangle().fill(ScoutDossierInk.green).frame(width:g.size.width * value / 100)
                    Rectangle().fill(ScoutDossierInk.ink).frame(width:2).offset(x:g.size.width * target / 100)
                }
            }.frame(height:9).accessibilityHidden(true)
        }
    }
    private func compareRow(_ key: String, _ left: String, _ right: String) -> some View {
        VStack(alignment:.leading,spacing:textGap) {
            Text(key).font(.caption).foregroundStyle(GameTheme.boardMuted)
            (large ? AnyLayout(VStackLayout(alignment:.leading,spacing:textGap)) : AnyLayout(HStackLayout(alignment:.top,spacing:16))) {
                Text(large ? clubs[0]+" · "+left : left).frame(maxWidth:.infinity,alignment:.leading)
                Text(large ? clubs[1]+" · "+right : right).frame(maxWidth:.infinity,alignment:.leading)
            }.font(.subheadline.monospaced())
            Rectangle().fill(GameTheme.boardLine).frame(height:1).accessibilityHidden(true)
        }.fixedSize(horizontal:false,vertical:true)
    }
}

private struct ScoutPixelEmblem: View {
    var body: some View {
        Canvas { context, size in
            let pixels = ["0011111100","0110000110","1101111011","1101001011","1101111011","1100000011","1101111011","0110110110","0011111100","0001100000","0011110000"]
            let unit = min(size.width/10,size.height/11)
            for (y,row) in pixels.enumerated() { for (x,pixel) in row.enumerated() where pixel == "1" {
                context.fill(Path(CGRect(x:CGFloat(x)*unit,y:CGFloat(y)*unit,width:unit,height:unit)),with:.color(GameTheme.gold))
            }}
        }
    }
}
#endif

// Shared presentation only. The live report supplies real values; the DEBUG preview stays isolated.
enum ScoutOfficeArt {
    static let image: UIImage? = Bundle.main.url(forResource: "scout-office-v1", withExtension: "png", subdirectory: "MatchArt")
        .flatMap { UIImage(contentsOfFile: $0.path) }
}
enum ScoutDossierInk {
    static let paper = Color(red:0.93,green:0.88,blue:0.74)
    static let ink = Color(red:0.14,green:0.23,blue:0.25)
    static let muted = Color(red:0.30,green:0.34,blue:0.31)
    static let rule = Color(red:0.73,green:0.72,blue:0.60)
    static let green = Color(red:0.16,green:0.38,blue:0.30)
}
struct ScoutDossier<Content: View>: View {
    let title: String
    let code: String
    let stamp: String
    var isPreview = true
    @ViewBuilder var content: Content
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var opened = false
    @ScaledMetric(relativeTo: .body) private var scaledSectionGap: CGFloat = 16
    private var sectionGap: CGFloat { min(scaledSectionGap, 24) }
    var body: some View {
        VStack(alignment: .leading, spacing: sectionGap) {
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:6)) : AnyLayout(HStackLayout(alignment:.top))) {
                Text(code).font(.caption2.monospaced().bold()).foregroundStyle(ScoutDossierInk.muted)
                if !typeSize.isAccessibilitySize { Spacer(minLength: 0) }
                Text(stamp).font(.caption.monospaced().bold()).foregroundStyle(ScoutDossierInk.green)
                    .padding(.horizontal,8).padding(.vertical,4).overlay(Rectangle().strokeBorder(ScoutDossierInk.green,lineWidth:2))
            }
            Text(title).font(.headline.monospaced()).foregroundStyle(ScoutDossierInk.ink)
            Rectangle().fill(ScoutDossierInk.ink).frame(height: 2).accessibilityHidden(true)
            content
            HStack {
                Text("BM  /  SCOUTING DEPARTMENT").font(.caption2.monospaced()).foregroundStyle(ScoutDossierInk.muted)
                Spacer(minLength: 0)
                Text(isPreview ? "시안" : "실제 선수 자료").font(.caption2.bold()).foregroundStyle(ScoutDossierInk.muted)
            }.padding(.top,4)
        }.padding(18).frame(maxWidth:.infinity,alignment:.leading)
            .foregroundStyle(ScoutDossierInk.ink).background(ScoutDossierInk.paper)
            .overlay(Rectangle().strokeBorder(ScoutDossierInk.rule,lineWidth:2))
            .padding(.bottom,4).background(alignment:.bottom) { Rectangle().fill(ScoutDossierInk.rule).padding(.horizontal,4) }
            .opacity(opened || reduced ? 1 : 0).offset(y: opened || reduced ? 0 : 8)
            .animation(reduced ? nil : .easeOut(duration:0.25), value: opened)
            .onAppear { opened = true }
    }
}


struct DomesticOfferHomePanel: View {
    let player:CareerPlayer
    let calendar:CareerCalendarState
    let evaluation:CareerContractEvaluation
    @Environment(\.modelContext) private var context
    @Query private var packets:[CareerContractOffer]
    @Query private var registrations:[CareerContractRegistration]
    @State private var refresh=0
    private func load() -> Result<DomesticOfferPacket?,Error> {
        do {
            _ = packets.count;_ = registrations.count
            _ = try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)
            let row=try ContractOfferStore.records(player:player,calendar:calendar,in:context).first {$0.key == evaluation.key}
            return .success(try row?.snapshot(evaluation:evaluation,player:player,calendar:calendar))
        } catch {return .failure(error)}
    }
    var body: some View {
        let _=refresh
        switch load() {
        case .failure(let error):
            Text(error.localizedDescription).font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("contractOffersError")
            Button("제의 다시 확인") {refresh += 1}.buttonStyle(MatchPixelButtonStyle())
        case .success(let value):
            if let value {
                let today=try? GameDate(player.gameDate)
                let decisions=(try? ContractRegistrationStore.journal(player:player,calendar:calendar,in:context).decisions) ?? []
                let active=value.offers.filter {offer in !decisions.contains(where:{$0.offerID == offer.id}) && (today.map {(try? offer.isExpired(on:$0)) == false} ?? false)}.count
                Text("실제 제의 \(value.offers.count)건 · 유효 \(active)건")
                    .font(.subheadline.bold()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("contractOffersHomeStatus")
                if value.offers.isEmpty {
                    Text(value.emptyReasons.first ?? "이번 창의 제의 없음").font(.caption).foregroundStyle(GameTheme.boardMuted)
                } else {
                    Text(value.offers.map {$0.name+" · "+($0.collegeEntry != nil ? "대학→프로":$0.reentry == true ? "재입단":$0.route.label)}.joined(separator:" / ")).font(.caption)
                }
                NavigationLink {DomesticOffersView(player:player,calendar:calendar,evaluation:evaluation)} label: {
                    Text(value.offers.isEmpty ? "제의 없음 · 부족 조건 확인":active > 0 ? "도착한 제의 · 상세/비교":"제의 결정 · 이력 보기")
                }.buttonStyle(MatchPixelButtonStyle(primary:active > 0)).accessibilityIdentifier("openDomesticOffers")
            } else {
                Text("제의 자료 미기록 · 과거 평가를 다시 심사하거나 지난 창에 제의를 소급 발행하지 않습니다.")
                    .font(.caption).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("contractOffersUnrecorded")
            }
        }
    }
}
struct DomesticOffersView: View {
    enum Page {case list,detail(String),compare}
    let player:CareerPlayer
    let calendar:CareerCalendarState
    let evaluation:CareerContractEvaluation
    var page:Page = .list
    struct Command {let offer:DomesticContractOffer;let accept:Bool;let date:String;let revision:Int}
    @State private var command:Command?
    @State private var failure:String?
    @State private var receipt:String?

    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var typeSize
    @Query private var packets:[CareerContractOffer]
    @Query private var registrations:[CareerContractRegistration]
    @State private var refresh=0
    private func load() -> Result<(DomesticOfferPacket,ContractEvaluationSnapshot),Error> {
        do {
            _ = packets.count;_ = registrations.count
            guard let row=try ContractOfferStore.records(player:player,calendar:calendar,in:context).first(where:{$0.key == evaluation.key}) else {throw ContractOfferError.invalid}
            _ = try ContractRegistrationStore.journal(player:player,calendar:calendar,in:context)
            return .success((try row.snapshot(evaluation:evaluation,player:player,calendar:calendar),try evaluation.snapshot(player:player,calendar:calendar)))
        } catch {return .failure(error)}
    }
    var body: some View {
        let _=refresh
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                switch load() {
                case .failure(let error):
                    GamePanel(title:"제의 조회 오류",onBoard:true) {
                        Text(error.localizedDescription).font(.subheadline)
                        Button("다시 확인") {refresh += 1}.buttonStyle(MatchPixelButtonStyle())
                    }
                case .success(let pair):
                    let packet=pair.0,value=pair.1
                    Text("제의 원본 · \(packet.issuedDate) 발행 / \(value.evaluatedDate) 평가")
                        .font(.caption.monospaced()).foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("liveOfferIssued")
                    switch page {
                    case .list:list(packet,value)
                    case .detail(let id):
                        if let offer=packet.offers.first(where:{$0.id == id}) {detail(offer,value)}
                        else {Text(ContractOfferError.invalid.localizedDescription)}
                    case .compare:compare(packet)
                    }
                    if let receipt {Text(receipt).font(.subheadline.bold()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("liveOfferDecisionReceipt")}
                }
            }.padding(14).frame(maxWidth:540,alignment:.leading).frame(maxWidth:.infinity)
        }.background(GameTheme.navy).foregroundStyle(GameTheme.boardInk)
            .navigationTitle(title).navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(GameTheme.navy,for:.navigationBar).toolbarBackground(.visible,for:.navigationBar)
            .toolbarColorScheme(.dark,for:.navigationBar).tint(GameTheme.gold)
            .confirmationDialog("제의 결정을 확정할까요?",isPresented:Binding(get:{command != nil},set:{if !$0 {command=nil}}),titleVisibility:.visible) {
                if let selected=command {
                    Button(selected.accept ? "수락 확정":"거절 확정",role:selected.accept ? nil:.destructive) {complete(selected)}.accessibilityIdentifier("confirmOfferDecision")
                }
                Button("취소",role:.cancel) {command=nil}
            } message: {
                if let selected=command {Text(selected.accept ? "\(selected.offer.name) 계약을 수락합니다. \(selected.offer.collegeEntry.map { $0.effectiveDate+"부터 프로 소속으로 전환하며 그 전까지 대학 소속을 유지합니다." } ?? "오늘 소속을 등록합니다.") 다른 열린 제의는 닫히며 날짜·피로·능력치는 유지합니다.":"이 제의를 거절합니다. 같은 창에서 다시 발행하지 않으며 다른 열린 제의는 유지합니다.")}
            }
            .alert("제의 결정을 완료하지 못했습니다",isPresented:Binding(get:{failure != nil},set:{if !$0 {failure=nil}})) {
                Button("확인") {failure=nil}
            } message:{Text(failure ?? "")}
    }
    private func complete(_ selected:Command) {
        do {
            try ContractRegistrationStore.decide(player:player,calendar:calendar,offerID:selected.offer.id,accept:selected.accept,date:selected.date,revision:selected.revision,in:context)
            receipt=selected.accept ? selected.offer.name+(selected.offer.collegeEntry != nil ? " · 수락/소속 전환 예약 완료":" · 수락/소속 발효 완료"):"제의 거절 완료 · 다른 열린 제의는 유지합니다."
        } catch {failure=error.localizedDescription}
        command=nil
    }
    private var title:String {switch page {case .list:"도착한 제의";case .detail:"제의 상세";case .compare:"제의 비교"}}
    private func status(_ offer:DomesticContractOffer) -> String {
        if let decision=try? ContractRegistrationStore.journal(player:player,calendar:calendar,in:context).decisions.first(where:{$0.offerID == offer.id}) {
            switch decision.kind {case .accepted:return offer.collegeEntry.map {$0.effectiveDate > player.gameDate ? "수락 · 전환 예약":"수락 · 소속 발효"} ?? "수락 · 소속 발효";case .rejected:return "거절 완료";case .closed:return "다른 제의 수락으로 종료"}
        }
        guard let date=try? GameDate(player.gameDate),let expired=try? offer.isExpired(on:date) else {return "날짜 확인 필요"}
        return expired ? "기간 만료":"검토 가능"
    }
    @ViewBuilder private func list(_ packet:DomesticOfferPacket,_ value:ContractEvaluationSnapshot) -> some View {
        if packet.offers.isEmpty {
            GamePanel(title:"이번 평가 · 제의 없음",onBoard:true) {
                Text("다음 기회를 준비할 수 있습니다").font(.headline).foregroundStyle(GameTheme.gold).accessibilityIdentifier("liveOffersEmpty")
                ForEach(packet.emptyReasons,id:\.self) {Text($0).font(.subheadline).lineSpacing(4)}
                Text(value.version == 4 ? "다음 국내 육성팀 재입단 평가는4월·7월입니다.":value.window.month == 4 ? "다음 국내 신인 창은7월 · 대학은 다음 해4월입니다.":"다음 국내 신인·대학 창은 다음 해4월입니다.")
                    .font(.caption).foregroundStyle(GameTheme.boardMuted)
                Text("훈련으로 보완해도 이번 창의 결과는 다시 뽑지 않습니다.").font(.caption)
            }
        }
        ForEach(packet.offers) {offer in
            GamePanel(title:offer.collegeEntry != nil ? "대학 재학생 · 프로 진출":offer.reentry == true ? "무소속 재도전 · 육성팀 재입단":offer.route == .rookie ? "프로 진입 · 신인 지명":"학적 선택 · 대학 선발",onBoard:true,contentSpacing:12) {
                Text(offer.name).font(.title3.bold()).foregroundStyle(GameTheme.gold)
                Text(offer.kind+" / "+DomesticContractOffer.roleName(offer.roleID)).font(.subheadline)
                Text(status(offer)+" · "+offer.expiresDate+"까지(포함)").font(.caption).accessibilityIdentifier("liveOfferStatus-"+offer.route.rawValue)
                Text(offer.economicLabel+" \(offer.economicIndex) · "+offer.period).font(.caption).foregroundStyle(GameTheme.boardMuted)
                NavigationLink {DomesticOffersView(player:player,calendar:calendar,evaluation:evaluation,page:.detail(offer.id))} label: {Text("제의 상세 보기")}
                    .buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("liveOfferDetail-"+offer.route.rawValue)
            }
        }
        if packet.offers.count > 1 {
            NavigationLink {DomesticOffersView(player:player,calendar:calendar,evaluation:evaluation,page:.compare)} label: {Text("제의 조건 비교")}
                .buttonStyle(MatchPixelButtonStyle(primary:true)).accessibilityIdentifier("liveOffersCompare")
        }
        Text("실제 선발 결과에서 발행된 제의입니다. 수락/거절은 상세에서 확정하며 조회만으로 소속·능력·피로·날짜를 바꾸지 않습니다.")
            .font(.caption).foregroundStyle(GameTheme.boardMuted).lineSpacing(4)
    }
    private func detail(_ offer:DomesticContractOffer,_ value:ContractEvaluationSnapshot) -> some View {
        VStack(alignment:.leading,spacing:16) {
            ScoutDossier(title:offer.name,code:"LIVE OFFER / "+offer.route.rawValue.uppercased(),stamp:status(offer),isPreview:false) {
                detailRow("선수",value.observation.name+" · #\(value.observation.number) / "+value.observation.role.label)
                detailRow("모집 역할",DomesticContractOffer.roleName(offer.roleID))
                detailRow("종류 / 배치",offer.kind+" / "+offer.placement)
                detailRow("기간",offer.period)
                detailRow(offer.economicLabel,"\(offer.economicIndex) · 해당 경로 기준100")
                detailRow("발행 / 만료",offer.issuedDate+" / "+offer.expiresDate+"까지 포함")
                detailRow("발효 / 종료일",registrationTerms(offer))
                detailRow("계약금/옵션/성과급","0 · 실제 통화 금액 아님")
                detailRow("연간 예산","잔여\(offer.availableBudget) / 필요\(offer.economicIndex)지수")
                detailRow("경쟁/선발","적격 경쟁\(offer.competition)명 · 고정F/ID 순으로 선발")
                detailRow("필요 확인",offer.collegeEntry != nil ? "대학 재학생 자격 검증 · 발효 전 대학 소속/학적 유지":"성인 무소속 신규 지원 · 수락/등록은 별도")
                detailRow("출전 보장","없음 · 입단 후 역할/선발 경쟁")
            }
            GamePanel(title:"선발 근거 · 고정 평가 자료",onBoard:true,contentSpacing:12) {
                Text(String(format:"H %.1f / C %.1f / P %+.1f / F %+.1f",offer.h,offer.c,offer.p,offer.f))
                    .font(.subheadline.monospaced()).accessibilityIdentifier("liveOfferFit")
                if let sample=value.selection?.sample {
                    Text(sample.kind+" · "+sample.endDate+" 종료").font(.subheadline)
                    Text(value.observation.role == .batter ? "\(sample.comparison.totals.line.plateAppearances)타석 · 같은 환경40타석 이상":"\(sample.comparison.totals.innings)이닝 · 같은 환경15이닝 이상").font(.caption)
                }
                Text("발행 뒤 훈련/경기·재실행으로 제의 조건을 재계산하지 않습니다. 현재 능력과 당시 평가를 구분해 보세요.")
                    .font(.caption).foregroundStyle(GameTheme.boardMuted)
            }
            if status(offer) == "검토 가능" {
                Text(offer.collegeEntry.map {"수락 시 "+$0.effectiveDate+" 소속 전환을 예약하며 그 전까지 대학 소속을 유지합니다. 다른 열린 제의는 닫힙니다."} ?? "수락하면 오늘 소속이 발효되고 다른 열린 제의는 닫힙니다. 진행 중인 경기·훈련을 먼저 마쳐 주세요.").font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("liveOfferDecisionGuide")
                Button("수락 · 소속 등록") {command=Command(offer:offer,accept:true,date:player.gameDate,revision:calendar.revision)}
                    .buttonStyle(MatchPixelButtonStyle(primary:true)).accessibilityIdentifier("acceptLiveOffer")
                Button("이 제의 거절") {command=Command(offer:offer,accept:false,date:player.gameDate,revision:calendar.revision)}
                    .buttonStyle(MatchPixelButtonStyle()).accessibilityIdentifier("rejectLiveOffer")
            } else {Text(status(offer)+" · 원본 조건과 결정 이력을 보관합니다.").font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("liveOfferFinalDecision")}

        }
    }
    private func registrationTerms(_ offer:DomesticContractOffer) -> String {
        if let member=try? ContractRegistrationStore.journal(player:player,calendar:calendar,in:context).memberships.first(where:{$0.offerID == offer.id}) {
            return member.since+" 발효 · 경제 기간 "+member.economicEnd+(member.route == .rookie ? " / 보유 권리는 별도":" / 학적 종료 "+(member.enrollmentEnd ?? "—"))
        }
        if let entry=offer.collegeEntry {return entry.effectiveDate+" 발효 · 1년 경제 기간 / 대학 학적 원본 보존"}
        return "수락일 발효 · 1년 경제 기간 / 현재 소속 유지"
    }
    private func detailRow(_ label:String,_ value:String) -> some View {
        VStack(alignment:.leading,spacing:7) {
            Text(label).font(.caption.bold()).foregroundStyle(ScoutDossierInk.muted)
            Text(value).font(.subheadline.monospaced()).fixedSize(horizontal:false,vertical:true)
            Rectangle().fill(ScoutDossierInk.rule).frame(height:1).accessibilityHidden(true)
        }.padding(.vertical,4).accessibilityElement(children:.combine)
    }
    private func compare(_ packet:DomesticOfferPacket) -> some View {
        GamePanel(title:"제의 조건 · 나란히 비교",onBoard:true,contentSpacing:18) {
            if packet.offers.count == 2 {
                let a=packet.offers[0],b=packet.offers[1]
                compareRow("구단 / 대학",a.name,b.name)
                compareRow("종류",a.kind,b.kind)
                compareRow("모집 역할",DomesticContractOffer.roleName(a.roleID),DomesticContractOffer.roleName(b.roleID))
                compareRow("배치",a.placement,b.placement)
                compareRow("기간",a.period,b.period)
                compareRow("경제 조건",a.economicLabel+" \(a.economicIndex)",b.economicLabel+" \(b.economicIndex)")
                compareRow("만료(포함)",a.expiresDate,b.expiresDate)
                compareRow("현재 상태",status(a),status(b))
                compareRow("고정 적합도 F",String(format:"%+.1f",a.f),String(format:"%+.1f",b.f))
                Text("연봉지수와 대학 지원지수는 다른 기준입니다. 숫자를 실제 금액처럼 합산하거나 유불리 순위로 해석하지 않습니다.")
                    .font(.caption).foregroundStyle(GameTheme.gold).accessibilityIdentifier("liveOfferCompareCaution")
            } else {Text("비교할 제의가2개일 때 표시됩니다.")}
        }
    }
    private func compareRow(_ label:String,_ a:String,_ b:String) -> some View {
        VStack(alignment:.leading,spacing:9) {
            Text(label).font(.caption.bold()).foregroundStyle(GameTheme.gold)
            (typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment:.leading,spacing:10)):AnyLayout(HStackLayout(alignment:.top,spacing:16))) {
                Text(a).frame(maxWidth:.infinity,alignment:.leading)
                Text(b).frame(maxWidth:.infinity,alignment:.leading)
            }.font(.subheadline.monospaced()).fixedSize(horizontal:false,vertical:true)
            Rectangle().fill(GameTheme.boardLine).frame(height:1).accessibilityHidden(true)
        }
    }
}
