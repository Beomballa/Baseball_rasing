import SwiftUI
import UIKit

/// Informational only: opening support never reads or changes a career store.
enum SupportInformation {
    static let title = "픽셀야구인생 고객지원"
    static let refundHelpURL = URL(string: "https://support.apple.com/ko-kr/118223")!
    static let refundRequestURL = URL(string: "https://reportaproblem.apple.com/")!
    static let testFlightPrivacyURL = URL(string: "https://www.apple.com/legal/privacy/data/en/test-flight/")!

    static func fontLicense(bundle: Bundle = .main) -> String? {
        guard let data = NSDataAsset(name: "ManagementPixelLicenseV59", bundle: bundle)?.data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

enum SupportTopic: String, CaseIterable, Identifiable {
    case privacy, terms, refund, children, dataRequests, licenses
    var id: String { rawValue }
    var title: String {
        switch self {
        case .privacy: "개인정보·기기 저장"
        case .terms: "서비스 이용 안내"
        case .refund: "구매·환불 안내"
        case .children: "어린이·보호자 안내"
        case .dataRequests: "문의·자료 관리"
        case .licenses: "글꼴·라이선스"
        }
    }
    var subtitle: String {
        switch self {
        case .privacy: "기기 저장과 TestFlight 자료를 구분해요"
        case .terms: "계정·커리어·백업의 이용 범위"
        case .refund: "Apple의 신청 경로와 처리 절차"
        case .children: "실명 없이 플레이하고 문의는 신중하게"
        case .dataRequests: "문의에 필요한 정보와 삭제 요청 구분"
        case .licenses: "NeoDunggeunmo · SIL OFL 1.1 원문"
        }
    }
    var sections: [(title: String, text: String)] {
        switch self {
        case .privacy: [
            ("이 기기에 저장하는 정보", "선수 이름·외형·등번호·가상 학교·능력치·구종·경기와 훈련 기록·날짜·계약·관찰 보고서를 기기에 저장합니다. 선수 나이는 게임 속 나이이며 실제 생년월일을 입력하는 항목이 아닙니다. 실명 대신 가상 이름을 사용해 주세요."),
            ("기본 플레이와 설정", "이 버전에는 게임 계정·개발자 클라우드·광고 추적 기능이 없습니다. 기기 저장을 개발자 서버로 자동 전송하지 않습니다. 햅틱·타격 안내·재생 방식은 기기 설정에 보관합니다."),
            ("백업 파일", "설정에서 직접 내보낸 파일에는 전체 커리어와 선수 이름이 들어 있습니다. 파일은 암호화되지 않았으며 손상 검사와 암호화는 다릅니다. 파일 앱의 저장 위치나 iPhone 백업 설정에 따라 외부 저장소에 보관될 수 있습니다."),
            ("TestFlight는 별도", "TestFlight로 테스트하면 Apple이 사용·충돌 정보와 제출한 제보를 개발자에게 제공합니다. 초대 방식에 따라 이름·이메일이 포함될 수 있습니다. 기본 플레이의 기기 저장과 별개로 Apple의 안내를 확인해 주세요."),
            ("공개 정책 준비", "문의 자료의 처리 근거·보관 기간·외부 업체·국외 이전·권리 요청 창구는 아직 확정 전입니다. 이 안내는 현재 기능 설명이며 확정된 개인정보 처리방침을 대신하지 않습니다.")
        ]
        case .terms: [
            ("게임의 이용 범위", "픽셀야구인생은 기기에 선수 커리어를 저장하는 1인 야구 게임입니다. 선수·학교·구단·계약금·성적은 게임 안의 설정과 기록이며 실제 입단이나 금전 지급을 의미하지 않습니다."),
            ("계정과 저장", "별도의 게임 회원가입은 없습니다. 경기·훈련은 저장된 진행 상태부터 이어갈 수 있습니다. 앱 삭제·기기 분실 후 자동 복구는 보장되지 않으므로 중요한 기록은 설정에서 직접 백업해 주세요."),
            ("백업과 복원", "복원 전 파일을 검증하고 확인을 거쳐 전체 커리어를 백업 시점으로 되돌립니다. 현재 기록과 합치지 않습니다. 복원 전 저장과 은퇴 기록은 자동 삭제하지 않습니다."),
            ("판매·지원 조건", "한국에서 앱 1회 유료 다운로드를 준비 중입니다. 이 버전에 인앱 결제·구독·자동 갱신은 없습니다. 최종 가격·운영자·지원 창구·약관 시행일은 공개 전 확정해야 합니다."),
            ("권리와 문의", "이 안내를 읽는 것만으로 권리를 포기하거나 새 약관에 동의한 것으로 처리하지 않습니다. 하자·환불·분쟁에 관한 법령상 권리를 일괄 제한하지 않습니다. 정식 이용약관은 운영 조건 확인 후 별도로 고지할 예정입니다.")
        ]
        case .refund: [
            ("현재 판매 준비", "한국 1회 유료 다운로드를 준비 중이며 인앱 결제와 자동 갱신은 없습니다. TestFlight 테스트 빌드와 유료 구매는 별개입니다. 가격은 판매 시 App Store의 최종 표시를 확인해 주세요."),
            ("Apple에서 신청", "App Store에서 구매한 앱은 Apple의 문제 신고 페이지에서 환불 가능 여부를 확인하고 신청할 수 있습니다. 구매한 Apple 계정으로 직접 로그인한 뒤 해당 앱과 사유를 선택합니다."),
            ("신청 뒤 확인", "신청 상태와 추가 안내는 Apple에서 확인합니다. 이 앱은 결제 취소를 직접 실행하거나 환불을 보장하지 않습니다. 비밀번호·인증번호·카드번호를 개발자에게 보내지 마세요."),
            ("권리를 일괄 제한하지 않아요", "다운로드나 사용만으로 모든 환불이 불가능하다고 안내하지 않습니다. 한국의 청약철회·디지털 콘텐츠 제공·하자 및 미성년 구매에 관한 조건과 Apple의 절차를 함께 확인해야 합니다.")
        ]
        case .children: [
            ("게임 속 선수 정보", "선수 이름에는 별명이나 가상 이름을 써 주세요. 집 주소·연락처·실제 생년월일·실제 학교를 적을 필요가 없습니다."),
            ("문의를 보내기 전", "만14세 미만 이용자는 개인정보나 전체 저장 파일을 보내기 전에 보호자와 함께 확인해 주세요. 아동 문의의 접수·필요한 법정대리인 동의와 확인 방법은 현재 준비 중이며 이 화면에서 정보를 수집하지 않습니다."),
            ("플레이·구매·테스트는 달라요", "게임을 플레이할 수 있는 나이, 구매에 필요한 동의, TestFlight를 이용할 수 있는 나이는 같은 기준이 아닙니다. 보호자와 함께 각각의 이용 조건을 확인해 주세요.")
        ]
        case .dataRequests: [
            ("오류 문의에 필요한 내용", "앱 버전, 기기·iOS 버전, 문제가 발생한 메뉴, 재현 순서와 기대한 동작을 먼저 정리해 주세요. 화면 사진은 선택 사항이며 이름·알림 등 개인정보를 가려 주세요."),
            ("보내지 않아도 되는 정보", "비밀번호·인증번호·주민등록번호·카드번호는 문의에 필요하지 않습니다. 전체 저장 파일도 기본 문의 자료가 아닙니다. 공개 문의 이메일은 아직 준비 중입니다."),
            ("기기 기록과 외부 자료", "게임 계정 탈퇴 기능은 없습니다. 기기 내 커리어, 직접 내보낸 파일, 기기 백업, 문의로 보낸 자료는 보관 위치가 다릅니다. 앱을 삭제해도 별도로 저장한 백업 파일까지 함께 삭제되는 것은 아닙니다."),
            ("삭제·권리 요청", "개발자가 받은 문의·제보 자료의 열람·정정·삭제 등은 별도 접수 창구를 준비 중입니다. 적절한 본인 확인과 법정 보관 여부를 확인한 후 처리해야 합니다. 이 화면은 자료를 삭제하거나 환불을 실행하지 않습니다.")
        ]
        case .licenses: [
            ("게임 글꼴", "NeoDunggeunmo · Eunbin Jeong (Dalgona.)\nSIL Open Font License 1.1. 아래 원문은 앱에 포함된 라이선스 파일입니다."),
            ("이용권 확인 범위", "이 문구는 해당 글꼴에 적용됩니다. 게임의 다른 이미지·로고의 이용권까지 이 라이선스로 허용되는 것은 아닙니다.")
        ]
        }
    }
}

struct SupportInformationView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ManagementTheme.Space.screen) {
                ManagementFileHeader(eyebrow: "PLAYER SUPPORT", title: SupportInformation.title, note: "이용 안내 · 공개 전 검토본")
                ManagementPanel("안내 준비 상태") {
                    Text("공개 운영자와 문의 이메일을 준비 중입니다. 아래 안내를 읽거나 Apple의 환불 경로를 확인할 수 있으며, 이 화면에서 개인정보를 입력하거나 전송하지 않습니다.")
                        .managementFont(.body).accessibilityIdentifier("supportPendingNotice")
                }
                ManagementPanel("공개 전 확인할 항목") {
                    Text("지원 이메일 · 운영자 표시: 미확정")
                    Text("문의 보관 기준 · 어린이 문의 절차: 미확정")
                    Text("이미지·로고 이용권: 자료별 확인 필요")
                    Text("확정 전에는 이 화면에서 문의 자료를 받지 않습니다. 전체 저장 파일이나 개인정보를 보내실 필요가 없습니다.")
                        .managementFont(.helper)
                }.managementFont(.body).accessibilityIdentifier("supportReleasePendingItems")
                ForEach(SupportTopic.allCases) { topic in
                    NavigationLink {
                        SupportTopicView(topic: topic)
                    } label: {
                        VStack(alignment: .leading, spacing: ManagementTheme.Space.micro) {
                            Text(topic.title).fontWeight(.semibold)
                            Text(topic.subtitle).managementFont(.helper)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(ManagementButtonStyle(variant: .secondary))
                    .accessibilityIdentifier("supportTopic-" + topic.rawValue)
                    .accessibilityElement(children: .combine)
                }
            }.padding(ManagementTheme.Space.screen)
        }
        .background(GameTheme.board).foregroundStyle(GameTheme.boardInk)
        .navigationTitle("고객지원").navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar { SupportBackAction(label: "설정으로 돌아가기", identifier: "supportBack") { dismiss() } }
    }
}

