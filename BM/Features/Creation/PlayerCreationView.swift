import SwiftUI
import SwiftData

struct PlayerCreationView: View {
    let schools: [School]
    let availableRoles: [PlayerRole]
    var onSaving: (Bool) -> Void = { _ in }
    let onCreated: (UUID) -> Void
    @Environment(\.modelContext) private var context
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Environment(\.scenePhase) private var scenePhase
    @Query private var existingPlayers: [CareerPlayer]
    @State private var section = CreationSection.information
    @State private var registeredID: UUID?
    @State private var registrationTask: Task<Void, Never>?
    @State private var draft = PlayerDraft()
    @State private var errorMessage: String?
    @State private var showSchools = false
    @State private var showGamePreview = false
    @FocusState private var focusedField: Field?
    private enum Field { case name, number }
    private enum CreationSection: String, CaseIterable {
        case information, abilities, appearance, review
        var title: String {
            switch self { case .information: "정보"; case .abilities: "유형·능력"; case .appearance: "외형"; case .review: "확인" }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
        Group {
        if section == .appearance {
            CreationAppearanceEditor(draft: $draft, school: selectedSchool,
                previous: { section = .abilities }, next: { section = .review })
        } else {
        ScrollView {
            VStack(spacing: ManagementTheme.Space.screen) {
                CreationIdentityCard(appearance: draft.appearance, role: draft.role,
                    number: draft.jerseyNumber, name: draft.name, school: selectedSchool,
                    position: draft.role == .batter ? draft.position.label : draft.throwingHand.label,
                    typeLabel: draft.isCustom ? "사용자 지정" : draft.selectedArchetype.label,
                    points: draft.assignedAbilityPoints, budget: draft.abilityBudget, compact: true)
                    .accessibilityIdentifier("creationPreview")

                GamePanel(title: "선수 정보", onBoard: true) {
                    Text("선수 이름 · 가상 이름 1~12자").font(.caption).foregroundStyle(GameTheme.boardMuted)
                    TextField("선수 이름", text: $draft.name, prompt: Text("선수 이름").foregroundStyle(GameTheme.boardMuted))
                        .focused($focusedField, equals: .name)
                        .accessibilityLabel("선수 이름").accessibilityIdentifier("playerName")
                        .accessibilityHint("실명 대신 가상 이름이나 별명을 사용할 수 있습니다.")
                        .padding(12).background(GameTheme.board)
                        .overlay(Rectangle().strokeBorder(GameTheme.boardLine, lineWidth: 1))
                    HStack {
                        Text("등번호")
                        TextField("0~99", text: $draft.jerseyNumber, prompt: Text("0~99").foregroundStyle(GameTheme.boardMuted))
                            .keyboardType(.numberPad).focused($focusedField, equals: .number)
                            .accessibilityLabel("등번호").accessibilityIdentifier("jerseyNumber")
                            .multilineTextAlignment(.trailing).padding(12).background(GameTheme.board)
                            .overlay(Rectangle().strokeBorder(GameTheme.boardLine, lineWidth: 1))
                    }
                    Text("나의 플레이").font(.caption).foregroundStyle(GameTheme.boardMuted)
                    LazyVGrid(columns: choiceColumns, spacing: 8) {
                        ForEach(availableRoles) { role in
                            choice(role.label, selected: draft.role == role, id: "role-" + role.rawValue) {
                                focusedField = nil; draft.role = role
                            }
                        }
                    }
                    Text(draft.role == .batter ? "주 포지션" : "투구 손")
                        .font(.caption).foregroundStyle(GameTheme.boardMuted)
                    LazyVGrid(columns: choiceColumns, spacing: 8) {
                        if draft.role == .batter {
                            ForEach(FieldPosition.allCases) { position in
                                choice(position.label, selected: draft.position == position, id: "position-" + position.rawValue) {
                                    focusedField = nil; draft.position = position
                                }
                            }
                        } else {
                            ForEach(ThrowingHand.allCases) { hand in
                                choice(hand.label, selected: draft.throwingHand == hand, id: "hand-" + hand.rawValue) {
                                    focusedField = nil; draft.throwingHand = hand
                                }
                            }
                        }
                    }
                }.id(CreationSection.information.rawValue)
                GamePanel(title: "소속 학교", onBoard: true) {
                    Button { focusedField = nil; showSchools = true } label: {
                        HStack {
                            if let selectedSchool { SchoolCrest(school: selectedSchool).frame(width: 40, height: 44) }
                            VStack(alignment: .leading, spacing: 4) {
                                Text(selectedSchool?.name ?? "학교 선택")
                                    .fontWeight(.bold)
                                Text("가상 고교 \(schools.count)곳").font(.caption)
                            }
                            if !dynamicTypeSize.isAccessibilitySize { Spacer(); Text("선택 ›") }
                        }.frame(minHeight: 48)
                    }.buttonStyle(GameButtonStyle(secondary: true, onBoard: true)).accessibilityIdentifier("schoolPicker")
                    Button("학교 무작위 선택") { draft.schoolID = schools.randomElement()?.id ?? "" }
                        .buttonStyle(GameButtonStyle(secondary: true, onBoard: true)).accessibilityIdentifier("randomSchool")
                    if let selectedSchool { SchoolReputationLabels(school: selectedSchool) }
                    Text("이름·교표는 게임 전용 창작 설정입니다. 학교를 골라도 시작 능력·성장 배율은 같습니다.").managementFont(.helper)
                }
                GamePanel(title: "선수 유형 · 시작 능력", onBoard: true) {
                    LazyVGrid(columns: choiceColumns, spacing: 8) {
                        ForEach(PlayerArchetype.choices(for: draft.role)) { archetype in
                            archetypeChoice(archetype) {
                                draft.archetype = archetype; draft.isCustom = false
                            }
                        }
                        typeChoice(title: "사용자 지정", detail: "내가 원하는 능력 배분", kind: "custom",
                            accent: Color(hex: 0xb9cbd4), selected: draft.isCustom, identifier: "archetype-custom") {
                            if draft.allocation == nil { draft.allocation = PlayerStatAllocation(role: draft.role, base: draft.selectedArchetype.values) }
                            draft.isCustom = true
                        }
                    }
                    Text("\(draft.isCustom ? "사용자 지정" : draft.selectedArchetype.label) · 전체 \(draft.assignedAbilityPoints) / \(draft.abilityBudget)점")
                        .font(.subheadline.bold()).accessibilityIdentifier("archetypePreviewTitle")
                    if draft.role == .pitcher {
                        Text("투구 4종 \(draft.pitchingAbilityPoints)점 + 스피드·수비·송구·멘탈 · 전체 8개 능력").managementFont(.helper)
                    } else { Text("타격·주루·수비·멘탈 · 전체 7개 능력").managementFont(.helper) }
                    if draft.isCustom {
                        Text("남은 \(draft.allocation?.remaining ?? 0) / \(draft.role == .batter ? 388 : 459)점")
                            .font(.headline.monospaced()).foregroundStyle(GameTheme.gold).accessibilityIdentifier("allocationRemaining")
                        Text("각 능력 0~100 · 1점씩 조절 · 남은 포인트를 모두 배분하세요.").font(.caption).foregroundStyle(GameTheme.boardMuted)
                        ForEach(PlayerStatAllocation.kinds(for: draft.role), id: \.rawValue) { kind in allocationRow(kind) }
                    } else {
                        let values = draft.initialValues
                        if draft.role == .batter {
                            creationStat(name: "컨택", value: values.contact)
                            creationStat(name: "파워", value: values.power)
                            creationStat(name: "선구안", value: values.discipline)
                        } else {
                            creationStat(name: "구속 능력", value: values.velocity ?? 0)
                            creationStat(name: "제구", value: values.control ?? 0)
                            creationStat(name: "구위", value: values.stuff ?? 0)
                            creationStat(name: "지구력", value: values.stamina ?? 0)
                        }
                        creationStat(name: "스피드", value: values.speed)
                        creationStat(name: "수비", value: values.defense)
                        creationStat(name: "송구", value: values.arm)
                        creationStat(name: "멘탈", value: values.mental)
                        Text(draft.role == .batter ? "유형은 시작 능력치만 바꿉니다. 성장 배율과 상한은 같습니다." : "구속 능력은 0~100점 기준 · 초기 구종 숙련은 아래 구성에서 확인하세요.")
                            .font(.caption).foregroundStyle(GameTheme.boardMuted)
                    }
                }.id(CreationSection.abilities.rawValue)
                if draft.role == .pitcher { pitchSelection }
                Button("도트 외형 꾸미기") { focusedField = nil; section = .appearance }
                    .buttonStyle(GameButtonStyle(onBoard: true)).id(CreationSection.appearance.rawValue)

                registrationReview.id(CreationSection.review.rawValue)
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Color(hex: 0xffb4a8)).font(.subheadline)
                        .accessibilityIdentifier("creationError")
                }
                Button("커리어 시작", action: save).buttonStyle(GameButtonStyle(onBoard: true))
                    .disabled(draft.isCustom && draft.allocation?.isValid != true)
                    .accessibilityIdentifier("createPlayer")
                Text("이 기기에 저장됩니다 · 활성 선수는 타자·투수 각 1명\n은퇴 선수의 소속·능력·기록은 보관됩니다.")
                    .font(.caption).foregroundStyle(GameTheme.boardMuted).multilineTextAlignment(.center)
            }.padding(16)
        }
        .accessibilityIdentifier("creationScroll")
        .scrollDismissesKeyboard(.interactively)
        .task(id: section) {
            await Task.yield()
            proxy.scrollTo(section.rawValue, anchor: .top)
        }
        }
        }
        .safeAreaInset(edge: .top, spacing: 0) { creationNavigation(proxy) }
        }
        .background(GameTheme.board).foregroundStyle(GameTheme.boardInk)
        .tint(GameTheme.gold).preferredColorScheme(.dark)
        .toolbarBackground(GameTheme.boardPanel, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationTitle("선수 만들기").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Text("선수 만들기").font(ManagementPixelFont.readable(.screenTitle))
            }
            if focusedField != nil {
                ManagementToolbarAction(title: "입력 완료", placement: .topBarTrailing) { focusedField = nil }
            }
        }
        .sheet(isPresented: $showSchools) {
            SchoolPicker(schools: schools, selected: $draft.schoolID)
        }
        .onAppear { if let role = availableRoles.first, !availableRoles.contains(draft.role) { draft.role = role } }
        .onChange(of: draft.role) { _, role in draft.archetype = .initial(for: role); draft.isCustom = false; draft.allocation = nil; draft.pitchCodes = nil }
        .disabled(registeredID != nil).accessibilityHidden(registeredID != nil)
        .overlay {
            if registeredID != nil {
                CreationRegistrationOverlay(appearance: draft.appearance, role: draft.role,
                                            number: Int(draft.jerseyNumber) ?? 0, name: draft.name, school: selectedSchool,
                                            position: draft.role == .batter ? draft.position.label : draft.throwingHand.label,
                                            typeLabel: draft.isCustom ? "사용자 지정" : draft.selectedArchetype.label,
                                            points: draft.assignedAbilityPoints, budget: draft.abilityBudget, reduced: reduced)
            }
        }
        .navigationBarBackButtonHidden(registeredID != nil)
        .interactiveDismissDisabled(registeredID != nil)
        .onChange(of: scenePhase) { _, phase in if phase != .active { finishRegistration() } }
        .onDisappear { registrationTask?.cancel(); registrationTask = nil }
        .onChange(of: draft.name) { _, _ in errorMessage = nil }
        .onChange(of: draft.jerseyNumber) { _, _ in errorMessage = nil }
        .onChange(of: draft.schoolID) { _, id in
            errorMessage = nil
            draft.appearance.schoolKitID = SchoolCreationKit.find(id)?.id
        }
        .onAppear { draft.appearance.creationVersion = 1 }
    }

    private func creationNavigation(_ proxy: ScrollViewProxy) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: dynamicTypeSize.isAccessibilitySize ? 2 : 4), spacing: 8) {
            ForEach(CreationSection.allCases, id: \.rawValue) { target in
                Button {
                    focusedField = nil; section = target
                } label: {
                    Text(target.title).font(ManagementPixelFont.readable(.label)).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(CreationStepButton(selected: section == target))
                    .accessibilityAddTraits(section == target ? .isSelected : [])
                    .accessibilityIdentifier("creationSection-" + target.rawValue)
            }
        }.padding(12).background(GameTheme.boardPanel)
    }
    private var registrationReview: some View {
        GamePanel(title: "등록 전 확인", onBoard: true) {
            CreationIdentityCard(appearance: draft.appearance, role: draft.role,
                number: draft.jerseyNumber, name: draft.name, school: selectedSchool,
                position: draft.role == .batter ? draft.position.label : draft.throwingHand.label,
                typeLabel: draft.isCustom ? "사용자 지정" : draft.selectedArchetype.label,
                points: draft.assignedAbilityPoints, budget: draft.abilityBudget)
            Text("전체 능력 \(draft.assignedAbilityPoints) / \(draft.abilityBudget)점 · \(draft.isCustom ? "사용자 지정" : draft.selectedArchetype.label)")
                .managementFont(.label).accessibilityIdentifier("creationReviewBudget")
            if draft.role == .pitcher {
                Text("구종 \(draft.selectedPitchCodes.count)개 · " + draft.selectedPitchCodes.compactMap { PitchType(rawValue: $0)?.label }.joined(separator: " · "))
                    .managementFont(.body).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("creationReviewPitches")
            }
            if let selectedSchool { SchoolReputationLabels(school: selectedSchool) }
            ForEach(PlayerRole.allCases) { role in
                let own = existingPlayers.filter { $0.role == role }
                Text("\(role.label) · 활성 \(own.filter { !$0.isRetired }.count)/1 · 보관 \(own.filter { $0.isRetired }.count)명")
                    .managementFont(.helper).accessibilityIdentifier("creationSlots-" + role.rawValue)
            }
            Text(registrationReadiness).managementFont(.body).foregroundStyle(GameTheme.gold)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("creationReadiness")
            VStack(alignment: .leading, spacing: 0) {
                Button { showGamePreview.toggle() } label: {
                    HStack {
                        Text("경기 동작 미리보기")
                        Spacer(minLength: 8)
                        Image(systemName: showGamePreview ? "chevron.up" : "chevron.down")
                            .foregroundStyle(GameTheme.gold).accessibilityHidden(true)
                    }.frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                        .contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityValue(showGamePreview ? "펼침" : "접힘")
                    .accessibilityIdentifier("creationGamePoseDisclosure")
                if showGamePreview { CreationGamePreview(draft: draft).padding(.top, 12) }
            }
            Text("확정하기 전에는 입력값만 바뀝니다. 저장에 실패하면 입력을 유지한 채 다시 시도할 수 있습니다.").managementFont(.helper)
        }
    }
    private var registrationReadiness: String {
        guard availableRoles.contains(draft.role), !existingPlayers.contains(where: { $0.role == draft.role && !$0.isRetired }) else {
            return CreationError.roleAlreadyExists.localizedDescription
        }
        do { try draft.validate(schools: schools); return "필수 항목 확인 완료 · 아래에서 커리어를 시작하세요." }
        catch { return error.localizedDescription }
    }

    private var selectedSchool: School? { schools.first { $0.id == draft.schoolID } }
    private var choiceColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
    }

    private var pitchSelection: some View {
        GamePanel(title: "구종 구성", onBoard: true) {
            HStack(alignment: .firstTextBaseline) {
                Text("보유 \(draft.selectedPitchCodes.count) / 5")
                    .font(.headline.monospaced()).foregroundStyle(GameTheme.gold)
                Spacer(minLength: 6)
                Text("남은 슬롯 \(max(0, 5 - draft.selectedPitchCodes.count))")
                    .font(.caption).foregroundStyle(GameTheme.boardMuted)
            }.accessibilityElement(children: .combine).accessibilityIdentifier("creationPitchCount")
            Text("3~5개를 선택하세요 · 습득한 구종은 이후 훈련으로 성장합니다.")
                .font(.caption).foregroundStyle(GameTheme.boardMuted)
            Text(draft.selectedPitchCodes.count == 3 ? "최소 3종 · 다른 구종을 추가한 뒤 기존 구종을 제외할 수 있습니다." : draft.selectedPitchCodes.count == 5 ? "최대 5종 · 기존 구종을 제외하면 새 구종을 선택할 수 있습니다." : "1종을 더 추가하거나 제외할 수 있습니다.")
                .managementFont(.helper).accessibilityIdentifier("creationPitchLimit")
            Text("구속 능력은 0~100점 · 개별 구종 숙련도도 0~100점입니다. 여기 표시한 점수는 km/h가 아닙니다.").managementFont(.helper)
            LazyVGrid(columns: choiceColumns, spacing: 8) {
                ForEach(PitchType.allCases) { pitch in
                    let selected = draft.selectedPitchCodes.contains(pitch.rawValue)
                    Button {
                        focusedField = nil
                        var codes = draft.selectedPitchCodes
                        if selected { codes.removeAll { $0 == pitch.rawValue } }
                        else { codes.append(pitch.rawValue) }
                        draft.pitchCodes = codes
                    } label: {
                        HStack(spacing: 8) {
                            MatchGrip(code: pitch.rawValue, hand: draft.throwingHand.rawValue)
                                .frame(width: 26, height: 32).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(pitch.label).font(.subheadline.bold())
                                Text("숙련 \(draft.initialValues.pitches[pitch.rawValue] ?? pitch.initialMastery, specifier: "%.1f")")
                                    .font(.caption).foregroundStyle(GameTheme.boardMuted)
                            }
                            Spacer(minLength: 0)
                            Text(selected ? "■" : "□").foregroundStyle(selected ? GameTheme.gold : GameTheme.boardMuted)
                                .accessibilityHidden(true)
                        }.frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                    }.buttonStyle(GameButtonStyle(secondary: !selected, onBoard: true))
                        .overlay(Rectangle().strokeBorder(selected ? GameTheme.gold : GameTheme.boardLine, lineWidth: 2).allowsHitTesting(false))
                        .disabled(selected ? draft.selectedPitchCodes.count <= 3 : draft.selectedPitchCodes.count >= 5)
                        .accessibilityLabel(pitch.label + " · 초기 숙련 " + String(format: "%.1f", draft.initialValues.pitches[pitch.rawValue] ?? pitch.initialMastery))
                        .accessibilityValue(selected ? "선택" : "미선택")
                        .accessibilityHint(selected && draft.selectedPitchCodes.count <= 3 ? "최소 3개 유지 · 새 구종 추가 후 제외 가능" : !selected && draft.selectedPitchCodes.count >= 5 ? "5개 선택됨 · 다른 구종 제외 후 추가 가능" : "구종 선택 변경")
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("creationPitch-" + pitch.rawValue)
                }
            }
            let actions = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(spacing: 8)) : AnyLayout(HStackLayout(spacing: 8))
            actions {
                Button("추천 구성") { focusedField = nil; draft.pitchCodes = nil }
                    .buttonStyle(GameButtonStyle(secondary: true, onBoard: true)).accessibilityIdentifier("creationPitchRecommended")
                Button("무작위 3~5개") {
                    focusedField = nil
                    draft.pitchCodes = Array(PitchType.allCases.shuffled().prefix(Int.random(in: 3...5))).map(\.rawValue)
                }.buttonStyle(GameButtonStyle(secondary: true, onBoard: true)).accessibilityIdentifier("creationPitchRandom")
            }
        }
    }

    private func creationStat(name: String, value: Double) -> some View {
        CreationStatRow(name: name, value: value, accent: draft.isCustom ? GameTheme.gold : archetypeAccent(draft.selectedArchetype))
    }
    private func archetypeAccent(_ type: PlayerArchetype) -> Color {
        switch type {
        case .contact: Color(hex: 0x74c8aa)
        case .slugger: Color(hex: 0xefaa78)
        case .onBase: Color(hex: 0x86c8df)
        case .stuff: Color(hex: 0xbaa5de)
        case .control: Color(hex: 0x83cbb8)
        case .endurance: Color(hex: 0xedc671)
        }
    }
    private func archetypeChoice(_ type: PlayerArchetype, action: @escaping () -> Void) -> some View {
        let values = type.values
        let detail: String
        switch type {
        case .contact: detail = "컨택 \(Int(values.contact)) · 스피드 \(Int(values.speed))"
        case .slugger: detail = "파워 \(Int(values.power)) · 송구 \(Int(values.arm))"
        case .onBase: detail = "선구안 \(Int(values.discipline)) · 스피드 \(Int(values.speed))"
        case .stuff: detail = "구위 \(Int(values.stuff ?? 0)) · 구속 능력 \(Int(values.velocity ?? 0))"
        case .control: detail = "제구 \(Int(values.control ?? 0)) · 구위 \(Int(values.stuff ?? 0))"
        case .endurance: detail = "지구력 \(Int(values.stamina ?? 0)) · 제구 \(Int(values.control ?? 0))"
        }
        return typeChoice(title: type.label, detail: detail, kind: type.rawValue, accent: archetypeAccent(type),
            selected: !draft.isCustom && draft.selectedArchetype == type, identifier: "archetype-" + type.rawValue, action: action)
    }
    private func typeChoice(title: String, detail: String, kind: String, accent: Color,
                            selected: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 9) {
                    CreationTypeMark(kind: kind, color: accent).frame(width: 28, height: 28).accessibilityHidden(true)
                    Text(title).font(.headline).fixedSize(horizontal: false, vertical: true)
                }
                Text(detail).font(.caption).foregroundStyle(GameTheme.boardMuted)
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, minHeight: 68, alignment: .leading).padding(.vertical, 4)
        }.buttonStyle(GameButtonStyle(secondary: !selected, onBoard: true))
            .overlay(Rectangle().strokeBorder(selected ? GameTheme.gold : GameTheme.boardLine, lineWidth: 2).allowsHitTesting(false))
            .accessibilityLabel(title).accessibilityValue(detail).accessibilityIdentifier(identifier)
            .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func choice(_ title: String, selected: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(selected ? "■" : "□").foregroundStyle(selected ? GameTheme.gold : GameTheme.boardMuted).accessibilityHidden(true)
                Text(title).fixedSize(horizontal: false, vertical: true)
            }.padding(.vertical, 6)
        }
        .buttonStyle(GameButtonStyle(secondary: !selected, onBoard: true))
        .overlay(Rectangle().strokeBorder(selected ? GameTheme.gold : GameTheme.boardLine, lineWidth: 2).allowsHitTesting(false))
        .accessibilityLabel(title).accessibilityIdentifier(id)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func palette(_ title: String, selection: Binding<Int>, colors: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(title) · \(selection.wrappedValue + 1)").font(.caption).foregroundStyle(GameTheme.boardMuted)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: dynamicTypeSize.isAccessibilitySize ? 3 : 6), spacing: 6) {
                ForEach(colors.indices, id: \.self) { index in
                    Button { selection.wrappedValue = index } label: {
                        VStack(spacing: 3) {
                            Rectangle().fill(Color(hex: colors[index])).frame(height: 24)
                            Text("\(index + 1)").font(.caption.monospaced().bold()).foregroundStyle(GameTheme.boardInk)
                        }.padding(5).frame(minHeight: 48)
                            .background(GameTheme.board)
                            .overlay(Rectangle().strokeBorder(selection.wrappedValue == index ? GameTheme.gold : GameTheme.boardLine, lineWidth: selection.wrappedValue == index ? 3 : 1))
                    }.buttonStyle(.plain).accessibilityLabel("\(title) \(index + 1)")
                        .accessibilityAddTraits(selection.wrappedValue == index ? .isSelected : [])
                }
            }
        }
    }

    private func allocationRow(_ kind: TrainingKind) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6)) : AnyLayout(HStackLayout(spacing: 8))
        return layout {
            HStack {
                Text(kind.label).font(.subheadline)
                Spacer(minLength: 4)
                Text("\(draft.allocation?.points[kind] ?? 0)").font(.headline.monospaced()).foregroundStyle(GameTheme.gold)
                    .accessibilityIdentifier("allocationValue-" + kind.rawValue)
            }
            HStack(spacing: 6) {
                ForEach([-1, 1], id: \.self) { amount in
                    Button(amount < 0 ? "−" : "+") { draft.allocation?.adjust(kind, by: amount) }
                        .buttonStyle(MatchPixelButtonStyle())
                        .frame(width: dynamicTypeSize.isAccessibilitySize ? nil : 44)
                        .disabled(draft.allocation?.canAdjust(kind, by: amount) != true)
                        .accessibilityLabel(kind.label + (amount < 0 ? " 1점 감소" : " 1점 증가"))
                        .accessibilityIdentifier("allocation-" + kind.rawValue + (amount < 0 ? "-minus" : "-plus"))
                }
            }
        }.padding(8).background(GameTheme.board)
    }
    private func finishRegistration() {
        guard let id = registeredID else { return }
        registeredID = nil; registrationTask?.cancel(); registrationTask = nil
        onSaving(false); onCreated(id)
    }
    private func save() {
        guard registeredID == nil else { return }
        focusedField = nil; onSaving(true)
        do {
            let player = try CareerStore.create(draft, schools: schools, in: context)
            errorMessage = nil; registeredID = player.id
            registrationTask = Task { @MainActor in
                do { try await Task.sleep(for: .milliseconds(reduced ? 100 : 900)) } catch { return }
                guard !Task.isCancelled else { return }
                finishRegistration()
            }
        } catch { onSaving(false); errorMessage = error.localizedDescription }
    }

}

