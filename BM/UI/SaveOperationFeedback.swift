import SwiftUI

enum SaveFailureOperation {
    case createBackup, exportFile, chooseBackup, validateBackup, restore
    case discardForClose, discardForSelection

    var label: String {
        switch self {
        case .createBackup: "백업 생성 실패"
        case .exportFile: "백업 내보내기 실패"
        case .chooseBackup: "백업 파일 선택 실패"
        case .validateBackup: "백업 파일 검증 실패"
        case .restore: "전체 복원 실패"
        case .discardForClose, .discardForSelection: "검증 사본 정리 실패"
        }
    }
}

enum SaveFailureRetry: Equatable {
    case createBackup, chooseExportLocation, chooseBackup, chooseAnotherBackup, confirmRestore
    case discardAndClose, discardAndChooseBackup, close

    var label: String {
        switch self {
        case .createBackup: "백업 다시 만들기"
        case .chooseExportLocation: "저장 위치 다시 선택"
        case .chooseBackup: "백업 다시 선택"
        case .chooseAnotherBackup: "다른 백업 선택"
        case .confirmRestore: "복원 다시 확인"
        case .discardAndClose, .discardAndChooseBackup: "정리 다시 시도"
        case .close: "닫고 다시 확인"
        }
    }
}

struct SaveOperationFailure: Identifiable {
    private enum Reason { case space, permission, invalid, busy, unavailable, other }
    let id = UUID()
    let operation: SaveFailureOperation
    let details: String
    private let reason: Reason

    init(_ error: Error, operation: SaveFailureOperation) {
        self.operation = operation
        details = error.localizedDescription
        if let protection = error as? SaveProtectionError {
            switch protection {
            case .invalid: reason = .invalid
            case .busy: reason = .busy
            case .unavailable: reason = .unavailable
            }
        } else if error is DecodingError {
            reason = .invalid
        } else {
            let outer = error as NSError
            let underlying = outer.userInfo[NSUnderlyingErrorKey] as? NSError
            let cocoa = outer.domain == NSCocoaErrorDomain ? outer : underlying
            let code = cocoa?.domain == NSCocoaErrorDomain ? cocoa.map { CocoaError.Code(rawValue: $0.code) } : nil
            switch code {
            case .fileWriteOutOfSpace: reason = .space
            case .fileReadNoPermission, .fileWriteNoPermission: reason = .permission
            default: reason = .other
            }
        }
    }

    var title: String {
        if reason == .space { return operation == .exportFile ? "저장 공간이 부족해요" : "기기 저장 공간이 부족해요" }
        if reason == .unavailable { return "저장 화면을 다시 열어 주세요" }
        switch operation {
        case .createBackup: return "백업을 만들지 못했어요"
        case .exportFile: return "백업을 저장하지 못했어요"
        case .chooseBackup, .validateBackup: return "이 백업을 열 수 없어요"
        case .restore: return reason == .invalid ? "백업을 다시 선택해 주세요" : "복원을 완료하지 못했어요"
        case .discardForClose, .discardForSelection: return "검증 사본 정리가 필요해요"
        }
    }

    var explanation: String {
        if reason == .unavailable { return "저장 연결을 확인할 수 없어요. 화면을 닫고 다시 열어 주세요." }
        if reason == .space {
            return operation == .exportFile
                ? "선택한 저장 위치의 공간을 확인한 뒤 다른 위치를 선택해 주세요."
                : "기기 공간을 확보한 뒤 다시 시도해 주세요."
        }
        switch operation {
        case .createBackup:
            return reason == .busy ? "저장 작업이나 저장소 확인을 마치지 못했어요. 잠시 후 다시 시도해 주세요."
                : "현재 저장에서 백업 파일을 준비하지 못했어요. 앱을 다시 열거나 백업 생성을 다시 시도해 주세요."
        case .exportFile:
            return reason == .permission ? "선택한 위치에 파일을 쓸 수 없어요. 다른 저장 위치를 선택해 주세요."
                : "백업 파일을 저장하지 못했어요. 저장 위치를 다시 선택해 주세요."
        case .chooseBackup, .validateBackup:
            if reason == .permission { return "파일의 접근 권한과 다운로드 상태를 확인한 뒤 다시 선택해 주세요." }
            if reason == .invalid { return "지원하지 않는 형식이거나 파일에 문제가 있는 백업이에요. 다른 백업을 선택해 주세요." }
            return "파일을 읽거나 검증하는 중 문제가 생겼어요. 백업을 다시 선택해 주세요."
        case .restore:
            if reason == .invalid { return "검증한 자료를 사용할 수 없어요. 백업을 다시 선택해 검증해 주세요." }
            if reason == .permission { return "복원에 필요한 파일 접근을 마치지 못했어요. 앱을 다시 연 뒤 확인해 주세요." }
            return "백업으로 전환을 마치지 못했어요. 날짜와 선수를 다시 확인한 뒤 복원해 주세요."
        case .discardForClose:
            return "화면을 닫기 전에 검증 사본 정리를 마쳐야 해요. 정리를 다시 시도해 주세요."
        case .discardForSelection:
            return "다른 파일을 검증하기 전에 이전 사본 정리가 필요해요. 정리를 다시 시도해 주세요."
        }
    }

