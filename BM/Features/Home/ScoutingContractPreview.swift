import SwiftUI

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