private struct SchoolPicker: View {
    let schools: [School]
    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    @State private var region: String? = nil
    @FocusState private var searchFocused: Bool
    private var filtered: [School] {
        SchoolCatalog.filtered(schools, query: search, region: region)
    }
    var body: some View {
        NavigationStack {
            VStack(spacing: 12) {
                HStack {
                    TextField("학교 또는 지역 검색", text: $search, prompt: Text("학교 또는 지역 검색").foregroundStyle(GameTheme.boardMuted))
                        .focused($searchFocused).submitLabel(.search)
                        .onSubmit { searchFocused = false }
                        .accessibilityLabel("학교 또는 지역 검색").accessibilityIdentifier("schoolSearch")
                    if !search.isEmpty {
                        Button("지우기") { search = "" }.frame(minWidth: 44, minHeight: 44).accessibilityLabel("검색 지우기")
                    }
                }.padding(12).background(GameTheme.boardPanel)
                    .overlay(Rectangle().strokeBorder(GameTheme.boardLine, lineWidth: 1))
                    .padding(.horizontal, 16)
                HStack {
                    Menu {
                        Button("전체 지역") { region = nil }
                        ForEach(Array(Set(schools.map(\.region))).sorted(), id: \.self) { value in Button(value) { region = value } }
                    } label: { Text(region ?? "지역").frame(minHeight: 44) }.accessibilityLabel(region ?? "전체 지역").accessibilityIdentifier("schoolRegion")
                    Spacer()
                    Button("무작위") {
                        guard let school = filtered.randomElement() else { return }
                        selected = school.id; dismiss()
                    }.disabled(filtered.isEmpty).frame(minHeight: 44).accessibilityLabel("검색 범위에서 무작위 선택").accessibilityIdentifier("randomFilteredSchool")
                }.padding(.horizontal, 16)
                Text("검색 \(filtered.count)곳")
                    .font(.caption).foregroundStyle(GameTheme.boardMuted)
                DisclosureGroup("학교 라벨 기준") {
                    Text("가상 세계관 · 명문/강팀은 초기 설정, 2025 우승은 시작 전년도 이력입니다. 경기·성장 보너스는 없습니다.")
                        .managementFont(.helper).foregroundStyle(GameTheme.boardMuted)
                }.font(.caption).padding(.horizontal, 16)
                List(filtered) { school in
                    Button { searchFocused = false; selected = school.id; dismiss() } label: {
                        HStack(spacing: 8) {
                            SchoolCrest(school: school).frame(width: 38, height: 42)
                            VStack(alignment: .leading, spacing: 6) {
                                Text(school.name).fontWeight(.bold).fixedSize(horizontal: false, vertical: true)
                                Text(school.locationLabel).font(.caption).foregroundStyle(GameTheme.boardMuted)
                                SchoolReputationLabels(school: school)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Text(selected == school.id ? "■" : "□").foregroundStyle(GameTheme.gold).accessibilityHidden(true)
                        }.frame(minHeight: 44).contentShape(Rectangle())
                    }.foregroundStyle(GameTheme.boardInk).accessibilityIdentifier(school.id)
                        .accessibilityAddTraits(selected == school.id ? .isSelected : [])
                        .listRowBackground(GameTheme.boardPanel).listRowSeparatorTint(GameTheme.boardLine)
                }.listStyle(.plain).padding(.horizontal, 16)
                    .scrollContentBackground(.hidden).scrollDismissesKeyboard(.interactively)
                    .overlay { if filtered.isEmpty { Text("검색 결과가 없습니다").foregroundStyle(GameTheme.boardMuted).accessibilityIdentifier("schoolSearchEmpty") } }
            }.padding(.top, 12).background(GameTheme.board).foregroundStyle(GameTheme.boardInk)
            .preferredColorScheme(.dark).tint(GameTheme.gold)
            .toolbarBackground(GameTheme.boardPanel, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
            .navigationTitle("소속 학교").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ManagementToolbarAction(title: "닫기", identifier: "closeSchoolPicker", placement: .cancellationAction) { searchFocused = false; dismiss() }
                if searchFocused {
                    ToolbarItem(placement: .topBarTrailing) { Button("검색 완료") { searchFocused = false }.foregroundStyle(GameTheme.gold) }
                }
            }
        }
    }
}

private struct CreationIdentityCard: View {
    let appearance: PlayerAppearance
    let role: PlayerRole
    let number: String
    let name: String
    let school: School?
    let position: String
    let typeLabel: String
    let points: Int
    let budget: Int
    var compact = false
    @Environment(\.dynamicTypeSize) private var type
    private var cleanName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            let layout = type.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 16))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
            layout {
                ManagementPortrait(appearance: appearance, role: role, number: Int(number) ?? 0)
                    .frame(width: compact ? 80 : type.isAccessibilitySize ? 128 : 96,
                           height: compact ? 88 : type.isAccessibilitySize ? 128 : 108)
                    .background(GameTheme.board).overlay(Rectangle().strokeBorder(GameTheme.boardLine, lineWidth: 1))
                VStack(alignment: .leading, spacing: 7) {
                    Text("MY FIRST SEASON").font(ManagementPixelFont.readable(.helper)).foregroundStyle(GameTheme.gold)
                    Text(cleanName.isEmpty ? "나의 첫 시즌" : cleanName)
                        .font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                    Text("#\(number.isEmpty ? "—" : number) · 16세 · \(role.label)")
                        .font(.subheadline.monospaced()).foregroundStyle(GameTheme.boardMuted)
                        .fixedSize(horizontal: false, vertical: true)
                    if !compact { Text(position).font(.subheadline).foregroundStyle(GameTheme.boardMuted) }
                    if let school {
                        HStack(spacing: 6) {
                            SchoolCrest(school: school).frame(width: 23, height: 26)
                            Text(school.name).font(.subheadline.bold()).fixedSize(horizontal: false, vertical: true)
                        }
                    } else { Text("학교 미선택").font(.subheadline).foregroundStyle(GameTheme.boardMuted) }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.padding(16)
            if !compact {
            Rectangle().fill(GameTheme.boardLine).frame(height: 1)
            let metadata = type.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
                : AnyLayout(HStackLayout(alignment: .top, spacing: 16))
            metadata {
                item("선수 유형", typeLabel)
                item("시작 능력", "\(points)/\(budget)점")
                item("첫 시즌", "고교 1학년")
            }.padding(14)
            }
        }.foregroundStyle(GameTheme.boardInk).frame(maxWidth: .infinity, alignment: .leading)
            .background(GameTheme.boardPanel).overlay(Rectangle().strokeBorder(GameTheme.boardLine, lineWidth: 1))
            .accessibilityElement(children: .combine)
    }
    private func item(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.caption).foregroundStyle(GameTheme.boardMuted)
            Text(value).font(.subheadline.bold()).fixedSize(horizontal: false, vertical: true)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct CreationTypeMark: View {
    let kind: String
    let color: Color
    private var rows: [String] {
        switch kind {
        case "contact": ["000010000", "011111110", "010010010", "010000010", "111010111", "010000010", "010010010", "011111110", "000010000"]
        case "slugger": ["000000110", "000001111", "000011110", "000111100", "001111000", "001110000", "011100000", "111000000", "010000000"]
        case "onBase": ["000000000", "000111000", "011111110", "110010011", "100111001", "110010011", "011111110", "000111000", "000000000"]
        case "stuff": ["000111000", "011000110", "010100010", "100010001", "100100001", "100010001", "010100010", "011000110", "000111000"]
        case "control": ["000010000", "000010000", "001111100", "001010100", "111101111", "001010100", "001111100", "000010000", "000010000"]
        case "endurance": ["000111000", "011111110", "010000010", "010111010", "010000010", "010111010", "010111010", "010000010", "011111110"]
        default: ["001100000", "111111111", "001100000", "000001100", "111111111", "000001100", "011000000", "111111111", "011000000"]
        }
    }
    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 9
            for (y, row) in rows.enumerated() {
                for (x, pixel) in row.enumerated() where pixel == "1" {
                    context.fill(Path(CGRect(x: CGFloat(x) * unit, y: CGFloat(y) * unit, width: unit, height: unit)), with: .color(color))
                }
            }
        }
    }
}