    func retry(preparedState: PreparedSave.State?, hasExport: Bool, hasProtection: Bool) -> SaveFailureRetry {
        guard hasProtection, reason != .unavailable else { return .close }
        switch operation {
        case .createBackup: return .createBackup
        case .exportFile: return hasExport ? .chooseExportLocation : .createBackup
        case .chooseBackup, .validateBackup: return .chooseAnotherBackup
        case .restore:
            if reason == .permission { return .close }
            if preparedState == .committed { return .close }
            return preparedState == .pending && reason != .invalid ? .confirmRestore : .chooseBackup
        case .discardForClose: return .discardAndClose
        case .discardForSelection: return .discardAndChooseBackup
        }
    }

    static func currentState(hasProtection: Bool, recoveryOnly: Bool) -> String {
        guard hasProtection else { return "저장 연결 확인 필요" }
        return recoveryOnly ? "열기 확인 필요 · 복구 진행 가능" : "사용 중 · 계속 플레이 가능"
    }
}

struct SaveOperationFailureView: View {
    let failure: SaveOperationFailure
    let currentState: String
    let retryTitle: String
    let retry: () -> Void
    @AccessibilityFocusState private var titleFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: ManagementTheme.Space.compact) {
            Label(failure.operation.label, systemImage: "exclamationmark.square.fill")
                .font(.footnote.weight(.semibold)).foregroundStyle(Color(hex: 0x814637))
                .accessibilityIdentifier("saveFailureStage")
            Text(failure.title).font(ManagementPixelFont.readable(.sectionTitle))
                .fixedSize(horizontal: false, vertical: true).accessibilityAddTraits(.isHeader)
                .accessibilityFocused($titleFocused).accessibilityIdentifier("saveFailureTitle")
            Text(failure.explanation).font(.subheadline).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("saveFailureReason")
            Divider().overlay(Color(hex: 0xc9bb8c))
            VStack(alignment: .leading, spacing: ManagementTheme.Space.micro) {
                Text("현재 커리어").font(.footnote).foregroundStyle(GameTheme.muted)
                Text(currentState).font(.subheadline.weight(.semibold))
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("saveCurrentState")
            }
            Divider().overlay(Color(hex: 0xc9bb8c))
            Button(retryTitle, action: retry).buttonStyle(ManagementButtonStyle())
                .accessibilityIdentifier("saveFailureRetry")
            DisclosureGroup("오류 상세") {
                Text(failure.details).font(.footnote).foregroundStyle(GameTheme.muted)
                    .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
            }.font(.footnote).tint(GameTheme.navy).environment(\.colorScheme, .light)
                .accessibilityIdentifier("saveFailureDetails")
        }
        .padding(ManagementTheme.Space.screen).frame(maxWidth: .infinity, alignment: .leading)
        .foregroundStyle(GameTheme.navy).background(GameTheme.boardInk, in: ManagementStepFrame())
        .overlay(ManagementStepFrame().strokeBorder(Color(hex: 0xc9bb8c), lineWidth: ManagementTheme.Control.border))
        .task(id: failure.id) {
            titleFocused = false
            await Task.yield()
            guard !Task.isCancelled else { return }
            titleFocused = true
        }
    }
}
