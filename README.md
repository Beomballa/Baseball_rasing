# BM iOS

SwiftUI 선수 생성·홈, SwiftData 로컬 커리어 저장, SpriteKit 경기장 진입을 연결한 iOS 본 개발의 첫 단계입니다. 기존 `../pitching-prototype` 웹과 독립된 Xcode 프로젝트입니다.

## 환경

- iPhone / 세로 화면 / 최소 iOS 17.0
- Swift 6 언어 모드, Xcode 프로젝트와 공유 `BM` 스킴
- 첫 검증 도구: Xcode 27.1 (27A9275), Apple Swift 6.4, Simulator iOS 27.0. 최소 OS는 배포 타깃이며 iOS 17 실기기 검증 완료를 뜻하지 않습니다.
- SwiftUI / SpriteKit / SwiftData만 사용하며 외부 패키지·서버·로그인·CloudKit 연동이 없습니다.

`BM.xcodeproj`를 열고 `BM` 스킴과 iPhone Simulator를 선택해 실행합니다. 실기기는 Xcode의 Signing & Capabilities에서 자신의 Team과 고유 Bundle Identifier를 설정해야 합니다. 현재 `dev.bm.career`는 개발용 식별자이며 배포용 팀은 지정하지 않았습니다.

## 구현 범위

1. 이름(1~12자)·등번호(0~99), 고교50곳 직접/무작위 선택
2. 타자 포지션 / 투수 좌·우투, 6피부×6머리색×6유니폼×3머리형×3표정
3. 역할별 선수1명 저장, 다른 역할 추가와 홈 전환
4. 홈에서 소속·정보·실제 초기 능력/구종 숙련도·피로 확인
5. SpriteKit 도트 야구장 이동과 좌우 투구 손을 반영한 간단한 연습 장면

경기장 연습은 기록/성장/피로를 변경하지 않습니다. 기존 웹의 실제 경기·훈련·하루 행동·특성·리그·계약·달력 진행은 아직 이식하지 않았습니다. 홈의 날짜/16세·고1/오늘 행동 표시는 시작 상태입니다. 새로운 나이/날짜 진행을 구현할 때 저장된 시작일 기준 계산으로 확장합니다.

## 구조와 저장

- `BM/App`: 초기 데이터 로드/오류·재시도, NavigationStack·역할 선택
- `BM/Domain`: 선수 생성 검증·역할/외형·학교 데이터 계약
- `BM/Persistence`: V1 모델/이전 계획, 로컬 전용 Container, 명시 저장과 실패 rollback
- `BM/Features`: 생성·홈·경기장 화면
- `BM/UI`: 도트 캐릭터·각진 버튼·정보 패널/수치 막대
- `BM/Resources/schools.json`: 기존 확정50교 ID/지역/이름. 학교·공식 자산 이용 허락을 의미하지 않습니다.
- `BMTests`: 입력 검증·역할 분리/중복 거부·실제 파일 재열기와 외형/구종 보존
- `BMUITests`: 전용 빈 시뮬레이터에서 생성→재실행→경기장→두 번째 역할→재실행 흐름

SwiftData의 CloudKit/group container를 명시적으로 끄고 자동 저장도 끕니다. 생성 성공은 `context.save()` 후에만 홈으로 전환합니다. 저장소를 열지 못하면 오류와 재시도를 제공하며 자동 삭제/메모리 저장으로 대체하지 않습니다. 사용자가 데이터를 지우거나 앱을 삭제하면 복원을 보장하지 않습니다. 웹 localStorage를 읽거나 이전하지 않습니다.

## 검증

Xcode의 Product → Test 또는 다음 명령으로 실행합니다. UI 테스트는 신규 선수 생성을 검증하므로 **전용 빈 시뮬레이터**를 사용합니다. 테스트 코드에는 사용자 세이브 초기화 기능이 없습니다.

