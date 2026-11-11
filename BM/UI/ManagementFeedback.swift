import SwiftUI
import UIKit

enum ManagementFeedbackKind {
    case information, confirmation, failure, success

    var label: String {
        switch self {
        case .information: "안내"
        case .confirmation: "결정 확인"
        case .failure: "처리 실패"
        case .success: "완료"
        }
    }

    fileprivate var border: Color {
        self == .failure ? Color(hex: 0x5f3a29) : Color(hex: 0x203c32)
    }

    fileprivate var trim: Color {
        self == .failure ? Color(hex: 0xb88555) : Color(hex: 0xbd9c54)
    }
}

private struct ManagementDialog<Actions: View, Message: View>: ViewModifier {
    let title: String
    @Binding var requested: Bool
    let kind: ManagementFeedbackKind
    let titleVisibility: Visibility
    let showsCancel: Bool
    let identifier: String
    let actions: () -> Actions
    let message: () -> Message

    @State private var presented = false
    @State private var selectedAction: (@MainActor () -> Void)?
    @AccessibilityFocusState private var titleFocused: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .onChange(of: requested, initial: true) { _, requested in
                if selectedAction == nil { setPresentation(requested) }
            }
            .fullScreenCover(isPresented: $presented, onDismiss: finish) {
                ZStack {
                    Color(hex: 0x071d19).opacity(0.8).ignoresSafeArea().accessibilityHidden(true)
                    ViewThatFits(in: .vertical) {
                        cardContent(scrollingDetails: false).fixedSize(horizontal: false, vertical: true)
                        cardContent(scrollingDetails: true)
                        ScrollView { cardContent(scrollingDetails: false) }
                    }
                    .frame(maxWidth: 420)
                    .background(Color(hex: 0xf4efda), in: ManagementStepFrame())
                    .overlay {
                        ManagementStepFrame().strokeBorder(kind.border, lineWidth: 3)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                    .overlay {
                        ManagementStepFrame().inset(by: 3).strokeBorder(kind.trim, lineWidth: 2)
                            .allowsHitTesting(false).accessibilityHidden(true)
                    }
                    .padding(16)
                    .accessibilityElement(children: .contain)
                    .accessibilityLabel(title)
                    .accessibilityAddTraits(.isModal)
                    .accessibilityIdentifier(identifier)
                    .accessibilityAction(.escape) { select {} }
                }
                .presentationBackground(.clear)
                .interactiveDismissDisabled()
                .task {
                    await Task.yield()
                    titleFocused = true
                }
            }
    }

    private func cardContent(scrollingDetails: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            if scrollingDetails {
                ScrollView { details }
                    .frame(minHeight: ManagementTheme.Control.hit)
                    .accessibilityIdentifier("managementDialogDetails")
            } else {
                details
            }
            actionButtons
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(Color(hex: 0x2b4638))
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(kind.label)
                .font(ManagementPixelFont.readable(.helper))
                .foregroundStyle(kind.border)
            if titleVisibility != .hidden {
                Text(title)
                    .font(ManagementPixelFont.readable(.screenTitle))
                    .accessibilityAddTraits(.isHeader)
                    .accessibilityFocused($titleFocused)
            }
            message()
                .managementFont(.body)
                .foregroundStyle(Color(hex: 0x3e5448))
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var actionButtons: some View {
        VStack(spacing: 8) {
            actions()
                .buttonStyle(ManagementDialogActionStyle(select: select))
            if showsCancel {
                Button("취소", role: .cancel) { select {} }
                    .buttonStyle(ManagementButtonStyle(variant: .paper))
                    .keyboardShortcut(.cancelAction)
            }
        }
        .padding(.top, 4)
        .disabled(selectedAction != nil)
    }

    private func select(_ action: @escaping @MainActor () -> Void) {
        guard presented, requested, selectedAction == nil else { return }
        selectedAction = action
        setPresentation(false)
    }

    private func finish() {
        let action = selectedAction
        selectedAction = nil
        guard requested else { return }
        if kind == .failure {
            // A synchronous retry may report a new failure before the binding is observed again.
            requested = false
            action?()
            if requested { setPresentation(true) }
            return
        }
        // The command can be stored in the source binding. Execute while it remains valid.
        action?()
        if requested { requested = false }
    }

    private func setPresentation(_ presented: Bool) {
        var transaction = Transaction()
        transaction.disablesAnimations = reduceMotion
        withTransaction(transaction) { self.presented = presented }
    }
}

private struct ManagementDialogActionStyle: PrimitiveButtonStyle {
    let select: (@escaping @MainActor () -> Void) -> Void

