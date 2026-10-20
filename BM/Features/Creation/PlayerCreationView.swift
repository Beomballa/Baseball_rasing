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
    @State private var registeredID: UUID?
    @State private var registrationTask: Task<Void, Never>?
    @State private var draft = PlayerDraft()
    @State private var errorMessage: String?
    @State private var showSchools = false
    @FocusState private var focusedField: Field?
    private enum Field { case name, number }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
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
                }
                GamePanel(title: "02  소속 학교", onBoard: true) {
                    Button { focusedField = nil; showSchools = true } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(selectedSchool?.name ?? "학교 선택")
                                    .fontWeight(.bold)
                                Text("검증된 고교 50곳").font(.caption)
                            }
                            if !dynamicTypeSize.isAccessibilitySize { Spacer(); Text("선택 ›") }
                        }.frame(minHeight: 48)
                    }.buttonStyle(GameButtonStyle(secondary: true, onBoard: true)).accessibilityIdentifier("schoolPicker")
                    Button("학교 무작위 선택") { draft.schoolID = schools.randomElement()?.id ?? "" }
                        .buttonStyle(GameButtonStyle(secondary: true, onBoard: true)).accessibilityIdentifier("randomSchool")
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
                    Text("\(draft.isCustom ? "사용자 지정" : draft.selectedArchetype.label) · \(draft.isCustom ? "총 \(draft.role == .batter ? 388 : 459) 포인트" : draft.role == .batter ? "타격·주루·수비·멘탈 합계 388" : "투구 원본 4종 합계 224")")
                        .font(.caption.bold()).accessibilityIdentifier("archetypePreviewTitle")
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
                        Text(draft.role == .batter ? "유형은 시작 능력치만 바꿉니다. 성장 배율과 상한은 같습니다." : "구속 능력은 0~100점 기준 · 초기 구종 숙련 62 / 55 / 42 / 35")
                            .font(.caption).foregroundStyle(GameTheme.boardMuted)
                    }
                }
                GamePanel(title: "04  도트 외형", onBoard: true) {
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

                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(Color(hex: 0xffb4a8)).font(.subheadline)
                        .accessibilityIdentifier("creationError")
                }
                Button("커리어 시작", action: save).buttonStyle(GameButtonStyle(onBoard: true))
                    .disabled(draft.isCustom && draft.allocation?.isValid != true)
                    .accessibilityIdentifier("createPlayer")
                Text("이 기기에 저장됩니다 · 역할별 선수 1명\n학교명은 참조 정보이며 공식 로고·유니폼은 사용하지 않습니다.")
                    .font(.caption).foregroundStyle(GameTheme.boardMuted).multilineTextAlignment(.center)
            }.padding(16)
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
        .onChange(of: draft.role) { _, role in draft.archetype = .initial(for: role); draft.isCustom = false; draft.allocation = nil }
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

    private var selectedSchool: School? { schools.first { $0.id == draft.schoolID } }
    private var choiceColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: dynamicTypeSize.isAccessibilitySize ? 1 : 2)
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
    @FocusState private var searchFocused: Bool
    private var filtered: [School] {
        search.isEmpty ? schools : schools.filter { $0.name.contains(search) || $0.region.contains(search) }
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
                        Button("지우기") { search = "" }.accessibilityLabel("검색 지우기")
                    }
                }.padding(12).background(GameTheme.boardPanel)
                    .overlay(Rectangle().strokeBorder(GameTheme.boardLine, lineWidth: 1))
                    .padding(.horizontal, 16)
                Text("고교 \(filtered.count)곳 · 학교를 선택하세요")
                    .font(.caption).foregroundStyle(GameTheme.boardMuted)
                List(filtered) { school in
                    Button { searchFocused = false; selected = school.id; dismiss() } label: {
                        HStack(spacing: 8) {
                            Text(school.name).fixedSize(horizontal: false, vertical: true)
                            Spacer(minLength: 8)
                            Text(school.region).font(.caption).foregroundStyle(GameTheme.boardMuted)
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
                ToolbarItem(placement: .cancellationAction) { Button("닫기") { searchFocused = false; dismiss() }.foregroundStyle(GameTheme.gold) }
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
