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
    @FocusState private var focusedField: Field?
    private enum Field { case name, number }
    private enum CreationSection: String, CaseIterable {
        case information, abilities, appearance, review
        var title: String {
            switch self { case .information: "1 정보"; case .abilities: "2 능력·구종"; case .appearance: "3 외형"; case .review: "4 확인" }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(spacing: ManagementTheme.Space.screen) {
                HStack(alignment: .center, spacing: 12) {
                    PixelPlayer(appearance: draft.appearance).frame(width: 48, height: 64)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("NEW CAREER · 16세 고1").font(.caption.monospaced().bold()).foregroundStyle(GameTheme.gold)
                        Text(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "나의 첫 시즌" : draft.name)
                            .font(.title3.bold()).fixedSize(horizontal: false, vertical: true)
                        Text("\(selectedSchool?.name ?? "학교 미선택") · \(draft.role.label)")
                            .font(.caption).foregroundStyle(GameTheme.boardMuted)
                        Text("#\(draft.jerseyNumber) · \(draft.role == .batter ? draft.position.label : draft.throwingHand.label)")
                            .font(.caption.monospaced().bold()).foregroundStyle(GameTheme.gold)
                    }
                    Spacer(minLength: 0)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(GameTheme.boardPanel)
                    .overlay(Rectangle().strokeBorder(GameTheme.boardLine, lineWidth: 2))
                    .accessibilityElement(children: .combine).accessibilityIdentifier("creationPreview")

                GamePanel(title: "01  선수 정보", onBoard: true) {
                    Text("선수 이름 · 1~12자").font(.caption).foregroundStyle(GameTheme.boardMuted)
                    TextField("선수 이름", text: $draft.name, prompt: Text("선수 이름").foregroundStyle(GameTheme.boardMuted))
                        .textContentType(.name).focused($focusedField, equals: .name)
                        .accessibilityLabel("선수 이름").accessibilityIdentifier("playerName")
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
                GamePanel(title: "02  소속 학교", onBoard: true) {
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
                GamePanel(title: "03  선수 유형", onBoard: true) {
                    LazyVGrid(columns: choiceColumns, spacing: 8) {
                        ForEach(PlayerArchetype.choices(for: draft.role)) { archetype in
                            choice(archetype.label, selected: !draft.isCustom && draft.selectedArchetype == archetype, id: "archetype-" + archetype.rawValue) {
                                draft.archetype = archetype; draft.isCustom = false
                            }
                        }
                        choice("사용자 지정", selected: draft.isCustom, id: "archetype-custom") {
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
                            CreationStatRow(name: "컨택", value: values.contact)
                            CreationStatRow(name: "파워", value: values.power)
                            CreationStatRow(name: "선구안", value: values.discipline)
                        } else {
                            CreationStatRow(name: "구속 능력", value: values.velocity ?? 0)
                            CreationStatRow(name: "제구", value: values.control ?? 0)
                            CreationStatRow(name: "구위", value: values.stuff ?? 0)
                            CreationStatRow(name: "지구력", value: values.stamina ?? 0)
                        }
                        CreationStatRow(name: "스피드", value: values.speed)
                        CreationStatRow(name: "수비", value: values.defense)
                        CreationStatRow(name: "송구", value: values.arm)
                        CreationStatRow(name: "멘탈", value: values.mental)
                        Text(draft.role == .batter ? "유형은 시작 능력치만 바꿉니다. 성장 배율과 상한은 같습니다." : "구속 능력은 0~100점 기준 · 초기 구종 숙련은 아래 구성에서 확인하세요.")
                            .font(.caption).foregroundStyle(GameTheme.boardMuted)
                    }
                }.id(CreationSection.abilities.rawValue)
                if draft.role == .pitcher { pitchSelection }
                GamePanel(title: draft.role == .pitcher ? "05  도트 외형" : "04  도트 외형", onBoard: true) {
                    if let number = Int(draft.jerseyNumber), (0...99).contains(number) {
                        DetailGamePortrait(role: draft.role, appearance: draft.appearance,
                                           number: number, hand: draft.throwingHand.rawValue)
                            .frame(height: 150).frame(maxWidth: .infinity).accessibilityHidden(true)
                    } else {
                        PixelPlayer(appearance: draft.appearance).frame(width: 48, height: 64).accessibilityHidden(true)
                        Text("등번호를 입력하면 경기 전신 도트를 확인할 수 있습니다.").managementFont(.helper)
                    }
                    Text("내 선수 미리보기 · " + (draft.role == .pitcher ? draft.throwingHand.label : draft.position.label))
                        .managementFont(.label).accessibilityIdentifier("creationMotionPreview")
                    Text("선택한 도트 외형·색상은 내 선수의 경기·연습에 적용됩니다. 학교 공식 유니폼이나 상대 팀 색상을 뜻하지 않습니다.")
                        .managementFont(.helper)
                    palette("피부", selection: $draft.appearance.skin, colors: PlayerAppearance.skinColors)
                    palette("머리색", selection: $draft.appearance.hair, colors: PlayerAppearance.hairColors)
                    palette("유니폼", selection: $draft.appearance.kit, colors: PlayerAppearance.kitColors)
                    Text("머리 모양").font(.caption).foregroundStyle(GameTheme.boardMuted)
                    LazyVGrid(columns: choiceColumns, spacing: 8) {
                        ForEach(Array(["짧은 머리", "옆가르마", "곱슬머리"].enumerated()), id: \.offset) { index, label in
                            choice(label, selected: draft.appearance.hairStyle == index, id: "hairStyle-\(index)") { draft.appearance.hairStyle = index }
                        }
                    }
                    Text("표정").font(.caption).foregroundStyle(GameTheme.boardMuted)
                    LazyVGrid(columns: choiceColumns, spacing: 8) {
                        ForEach(Array(["기본", "집중", "미소"].enumerated()), id: \.offset) { index, label in
                            choice(label, selected: draft.appearance.expression == index, id: "expression-\(index)") { draft.appearance.expression = index }
                        }
                    }
                    HStack(spacing: 12) {
                        PixelPlayer(appearance: draft.appearance).frame(width: 48, height: 64).accessibilityHidden(true)
                        Text("피부 \(draft.appearance.skin + 1) · 머리색 \(draft.appearance.hair + 1) · 유니폼 \(draft.appearance.kit + 1)")
                            .font(.caption).foregroundStyle(GameTheme.boardMuted)
                            .accessibilityIdentifier("appearanceSummary")
                    }

                }.id(CreationSection.appearance.rawValue)

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
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .top, spacing: 0) { creationNavigation(proxy) }
        }
        .background(GameTheme.board).foregroundStyle(GameTheme.boardInk)
        .tint(GameTheme.gold).preferredColorScheme(.dark)
        .toolbarBackground(GameTheme.boardPanel, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .navigationTitle("선수 생성").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if focusedField != nil {
                ToolbarItem(placement: .topBarTrailing) { Button("입력 완료") { focusedField = nil }.foregroundStyle(GameTheme.gold) }
            }
        }
        .sheet(isPresented: $showSchools) {
            SchoolPicker(schools: schools, selected: $draft.schoolID)
        }
        .onAppear { if let role = availableRoles.first, !availableRoles.contains(draft.role) { draft.role = role } }
        .onChange(of: draft.role) { _, role in draft.archetype = .initial(for: role); draft.isCustom = false; draft.allocation = nil; draft.pitchCodes = nil }
        .disabled(registeredID != nil).accessibilityHidden(registeredID != nil)
        .overlay {
            if registeredID != nil { CreationRegistrationOverlay(appearance: draft.appearance, name: draft.name, reduced: reduced) }
        }
        .navigationBarBackButtonHidden(registeredID != nil)
        .interactiveDismissDisabled(registeredID != nil)
        .onChange(of: scenePhase) { _, phase in if phase != .active { finishRegistration() } }
        .onDisappear { registrationTask?.cancel(); registrationTask = nil }
        .onChange(of: draft.name) { _, _ in errorMessage = nil }
        .onChange(of: draft.jerseyNumber) { _, _ in errorMessage = nil }
        .onChange(of: draft.schoolID) { _, _ in errorMessage = nil }
    }

    private func creationNavigation(_ proxy: ScrollViewProxy) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: dynamicTypeSize.isAccessibilitySize ? 2 : 4), spacing: 8) {
            ForEach(CreationSection.allCases, id: \.rawValue) { target in
                Button {
                    focusedField = nil; section = target
                    withAnimation(reduced ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo(target.rawValue, anchor: .top) }
                } label: {
                    Text(target.title).managementFont(.label).fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(GameButtonStyle(secondary: section != target, onBoard: true))
                    .accessibilityAddTraits(section == target ? .isSelected : [])
                    .accessibilityIdentifier("creationSection-" + target.rawValue)
            }
        }.padding(12).background(GameTheme.boardPanel)
    }
    private var registrationReview: some View {
        GamePanel(title: "등록 전 확인", onBoard: true) {
            Text(draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "이름 미입력" : draft.name)
                .managementFont(.sectionTitle)
            Text("#\(draft.jerseyNumber) · \(draft.role.label) · \(draft.role == .pitcher ? draft.throwingHand.label : draft.position.label)").managementFont(.body)
            if let selectedSchool {
                HStack(spacing: 10) {
                    SchoolCrest(school: selectedSchool).frame(width: 36, height: 40)
                    Text(selectedSchool.name).managementFont(.body)
                }
                SchoolReputationLabels(school: selectedSchool)
            } else { Text("학교 미선택").managementFont(.body) }
            Text("전체 능력 \(draft.assignedAbilityPoints) / \(draft.abilityBudget)점 · \(draft.isCustom ? "사용자 지정" : draft.selectedArchetype.label)").managementFont(.label)
                .accessibilityIdentifier("creationReviewBudget")
            if draft.role == .pitcher {
                Text("구종 \(draft.selectedPitchCodes.count)개 · " + draft.selectedPitchCodes.compactMap { PitchType(rawValue: $0)?.label }.joined(separator: " · "))
                    .managementFont(.body).accessibilityIdentifier("creationReviewPitches")
            }
            ForEach(PlayerRole.allCases) { role in
                let own = existingPlayers.filter { $0.role == role }
                Text("\(role.label) · 활성 \(own.filter { !$0.isRetired }.count)/1 · 보관 \(own.filter { $0.isRetired }.count)명")
                    .managementFont(.helper).accessibilityIdentifier("creationSlots-" + role.rawValue)
            }
            Text(registrationReadiness).managementFont(.body).foregroundStyle(GameTheme.gold)
                .accessibilityIdentifier("creationReadiness")
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
        GamePanel(title: "04  구종 구성", onBoard: true) {
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
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { searchFocused = false; dismiss() }.frame(minWidth: 44, minHeight: 44).foregroundStyle(GameTheme.gold) }
                if searchFocused {
                    ToolbarItem(placement: .topBarTrailing) { Button("검색 완료") { searchFocused = false }.foregroundStyle(GameTheme.gold) }
                }
            }
        }
    }
}

private struct CreationStatRow: View {
    let name: String
    let value: Double
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(name)
                Spacer(minLength: 8)
                Text(value.formatted(.number.precision(.fractionLength(1)))).monospacedDigit().foregroundStyle(GameTheme.growth)
            }.font(.subheadline)
            GeometryReader { proxy in
                Rectangle().fill(GameTheme.board)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(GameTheme.growth).frame(width: proxy.size.width * min(100, max(0, value)) / 100)
                    }
            }.frame(height: dynamicTypeSize.isAccessibilitySize ? 8 : 5).accessibilityHidden(true)
        }.accessibilityElement(children: .combine)
    }
}

private struct CreationRegistrationOverlay: View {
    let appearance: PlayerAppearance
    let name: String
    let reduced: Bool
    private let started = Date()
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                GameTheme.board.opacity(0.97).ignoresSafeArea()
                ScrollView {
                    GamePanel(title: "선수 등록", onBoard: true) {
                        PixelPlayer(appearance: appearance).frame(width: 48, height: 64).accessibilityHidden(true)
                        Text(name).font(.title2.bold()).fixedSize(horizontal: false, vertical: true)
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