    func makeBody(configuration: Configuration) -> some View {
        let button = Button(role: configuration.role) {
            select { configuration.trigger() }
        } label: {
            configuration.label
        }
        if configuration.role == .cancel {
            button.buttonStyle(ManagementButtonStyle(variant: .paper)).keyboardShortcut(.cancelAction)
        } else {
            button.buttonStyle(ManagementButtonStyle())
        }
    }
}

struct ManagementFeedbackBanner: View {
    let message: String
    var kind: ManagementFeedbackKind = .success

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(kind.label).font(ManagementPixelFont.readable(.helper)).foregroundStyle(kind.trim)
            Text(message).managementFont(.label).fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: 420, alignment: .leading)
        .foregroundStyle(GameTheme.boardInk)
        .background(kind.border, in: ManagementStepFrame())
        .overlay {
            ManagementStepFrame().strokeBorder(kind.trim, lineWidth: 2)
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("managementFeedbackBanner")
    }
}

extension View {
    func managementAlert<Actions: View, Message: View>(
        _ title: String, isPresented: Binding<Bool>, kind: ManagementFeedbackKind = .information,
        identifier: String = "managementDialog", @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder message: @escaping () -> Message
    ) -> some View {
        modifier(ManagementDialog(title: title, requested: isPresented, kind: kind, titleVisibility: .visible,
                                  showsCancel: false, identifier: identifier, actions: actions, message: message))
    }

    func managementAlert<Actions: View>(
        _ title: String, isPresented: Binding<Bool>, kind: ManagementFeedbackKind = .information,
        identifier: String = "managementDialog", @ViewBuilder actions: @escaping () -> Actions
    ) -> some View {
        managementAlert(title, isPresented: isPresented, kind: kind, identifier: identifier, actions: actions) { EmptyView() }
    }

    func managementConfirmationDialog<Actions: View, Message: View>(
        _ title: String, isPresented: Binding<Bool>, titleVisibility: Visibility = .visible,
        showsCancel: Bool = true, identifier: String = "managementDialog", @ViewBuilder actions: @escaping () -> Actions,
        @ViewBuilder message: @escaping () -> Message
    ) -> some View {
        modifier(ManagementDialog(title: title, requested: isPresented, kind: .confirmation, titleVisibility: titleVisibility,
                                  showsCancel: showsCancel, identifier: identifier, actions: actions, message: message))
    }

    func managementConfirmationDialog<Actions: View>(
        _ title: String, isPresented: Binding<Bool>, titleVisibility: Visibility = .visible,
        showsCancel: Bool = true, identifier: String = "managementDialog", @ViewBuilder actions: @escaping () -> Actions
    ) -> some View {
        managementConfirmationDialog(title, isPresented: isPresented, titleVisibility: titleVisibility,
                                     showsCancel: showsCancel, identifier: identifier, actions: actions) { EmptyView() }
    }

    func managementNotice(_ message: Binding<String?>, kind: ManagementFeedbackKind = .success) -> some View {
        overlay(alignment: .top) {
            if let current = message.wrappedValue {
                ManagementFeedbackBanner(message: current, kind: kind)
                    .padding(.horizontal, 16).padding(.top, 8)
                    .allowsHitTesting(false)
                    .task(id: current) {
                        UIAccessibility.post(notification: .announcement, argument: current)
                        do { try await Task.sleep(for: .seconds(4.2)) }
                        catch { return }
                        if message.wrappedValue == current { message.wrappedValue = nil }
                    }
            }
        }
    }
}
