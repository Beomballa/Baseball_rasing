import SwiftUI
import SwiftData

struct PlayerCreationView: View {
    let schools: [School]
    let availableRoles: [PlayerRole]
    let onCreated: (UUID) -> Void
    @Environment(\.modelContext) private var context
    @State private var draft = PlayerDraft()
    @State private var errorMessage: String?
    @State private var showSchools = false
    @FocusState private var focusedField: Field?
    private enum Field { case name, number }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    PixelPlayer(appearance: draft.appearance).frame(width: 72, height: 96)
                    VStack(alignment: .leading, spacing: 8) {
                        Text("나의 첫 시즌").font(.title2.bold())
                        Text("16세 · 고1에서 시작").font(.subheadline).foregroundStyle(GameTheme.muted)
                        Text("선수 생성").font(.caption.monospaced().bold()).foregroundStyle(GameTheme.green)
                    }
                    Spacer()
                }.padding(16).background(GameTheme.gold.opacity(0.25))

                GamePanel(title: "01  선수 정보") {
                    TextField("선수 이름 · 최대 12자", text: $draft.name)
                        .textContentType(.name).focused($focusedField, equals: .name)
                        .accessibilityIdentifier("playerName")
                        .padding(12).background(GameTheme.paper)
                    HStack {
                        Text("등번호")
                        TextField("0~99", text: $draft.jerseyNumber)
                            .keyboardType(.numberPad).focused($focusedField, equals: .number)
                            .accessibilityIdentifier("jerseyNumber")
                            .multilineTextAlignment(.trailing).padding(12).background(GameTheme.paper)
                    }
                    Picker("역할", selection: $draft.role) {
                        ForEach(availableRoles) { Text($0.label).tag($0) }
                    }.pickerStyle(.segmented).accessibilityIdentifier("rolePicker")
                    if draft.role == .batter {
                        Picker("주 포지션", selection: $draft.position) {
                            ForEach(FieldPosition.allCases) { Text($0.label).tag($0) }
                        }.accessibilityIdentifier("positionPicker")
                    } else {
                        Picker("투구 손", selection: $draft.throwingHand) {
                            ForEach(ThrowingHand.allCases) { Text($0.label).tag($0) }
                        }.pickerStyle(.segmented).accessibilityIdentifier("throwingHandPicker")
                    }
                }
                GamePanel(title: "02  소속 학교") {
                    Button { focusedField = nil; showSchools = true } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(schools.first(where: { $0.id == draft.schoolID })?.name ?? "학교 선택")
                                    .fontWeight(.bold)
                                Text("검증된 고교 50곳").font(.caption)
                            }
                            Spacer(); Text("선택 ›")
                        }.frame(minHeight: 48)
                    }.accessibilityIdentifier("schoolPicker")
                    Button("학교 무작위 선택") { draft.schoolID = schools.randomElement()?.id ?? "" }
                        .buttonStyle(GameButtonStyle(secondary: true)).accessibilityIdentifier("randomSchool")
                }
                GamePanel(title: "03  선수 유형") {
                    HStack(spacing: 8) {
                        ForEach(PlayerArchetype.choices(for: draft.role)) { archetype in
                            Button(archetype.label) { draft.archetype = archetype }
                                .buttonStyle(GameButtonStyle(secondary: draft.selectedArchetype != archetype))
                                .accessibilityIdentifier("archetype-" + archetype.rawValue)
                                .accessibilityAddTraits(draft.selectedArchetype == archetype ? .isSelected : [])
                        }
                    }
                    Text("\(draft.selectedArchetype.label) · \(draft.role == .batter ? "타격·주루·수비·멘탈 합계 388" : "투구 원본 4종 합계 224")")
                        .font(.caption.bold()).accessibilityIdentifier("archetypePreviewTitle")
                    let values = draft.selectedArchetype.values
                    if draft.role == .batter {
                        StatRow(name: "컨택", value: values.contact)
                        StatRow(name: "파워", value: values.power)
                        StatRow(name: "선구안", value: values.discipline)
                    } else {
                        StatRow(name: "구속 능력", value: values.velocity ?? 0)
                        StatRow(name: "제구", value: values.control ?? 0)
                        StatRow(name: "구위", value: values.stuff ?? 0)
                        StatRow(name: "지구력", value: values.stamina ?? 0)
                    }
                    StatRow(name: "스피드", value: values.speed)
                    StatRow(name: "수비", value: values.defense)
                    StatRow(name: "송구", value: values.arm)
                    StatRow(name: "멘탈", value: values.mental)
                    Text(draft.role == .batter ? "유형은 시작 능력치만 바꿉니다. 성장 배율과 상한은 같습니다." : "구속 능력은 0~100점 기준 · 초기 구종 숙련 62 / 55 / 42 / 35")
                        .font(.caption).foregroundStyle(GameTheme.muted)
                }
                GamePanel(title: "04  도트 외형") {
                    palette("피부", selection: $draft.appearance.skin, colors: PlayerAppearance.skinColors)
                    palette("머리색", selection: $draft.appearance.hair, colors: PlayerAppearance.hairColors)
                    palette("유니폼", selection: $draft.appearance.kit, colors: PlayerAppearance.kitColors)
                    Picker("머리 모양", selection: $draft.appearance.hairStyle) {
                        Text("짧은 머리").tag(0); Text("옆가르마").tag(1); Text("곱슬머리").tag(2)
                    }
                    Picker("표정", selection: $draft.appearance.expression) {
                        Text("기본").tag(0); Text("집중").tag(1); Text("미소").tag(2)
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.red).font(.subheadline)
                        .accessibilityIdentifier("creationError")
                }
                Button("커리어 시작", action: save).buttonStyle(GameButtonStyle())
                    .accessibilityIdentifier("createPlayer")
                Text("이 기기에 저장됩니다 · 역할별 선수 1명\n학교명은 참조 정보이며 공식 로고·유니폼은 사용하지 않습니다.")
                    .font(.caption).foregroundStyle(GameTheme.muted).multilineTextAlignment(.center)
            }.padding(16)
        }
        .background(GameTheme.paper).foregroundStyle(GameTheme.navy)
        .navigationTitle("선수 생성").navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if focusedField != nil {
                ToolbarItem(placement: .topBarTrailing) { Button("입력 완료") { focusedField = nil } }
            }
        }
        .sheet(isPresented: $showSchools) {
            SchoolPicker(schools: schools, selected: $draft.schoolID)
        }
        .onAppear { if let role = availableRoles.first, !availableRoles.contains(draft.role) { draft.role = role } }
        .onChange(of: draft.role) { _, role in draft.archetype = .initial(for: role) }
    }

    private func palette(_ title: String, selection: Binding<Int>, colors: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.subheadline)
            HStack(spacing: 0) {
                ForEach(colors.indices, id: \.self) { index in
                    Button { selection.wrappedValue = index } label: {
                        Rectangle().fill(Color(hex: colors[index])).frame(width: 28, height: 28)
                            .overlay(Rectangle().strokeBorder(selection.wrappedValue == index ? GameTheme.gold : .clear, lineWidth: 4))
                            .frame(maxWidth: .infinity, minHeight: 44)
                    }.accessibilityLabel("\(title) \(index + 1)")
                        .accessibilityAddTraits(selection.wrappedValue == index ? .isSelected : [])
                }
            }
        }
    }

    private func save() {
        focusedField = nil
        do {
            let player = try CareerStore.create(draft, schools: schools, in: context)
            errorMessage = nil; onCreated(player.id)
        } catch { errorMessage = error.localizedDescription }
    }
}

private struct SchoolPicker: View {
    let schools: [School]
    @Binding var selected: String
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    private var filtered: [School] {
        search.isEmpty ? schools : schools.filter { $0.name.contains(search) || $0.region.contains(search) }
    }
    var body: some View {
        NavigationStack {
            List(filtered) { school in
                Button { selected = school.id; dismiss() } label: {
                    HStack {
                        Text(school.name); Spacer(); Text(school.region).foregroundStyle(.secondary)
                        if selected == school.id { Image(systemName: "checkmark").accessibilityLabel("선택됨") }
                    }.frame(minHeight: 44)
                }.accessibilityIdentifier(school.id)
            }
            .searchable(text: $search, prompt: "학교 또는 지역")
            .navigationTitle("소속 학교").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("닫기") { dismiss() } } }
        }
    }
}