private struct SupportTopicView: View {
    let topic: SupportTopic
    @Environment(\.dismiss) private var dismiss
    private let license = SupportInformation.fontLicense()
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: ManagementTheme.Space.screen) {
                ManagementFileHeader(eyebrow: "PLAYER GUIDE", title: topic.title, note: topic == .licenses ? "앱에 포함된 원문" : "이용 안내 · 공개 정책 확정 전")
                ForEach(topic.sections.indices, id: \.self) { index in
                    ManagementPanel(topic.sections[index].title, surface: .paper) {
                        Text(topic.sections[index].text).managementFont(.body)
                            .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
                    }.accessibilityIdentifier("supportSection-\(topic.rawValue)-\(index)")
                }
                if topic == .refund {
                    SupportExternalLink(title: "Apple 환불 신청 안내", url: SupportInformation.refundHelpURL, identifier: "supportRefundHelp")
                    SupportExternalLink(title: "Apple에 환불 신청", url: SupportInformation.refundRequestURL, identifier: "supportRefundRequest")
                }
                if topic == .privacy {
                    SupportExternalLink(title: "Apple TestFlight 개인정보 안내", url: SupportInformation.testFlightPrivacyURL, identifier: "supportTestFlightPrivacy")
                }
                if topic == .licenses {
                    ManagementPanel("SIL OPEN FONT LICENSE · 원문", surface: .paper) {
                        Text(license ?? "라이선스 파일을 읽지 못했습니다. 앱 버전과 함께 문의해 주세요.")
                            .managementFont(.helper).textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("supportFontLicense")
                    }
                }
            }.padding(ManagementTheme.Space.screen)
        }
        .background(GameTheme.board).foregroundStyle(GameTheme.boardInk)
        .navigationTitle(topic.title).navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden()
        .toolbar { SupportBackAction(label: "고객지원 목록으로 돌아가기", identifier: "supportTopicBack") { dismiss() } }
    }
}

private struct SupportBackAction: ToolbarContent {
    let label: String
    let identifier: String
    let action: () -> Void
    var body: some ToolbarContent {
        if #available(iOS 26.0, *) { item.sharedBackgroundVisibility(.hidden) }
        else { item }
    }
    private var item: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button(action: action) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 20, weight: .bold))
                    .frame(minWidth: ManagementTheme.Control.hit, minHeight: ManagementTheme.Control.hit)
            }
            .buttonStyle(ManagementToolbarButtonStyle())
            .accessibilityLabel(label).accessibilityIdentifier(identifier)
        }
    }
}

private struct SupportExternalLink: View {
    let title: String
    let url: URL
    let identifier: String
    var body: some View {
        Link(destination: url) {
            VStack(spacing: ManagementTheme.Space.micro) {
                Text(title)
                Text("Apple 웹사이트 열기").managementFont(.helper)
            }
        }
        .buttonStyle(ManagementButtonStyle(variant: .secondary))
        .accessibilityHint("외부 Apple 웹사이트로 이동합니다. 앱의 저장은 변경하지 않습니다.")
        .accessibilityIdentifier(identifier)
    }
}