private struct CreationStatRow: View {
    let name: String
    let value: Double
    var accent: Color = GameTheme.growth
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                Spacer(minLength: 8)
                Text(value.formatted(.number.precision(.fractionLength(1)))).monospacedDigit().foregroundStyle(accent)
            }.font(.subheadline)
            GeometryReader { proxy in
                Rectangle().fill(GameTheme.board)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(accent).frame(width: proxy.size.width * min(100, max(0, value)) / 100)
                    }
            }.frame(height: dynamicTypeSize.isAccessibilitySize ? 8 : 5).accessibilityHidden(true)
        }.accessibilityElement(children: .combine)
    }
}

private struct CreationRegistrationOverlay: View {
    let appearance: PlayerAppearance
    let role: PlayerRole
    let number: Int
    let name: String
    let school: School?
    let position: String
    let typeLabel: String
    let points: Int
    let budget: Int
    let reduced: Bool
    private let started = Date()
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                GameTheme.board.opacity(0.97).ignoresSafeArea()
                ScrollView {
                    GamePanel(title: "선수 등록", onBoard: true) {
                        CreationIdentityCard(appearance: appearance, role: role, number: String(number), name: name,
                            school: school, position: position, typeLabel: typeLabel, points: points, budget: budget)
                        Text("선수 정보 저장 완료").font(.headline).foregroundStyle(GameTheme.growth)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("첫 시즌을 준비하고 있습니다").font(.subheadline).fixedSize(horizontal: false, vertical: true)
                        TimelineView(.animation(minimumInterval: 0.15, paused: reduced)) { timeline in
                            HStack(spacing: 6) {
                                ForEach(0..<6) { index in
                                    Rectangle().fill(reduced || index <= Int(timeline.date.timeIntervalSince(started) / 0.15) % 6 ? GameTheme.gold : GameTheme.boardLine)
                                        .frame(height: 8)
                                }
                            }.accessibilityHidden(true)
                        }
                    }.padding(24).frame(minHeight: geometry.size.height)
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("creationRegistered")
    }
}

private struct CreationStepButton: ButtonStyle {
    let selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(selected ? GameTheme.navy : GameTheme.boardInk)
            .background(selected ? GameTheme.gold : GameTheme.boardPanel)
            .overlay(ManagementStepFrame().strokeBorder(selected ? GameTheme.gold : GameTheme.boardLine, lineWidth: 2))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
