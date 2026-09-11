<div align="center">

# Image Dedupe

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

![Platform](https://img.shields.io/badge/platform-macOS-111827?logo=apple&logoColor=white)
![Type](https://img.shields.io/badge/type-Photo%20Dedupe-2563eb)
![Local First](https://img.shields.io/badge/architecture-local--first-059669)

</div>

Image Dedupe는 연결된 iPhone의 미디어를 살펴보고, 고른 파일을 내려받고, 보수적인 중복 후보를 찾아내고, 확인을 마친 기기 항목을 의도적으로 삭제하기 위한 macOS 네이티브 앱입니다.

Apple의 ImageCaptureCore 프레임워크 위에서 동작합니다. 계정도, 클라우드 백엔드도, 분석도, 카탈로그 업로드도, 네트워크 클라이언트도 없습니다. 모든 것이 사용자의 Mac 안에 머뭅니다.

무엇도 알아서 삭제되지 않습니다. 앱은 제안만 하고, 결정은 사용자가 합니다.

이전 이름은 iPhone Dedupe였습니다. 이름을 바꾼 뒤에도 기존 작업 기록과 환경설정은 자동으로 이어집니다. 식별자가 그대로 유지되어야 하는 곳에만 옛 이름이 남아 있습니다.

## 설치

[릴리스 페이지](https://github.com/howtoexitvim/ImageDedupe/releases)에서 DMG를 내려받고(현재 릴리스는 `ImageDedupe-v1.0`, 버전 1.0.0), 앱을 응용 프로그램 폴더로 끌어다 놓은 다음, 다운로드 격리 플래그를 지웁니다.

```sh
xattr -dr com.apple.quarantine "/Applications/Image Dedupe.app"
```

이 빌드는 애드혹 서명되어 있고 Apple 공증을 받지 **않았기** 때문에, 위 명령을 실행하기 전까지는 Gatekeeper가 실행을 막습니다. macOS 14 이상, Apple 실리콘(arm64) 전용입니다. 공증되지 않은 바이너리를 실행하고 싶지 않다면 아래 방법으로 소스에서 직접 빌드하세요.

스캔하기 전에 iPhone의 잠금을 해제하고 이 Mac을 신뢰하도록 설정한 뒤, 이미지 캡처와 사진 앱을 비롯해 기기 세션을 독점할 수 있는 앱을 모두 종료하세요.

## 안전성

안전성은 이 프로젝트의 목적 그 자체이지, 덧붙인 기능이 아닙니다.

- 중복 탐지는 일부러 보수적으로 동작합니다. 사용자가 검토할 *후보*만 제시할 뿐, 자동으로 삭제하지 않습니다.
- 기기 삭제는 언제나 앱 안에서의 명시적 확인이 필요하며, 감사 기록을 영구 저장하고, 삭제 후 자동으로 다시 스캔합니다. 재시도는 검증만 수행합니다.
- 자동화 과정이나 개발용 하니스를 통한 삭제에는 대상 픽스처 파일명을 명시한 새로운 사용자 승인이 추가로 필요합니다. 과거의 승인은 결코 재사용되지 않습니다.
- 다운로드는 먼저 비공개 위치에 준비된 뒤, 디스크립터 상대 경로 기준으로 덮어쓰지 않는 방식으로 커밋됩니다. 기존 파일이 조용히 대체되는 일은 없습니다.
- 계정 없음, 클라우드 없음, 분석 없음, 네트워크 클라이언트 없음.
- 로컬 빌드 게이트가 Hardened Runtime을 강제하며, 앱에는 추적하지 않는 개인정보 매니페스트가 포함되어 있습니다.

## 기능

- 포커스를 공유하는 네이티브 List와 Grid 브라우저, 그리고 명시적인 체크박스 선택;
- 파일 이름 검색과 `name:`, `kind:`, `size:`, `duration:` 필터;
- 정렬 가능하고 상태가 유지되는 List 열;
- 점진적으로 로드되는 정적 Inspector 미리보기(최대 2048픽셀, 메모리 캐시 상한 있음);
- 보수적인 중복 후보 — 자동 삭제는 없음;
- 다운로드 진행 상황, 현재 파일 상태, 취소, 대상 위치 사전 점검, 충돌 차단;
- 명시적인 기기 삭제 확인, 영구 저장되는 감사 기록, 자동 재스캔, 검증만 수행하는 재시도;
- 부분 실패와 취소를 보관하는 Results 기록;
- 주요 작업 흐름에 대한 전체 키보드 접근(Full Keyboard Access)과 VoiceOver 시맨틱.

## 요구 사항

- macOS 14 이상, Apple 실리콘(arm64);
- Swift 6.2 툴체인(빌드하는 경우);
- 잠금이 해제되고 신뢰된 iPhone과 데이터 전송이 가능한 케이블;
- 스캔하는 동안 이미지 캡처, 사진 등 기기 세션을 독점할 수 있는 앱은 종료.

## 빌드와 실행

일반적인 로컬 Debug 앱 번들을 빌드합니다.

```sh
./scripts/build-debug-app.sh
open "$(swift build --show-bin-path)/Image Dedupe.app"
```

UI와 접근성 테스트에는 `.app` 번들을 사용하세요. SwiftPM 실행 파일을 직접 실행하면 macOS의 정상적인 앱 등록 과정을 건너뛰므로 검수 경로가 아닙니다.

전체 테스트 스위트를 실행합니다.

```sh
swift test
swift test -c release
```

가장 최근에 검증된 기준선은 Debug와 Release 구성 모두에서 XCTest 650개와 Swift Testing 22개입니다.

번들 스크립트는 대상 앱이 실행 중인 동안에는 교체나 재서명을 거부합니다. 다시 빌드하기 전에 앱을 종료하세요. 이렇게 하면 macOS가 실행 중인 프로세스를 `Code Signature Invalid`로 종료시키는 일을 막을 수 있습니다.

## 릴리스 후보

명시적으로 로컬 전용이며 배포할 수 없는 애드혹 Hardened Runtime 후보를 빌드합니다.

```sh
IMAGE_DEDUPE_ALLOW_ADHOC=1 ./scripts/build-release-candidate.sh
```

배포 가능한 후보를 만들려면 호출자가 소유한 Developer ID Application 인증서를 지정합니다.

```sh
IMAGE_DEDUPE_SIGNING_IDENTITY="Developer ID Application: …" \
  ./scripts/build-release-candidate.sh
```

호출자 소유의 `notarytool` 키체인 프로파일을 구성한 뒤 실행합니다.

```sh
IMAGE_DEDUPE_SIGNING_IDENTITY="Developer ID Application: …" \
IMAGE_DEDUPE_NOTARY_PROFILE="profile-name" \
  ./scripts/notarize-release.sh "/path/to/Image Dedupe.app"
```

릴리스 스크립트는 필요한 서명이나 공증 입력이 없으면 안전하게 실패합니다. 이 저장소에는 어떤 자격 증명도 저장되어 있지 않습니다.

## 디스크 이미지

`scripts/package-dmg.sh`는 이미 빌드된 후보를 익숙한 "응용 프로그램으로 드래그" 레이아웃과 함께 `dist/Image-Dedupe-<version>.dmg`로 감쌉니다. 의도적으로 빌드는 하지 않습니다. `build-release-candidate.sh`가 만들어 낸 번들을 그대로 포장하므로, 배포되는 산출물은 검증을 통과한 바로 그것이지 그와 비슷해 보이는 또 다른 빌드가 아닙니다.

```sh
IMAGE_DEDUPE_ALLOW_ADHOC=1 ./scripts/package-dmg.sh
```

포장하기 전에 번들에 대해 `verify-release.sh`를 다시 실행하며, `IMAGE_DEDUPE_ALLOW_ADHOC=1`이 명시적으로 설정되지 않는 한 애드혹 서명을 거부합니다. 디스크 이미지야말로 검증되지 않은 번들이 로컬의 실수에서 남의 다운로드로 바뀌는 지점이기 때문입니다. `IMAGE_DEDUPE_SIGNING_IDENTITY`를 설정하면 이미지 자체도 서명됩니다. 스테이플링은 번들에 적용되므로, 포장하기 전에 `.app`을 먼저 공증하세요.

`dist/`는 무시되며 절대 커밋되지 않습니다.

## 프로젝트 구성

- `Sources/DeduperCore`: 순수 모델, 검색/정렬, 중복 판정 정책, 표현, 재시도 정책;
- `Sources/DeviceMediaKit`: 직렬화된 ImageCaptureCore 게이트웨이와 안전한 파일 시스템 경계;
- `Sources/ImageDedupeApp`: SwiftUI/AppKit 애플리케이션, 상태, 영속화, 뷰;
- `Sources/ImageDedupeVerifier`: 개발 전용 실기기 하니스;
- `Tests`: 단위, 통합, 렌더러, 작업, 영속화, 보안 회귀 테스트;
- `Packaging`: 앱 Info.plist와 개인정보 매니페스트;
- `scripts`: Debug/Release 번들, 검증, 공증 도구.

## 현황

실제 iPhone을 연결한 상태에서 동작을 확인했고, 미디어 항목 3,961개 중 3,961개를 불러왔습니다. 소스와 로컬 Hardened Runtime 빌드 게이트는 완성되어 있습니다.

솔직히 아직 남아 있는 작업도 있습니다. Developer ID 서명, Apple 공증과 스테이플링, 깨끗한 Mac에서의 Gatekeeper 검증, 유니버설 빌드, 그리고 App Sandbox 채택 여부에 대한 결정입니다. 이 작업들이 마무리되기 전까지는 배포되는 DMG에 위의 격리 해제 단계가 필요합니다.

## 라이선스

[MIT](LICENSE)
