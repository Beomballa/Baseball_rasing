import SwiftUI
import Observation

@MainActor @Observable final class CareerTransition {
    struct Display: Identifiable {
        let id = UUID()
        let label: String
        var date: String
        let cancellable: Bool
    }
    private(set) var display: Display?
    private var task: Task<Void, Never>?

    func perform(date: String, label: String, reduced: Bool, cancellable: Bool = false,
                 action: @escaping @MainActor () async -> Void) {
        guard display == nil else { return }
        let current = Display(label: label, date: date, cancellable: cancellable)
        display = current
        task = Task { @MainActor in
            defer {
                if display?.id == current.id { display = nil; task = nil }
            }
            do {
                try await Task.sleep(for: .milliseconds(reduced ? 40 : 350))
                try Task.checkCancellation()
                await action()
                try await Task.sleep(for: .milliseconds(reduced ? 40 : 300))
            } catch is CancellationError { /* Already saved days remain committed. */ }
            catch { return }
        }
    }

    func arrive(on date: String, reduced: Bool) {
        withAnimation(reduced ? nil : .easeOut(duration: 0.2)) { display?.date = date }
    }
    func requestCancel() { task?.cancel() }
}

struct CareerTransitionOverlay: View {
    let transition: CareerTransition
    @Environment(\.accessibilityReduceMotion) private var reduced
    var body: some View {
        if let display = transition.display {
            ZStack {
                GameTheme.navy.opacity(0.96).ignoresSafeArea()
                VStack(spacing: 18) {
                    Text("CAREER CALENDAR").font(.caption.monospaced().bold()).foregroundStyle(GameTheme.gold)
                    ZStack(alignment: .top) {
                        Rectangle().fill(GameTheme.paper).frame(width: 76, height: 76)
                        Rectangle().fill(GameTheme.gold).frame(width: 76, height: 18)
                        HStack { Rectangle().frame(width: 7, height: 16); Spacer(); Rectangle().frame(width: 7, height: 16) }
                            .foregroundStyle(GameTheme.paper).frame(width: 44).offset(y: -7)
                        Text(String(display.date.suffix(2))).font(.largeTitle.monospaced().bold())
                            .foregroundStyle(GameTheme.navy).offset(y: 24).id(display.date)
                            .transition(reduced ? .identity : .opacity.combined(with: .offset(y: -8)))
                    }.frame(height: 82).accessibilityHidden(true)
                    Text(display.label).font(.headline)
                    Text(display.date.replacingOccurrences(of: "-", with: ".")).font(.title2.monospaced().bold())
                        .accessibilityIdentifier("transitionDate")
                    ProgressView().tint(GameTheme.gold)
                    if display.cancellable {
                        Button("진행 중지") { transition.requestCancel() }.buttonStyle(GameButtonStyle(secondary: true))
                    }
                }
                .padding(24).frame(maxWidth: 300).foregroundStyle(GameTheme.paper)
                .overlay(Rectangle().strokeBorder(GameTheme.gold, lineWidth: 3))
                .padding(24)
            }.accessibilityElement(children: .contain).accessibilityIdentifier("careerTransition")
        }
    }
}
