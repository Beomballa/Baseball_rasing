import SwiftUI

struct CreationAppearanceEditor: View {
    @Binding var draft: PlayerDraft
    let school: School?
    let previous: () -> Void
    let next: () -> Void
    @Environment(\.dynamicTypeSize) private var type
    @State private var tab = Tab.hair
    @State private var cap = false
    private enum Tab: String, CaseIterable {
        case hair, face, expression, colors
        var label: String { switch self { case .hair: "헤어"; case .face: "얼굴"; case .expression: "표정"; case .colors: "색상" } }
    }
    private let hairOrder = [0, 3, 4, 1, 6, 7, 2, 5]
    private var columns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: type.isAccessibilitySize ? 2 : 4)
    }
    var body: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 0) {
                    stage(height: min(240, max(190, geometry.size.width * 0.58)))
                    VStack(alignment: .leading, spacing: 16) {
                        portraitPresets
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: type.isAccessibilitySize ? 2 : 4), spacing: 4) {
                            ForEach(Tab.allCases, id: \.self) { item in
                                Button { tab = item } label: {
                                    Text(item.label).font(ManagementPixelFont.readable(.label))
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                }.buttonStyle(CreationPaperChoice(selected: tab == item, filled: true))
                                    .accessibilityAddTraits(tab == item ? .isSelected : [])
                                    .accessibilityIdentifier("appearanceTab-" + item.rawValue)
                            }
                        }
                        switch tab {
                        case .hair:
                            heading("머리 모양", detail: "8종")
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(hairOrder, id: \.self) { index in
                                    thumbnail(PlayerAppearance.hairNames[index], id: "hairStyle-\(index)", selected: draft.appearance.hairStyle == index,
                                        appearance: changed { $0.hairStyle = index }, cap: false) { draft.appearance.hairStyle = index }
                                }
                            }
                            colors("머리색", values: PlayerAppearance.hairColors, selection: $draft.appearance.hair, prefix: "hair")
                        case .face:
                            heading("눈매", detail: "4종")
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(PlayerAppearance.eyeNames.indices, id: \.self) { index in
                                    thumbnail(PlayerAppearance.eyeNames[index], id: "eyeShape-\(index)", selected: draft.appearance.eyeIndex == index,
                                        appearance: changed { $0.eyeShape = index }, cap: false) { draft.appearance.eyeShape = index }
                                }
                            }
                            heading("눈썹", detail: "4종")
                            LazyVGrid(columns: columns, spacing: 10) {
                                ForEach(PlayerAppearance.browNames.indices, id: \.self) { index in
                                    thumbnail(PlayerAppearance.browNames[index], id: "browShape-\(index)", selected: draft.appearance.browIndex == index,
                                        appearance: changed { $0.browShape = index }, cap: false) { draft.appearance.browShape = index }
                                }
                            }
                        case .expression:
                            heading("기본 표정", detail: "6종")
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: type.isAccessibilitySize ? 2 : 3), spacing: 10) {
                                ForEach(PlayerAppearance.expressionNames.indices, id: \.self) { index in
                                    thumbnail(PlayerAppearance.expressionNames[index], id: "expression-\(index)", selected: draft.appearance.expression == index,
                                        appearance: changed { $0.expression = index }, cap: false) { draft.appearance.expression = index }
                                }
                            }
                        case .colors:
                            colors("피부색", values: PlayerAppearance.skinColors, selection: $draft.appearance.skin, prefix: "skin")
                            colors("머리색", values: PlayerAppearance.hairColors, selection: $draft.appearance.hair, prefix: "hair")
                            heading("학교 유니폼", detail: "홈")
                            if let school, SchoolCreationKit.find(school.id) != nil {
                                Image("CreationKit-" + school.id).resizable().interpolation(.none).scaledToFit()
                                    .frame(maxHeight: 160).accessibilityLabel(school.name + " 홈 유니폼과 모자 앞뒤 도안")
                                HStack(spacing: 8) {
                                    SchoolCrest(school: school).frame(width: 32, height: 32)
                                    Text(school.name).managementFont(.label)
                                }.accessibilityIdentifier("appearanceSchoolKit")
                                Text("학교를 바꾸면 미리보기의 복장도 함께 바뀝니다.").managementFont(.helper)
                            } else {
                                Text("정보 단계에서 학교를 선택하세요.").managementFont(.body)
                            }
                        }
                    }
                    .padding(16).foregroundStyle(GameTheme.navy).frame(maxWidth: .infinity, alignment: .leading)
                    .background(GameTheme.boardInk)
                }
            }.accessibilityIdentifier("appearanceEditorScroll")
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    HStack(spacing: 12) {
                        Button(type.isAccessibilitySize ? "이전" : "이전 단계", action: previous)
                            .accessibilityLabel("이전 단계").buttonStyle(ManagementButtonStyle(variant: .secondary))
                        Button(type.isAccessibilitySize ? "다음" : "이 모습으로 계속", action: next)
                            .accessibilityLabel("이 모습으로 계속").buttonStyle(ManagementButtonStyle())
                    }.padding(12).background(GameTheme.board)
                }
        }.onAppear { updateSchool() }
            .onChange(of: school?.id) { _, _ in updateSchool() }
    }
    private func updateSchool() {
        draft.appearance.creationVersion = 1
        draft.appearance.schoolKitID = school.flatMap { SchoolCreationKit.find($0.id) != nil ? $0.id : nil }
    }
    private func changed(_ change: (inout PlayerAppearance) -> Void) -> PlayerAppearance {
        var value = draft.appearance; change(&value); return value
    }
    private var portraitPresets: some View {
        VStack(alignment: .leading, spacing: 12) {
            heading("얼굴 스타일", detail: "4가지 시작 모습")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
                ForEach(0..<4) { index in
                    let look = preset(index)
                    Button { draft.appearance = look } label: {
                        VStack(spacing: 7) {
                            ManagementPortrait(appearance: look, role: draft.role, number: Int(draft.jerseyNumber) ?? 0)
                                .frame(height: type.isAccessibilitySize ? 108 : 90)
                            Text(["얼굴 A · 스포츠컷", "얼굴 B · 옆가르마", "얼굴 C · 크루컷", "얼굴 D · 웨이브"][index])
                                .font(ManagementPixelFont.readable(.helper)).fixedSize(horizontal: false, vertical: true)
                        }.frame(maxWidth: .infinity, minHeight: 120).padding(8)
                    }.buttonStyle(CreationPaperChoice(selected: draft.appearance == look))
                        .accessibilityLabel("얼굴 스타일 " + ["A", "B", "C", "D"][index])
                        .accessibilityAddTraits(draft.appearance == look ? .isSelected : [])
                        .accessibilityIdentifier("appearancePreset-\(index)")
                }
            }
            Text("스타일을 고른 뒤 헤어·눈매·눈썹·표정·색상을 각각 바꿀 수 있습니다.")
                .managementFont(.helper).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func preset(_ index: Int) -> PlayerAppearance {
        var value = draft.appearance
        value.skin = index == 2 ? 2 : 0; value.hair = 0
        value.hairStyle = [0, 1, 3, 7][index]
        value.eyeShape = [0, 0, 2, 1][index]
        value.browShape = [0, 1, 1, 3][index]
        value.expression = index < 2 ? 2 : 0
        return value
    }
    private func stage(height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            let layout = type.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 14))
                : AnyLayout(HStackLayout(alignment: .center, spacing: 16))
            layout {
                ManagementPortrait(appearance: draft.appearance, role: draft.role,
                    number: Int(draft.jerseyNumber) ?? 0, cap: cap)
                    .frame(width: type.isAccessibilitySize ? 144 : 128, height: min(168, height * 0.74))
                    .background(GameTheme.board)
                    .overlay(Rectangle().strokeBorder(GameTheme.boardLine, lineWidth: 1))
                VStack(alignment: .leading, spacing: 8) {
                    Text("MY PLAYER").font(ManagementPixelFont.readable(.helper)).foregroundStyle(GameTheme.gold)
                    Text((draft.name.isEmpty ? "나의 선수" : draft.name) + " · #" + draft.jerseyNumber)
                        .font(.headline).fixedSize(horizontal: false, vertical: true)
                    Text((school?.name ?? "학교 미선택") + " · " + draft.role.label)
                        .font(.subheadline).foregroundStyle(GameTheme.boardMuted).fixedSize(horizontal: false, vertical: true)
                    Text("\(PlayerAppearance.hairNames[draft.appearance.hairStyle]) · \(PlayerAppearance.expressionNames[draft.appearance.expression])")
                        .font(.caption).foregroundStyle(GameTheme.boardMuted).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.accessibilityElement(children: .combine).accessibilityIdentifier("creationMotionPreview")
                .accessibilityValue("\(PlayerAppearance.hairNames[draft.appearance.hairStyle]) · \(PlayerAppearance.expressionNames[draft.appearance.expression]) · \(PlayerAppearance.eyeNames[draft.appearance.eyeIndex]) · \(PlayerAppearance.browNames[draft.appearance.browIndex])")
            Button { cap.toggle() } label: {
                HStack(spacing: 8) { Text(cap ? "■" : "□"); Text("모자 보기"); Spacer() }
                    .font(.subheadline).frame(minHeight: 44).padding(.horizontal, 10)
                    .overlay(Rectangle().strokeBorder(GameTheme.boardLine, lineWidth: 1))
            }.buttonStyle(.plain).accessibilityLabel("모자 보기").accessibilityValue(cap ? "착용" : "벗음")
                .accessibilityIdentifier("appearanceCap")
        }.padding(16).foregroundStyle(GameTheme.boardInk).frame(maxWidth: .infinity, alignment: .leading)
            .background(GameTheme.boardPanel)
    }
    private func heading(_ title: String, detail: String) -> some View {
        HStack { Text(title).font(ManagementPixelFont.readable(.sectionTitle)); Spacer(); Text(detail).managementFont(.helper) }
    }
    private func thumbnail(_ label: String, id: String, selected: Bool, appearance: PlayerAppearance, cap: Bool,
                           action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                ManagementPortrait(appearance: appearance, role: draft.role, number: Int(draft.jerseyNumber) ?? 0, cap: cap).frame(height: type.isAccessibilitySize ? 96 : 80)
                Text(label).font(ManagementPixelFont.readable(.helper)).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity).padding(4)
                .overlay(alignment: .topTrailing) {
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(GameTheme.navy, GameTheme.gold).padding(3) }
                }
        }.buttonStyle(CreationPaperChoice(selected: selected)).accessibilityLabel(label)
            .accessibilityAddTraits(selected ? .isSelected : []).accessibilityIdentifier(id)
    }
    private func colors(_ name: String, values: [Int], selection: Binding<Int>, prefix: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            heading(name, detail: "6색")
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: type.isAccessibilitySize ? 3 : 6), spacing: 8) {
                ForEach(values.indices, id: \.self) { index in
                    Button { selection.wrappedValue = index } label: {
                        Color(hex: values[index]).frame(minHeight: 44)
                            .overlay { if selection.wrappedValue == index { Image(systemName: "checkmark.circle.fill").foregroundStyle(GameTheme.navy, GameTheme.gold) } }
                    }.buttonStyle(CreationPaperChoice(selected: selection.wrappedValue == index))
                        .accessibilityLabel(name + " \(index + 1)")
                        .accessibilityAddTraits(selection.wrappedValue == index ? .isSelected : [])
                        .accessibilityIdentifier("appearanceColor-\(prefix)-\(index)")
                }
            }
        }
    }
}

private struct CreationPaperChoice: ButtonStyle {
    let selected: Bool
    var filled = false
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(GameTheme.navy)
            .contentShape(Rectangle())
            .background(selected && (filled || configuration.isPressed) ? GameTheme.gold : GameTheme.boardInk)
            .overlay(ManagementStepFrame().strokeBorder(selected ? GameTheme.gold : GameTheme.muted, lineWidth: selected ? 3 : 1))
            .opacity(configuration.isPressed ? 0.75 : 1)
    }
}