```sh
xcodebuild -project BM.xcodeproj -scheme BM -destination 'platform=iOS Simulator,id=<전용 기기 UDID>' -derivedDataPath /tmp/BM-iOS-DerivedData CODE_SIGNING_ALLOWED=NO test
```

첫 스키마 버전만 있으며 추후 스키마 변경 시 마이그레이션 단계를 추가하고 이전 세이브 fixture로 검증해야 합니다. 전체 커리어·저장 실패 주입·계약 엔진 검증은 이번 테스트 범위가 아닙니다.

## Git

이 `ios` 폴더를 독립 저장소 경계로 사용합니다. 웹 실험물·대용량 QA·사용자 환경 설정과 앱 출시 이력을 분리합니다. 공유 스킴/소스/학교 JSON/테스트는 관리하고 DerivedData·개인 Xcode 설정·서명 파일은 제외합니다. 사용자가 지정한 GitHub 원격에 연결하고 최초 테스트 커밋을 올립니다. 이후 기능 단위 개발을 마치고 관련 검증을 통과할 때마다 커밋/push합니다. 제목은 `YYYY.MM.DD 구체적인 기능 작업 수행` 형식이며 작업일은 KST 기준입니다.

기획 정본은 `../pitching-prototype/docs/`의 MVP/일정/경기·육성 설계/구현 현황을 따릅니다. 이 README는 네이티브 첫 단계의 구현 경계를 설명하며 전체 기획을 복제하지 않습니다.

## 첫 구현 검증 기록

- 전용 iPhone17 Pro / iOS27.0 시뮬레이터를 사용했습니다. 기존 사용자 시뮬레이터·웹 저장은 조작하지 않았습니다.
- 단위4개:50교 데이터·생성 입력 검증·역할 분리/중복 거부·SwiftData 실제 파일 재열기. UI1개:두 역할 생성·재실행·경기장 이동. 최종 결과는 `qa/xcode-test-summary.json`에 기록합니다.
- 최소 iOS17 실기기·VoiceOver/큰 글자·파일 저장 실패 주입·이후 스키마 마이그레이션은 아직 검증하지 않았습니다.
- 개발용 서명/프로비저닝 팀·앱 아이콘/스토어 제출 자산과 배포용 식별자는 출시 준비에서 설정합니다.

## 소스 업로드와 개인정보 보호

업로드 대상은 Swift 앱/테스트, 공유 Xcode 프로젝트/스킴, 학교 JSON, Git 검사 스크립트, README/개발 규칙입니다. 테스트 결과·스크린샷·로그·세이브·개인 IDE 설정·환경 파일·인증/서명 파일은 로컬에만 둡니다. QA 경로를 설명하는 문서가 있어도 해당 산출물은 원격에 포함되지 않습니다.

일반 Bundle Identifier와 Xcode 내부 참조ID는 빌드에 필요한 공개 가능한 설정이며 비밀키가 아닙니다. 개인 Team/인증값은 공유 프로젝트에 입력해 커밋하지 말고 `Signing.local.xcconfig` 등 로컬 설정으로 관리합니다. `.gitignore`만으로 이미 추적하거나 강제 추가한 파일을 보호할 수 없어 pre-commit에서 staged 파일을 다시 검사합니다. 패턴 검사는 완전한 비밀 탐지 도구가 아니므로 staged diff 검토도 수행합니다.

최초 clone 후 로컬 훅을 활성화합니다. 작성자는 자신의 GitHub noreply 주소를 저장소 로컬 설정에 사용합니다. 이 값과 원격 인증정보는 추적 파일에 저장하지 않습니다.

```sh
git config core.hooksPath .githooks
python3 scripts/test_git_security.py
python3 scripts/check_staged.py
```

커밋 메시지 예: `2026.10.19 iOS 선수 생성 및 로컬 저장 작업 수행`. 기능 완료 후 테스트/빌드·staged 개인정보 검사·push·원격 SHA 확인을 수행합니다. 자동 시간 스케줄이 아니라 이 저장소의 개발 작업 규칙입니다.
