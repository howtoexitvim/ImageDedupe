<div align="center">

# Image Dedupe

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

![Platform](https://img.shields.io/badge/platform-macOS-111827?logo=apple&logoColor=white)
![유형](https://img.shields.io/badge/type-Photo%20Dedupe-2563eb)
![아키텍처](https://img.shields.io/badge/architecture-local--first-059669)

</div>

Image Dedupe는 iPhone에 쌓인 사진과 동영상을 정리하는 Mac 앱입니다.

케이블을 연결하고 한 번 스캔하면 모든 것이 한 창에 모입니다. 정렬 가능한 목록, 또는 썸네일 그리드, 그 옆에는 미리보기와 메타데이터. 원하는 것을 검색하고, 남길 것을 내려받고, 더 이상 필요 없는 것을 지우세요.

iPhone과의 통신은 Apple이 만든 ImageCaptureCore를 통해 케이블로만 이루어집니다. 계정도, 클라우드도, 분석도, 네트워크 통신도 없습니다. 어떤 것도 Mac을 떠나지 않습니다.

그리고 앱이 알아서 지우는 일은 없습니다. 앱은 제안하고, 결정은 당신이 합니다.

## Image Dedupe를 선택하는 이유

- 🔒 **모든 것이 로컬에서**: 로그인도, 업로드도, 원격 분석도 없습니다. Mac과 케이블뿐입니다.
- 🧊 **의도적으로 보수적**: 중복 항목은 자동 삭제가 아니라 직접 확인할 후보일 뿐입니다.
- 🔍 **무엇이든 빠르게 찾기**: 파일 이름으로 검색하거나 `name:`, `kind:`, `size:`, `duration:` 필터로 좁혀 보세요.
- 🖼️ **보고 나서 결정**: 목록과 그리드 보기, 정렬 가능한 열, 미리보기와 실제 EXIF 메타데이터를 보여주는 인스펙터.
- ⬇️ **고른 것만 내려받기**: 실시간 진행률, 언제든 취소, 저장 위치 사전 확인, 조용한 덮어쓰기 없음.
- 🗑️ **삭제는 분명한 의사로**: 앱 안에서의 명시적 확인, 감사 기록 보관, 그리고 이후 자동 재스캔.
- 🆓 **무료, MIT 라이선스**.

## 스크린샷

<div align="center">
  <img src="assets/duplicates-review.png" width="88%" alt="Image Dedupe 중복 검토 화면: QVKQ5385.JPG — 2 copies 그룹 머리글 아래 두 사본이 나열되고 하나가 남길 항목으로 표시되며, 인스펙터에 미리보기와 EXIF 메타데이터가 보입니다" />
</div>

<br/>

<table>
	<tr>
		<td align="center" colspan="2"><strong>Scanned 4189 items. Conservative duplicates: 1.</strong><br/>이 상태 표시줄 한 줄이 이 앱의 철학 전부입니다. 확신하는 것만 제안합니다.</td>
	</tr>
	<tr>
		<td align="center"><strong>연결하고 스캔</strong></td>
		<td align="center"><strong>목록 보기와 인스펙터</strong></td>
	</tr>
	<tr>
		<td align="center"><img src="assets/scan-empty.png" alt="iPhone 연결을 기다리는 Image Dedupe의 빈 화면과 Scan iPhone 버튼" /></td>
		<td align="center"><img src="assets/all-media-list.png" alt="이름, 종류, 날짜, 파일 크기 열과 체크박스 선택, 검색 필드, 오른쪽 인스펙터를 갖춘 Image Dedupe 목록 브라우저" /></td>
	</tr>
	<tr>
		<td align="center"><strong>그리드 보기</strong></td>
		<td align="center"><strong>검토를 기다리는 중복 항목</strong></td>
	</tr>
	<tr>
		<td align="center"><img src="assets/all-media-grid.png" alt="같은 라이브러리를 썸네일로 보여주는 Image Dedupe 그리드 브라우저" /></td>
		<td align="center"><img src="assets/duplicates-review.png" alt="같은 파일의 사본 두 개로 이루어진 Image Dedupe 중복 그룹, 하나는 남길 항목으로 표시됨" /></td>
	</tr>
</table>

## 설치

[릴리스 페이지](https://github.com/howtoexitvim/ImageDedupe/releases)에서 DMG를 내려받고(현재 릴리스는 `ImageDedupe-v1.0`, 버전 1.0.0), **Image Dedupe**를 응용 프로그램 폴더로 끌어다 놓으세요.

이 빌드는 ad-hoc 서명이며 아직 공증을 받지 않았습니다. 그래서 다운로드 표시를 지우기 전까지 macOS가 실행을 막습니다. 터미널에서 한 번만 실행하세요.

```sh
xattr -dr com.apple.quarantine "/Applications/Image Dedupe.app"
```

그다음부터는 평소처럼 열 수 있습니다.

**준비물:** macOS 14 이상의 Apple 실리콘 Mac, 잠금이 해제되고 이 Mac을 신뢰하는 iPhone, 데이터 전송이 가능한 케이블, 그리고 스캔하는 동안 이미지 캡처와 사진 앱을 닫아 두는 것.

## 소스에서 빌드하기

macOS 14 이상과 Swift 6.2 툴체인이 필요합니다.

```sh
./scripts/build-debug-app.sh
open "$(swift build --show-bin-path)/Image Dedupe.app"
swift test
```

## 앞으로 할 일

Developer ID 서명과 Apple 공증은 아직 준비되지 않았습니다. 위의 격리 플래그 해제 단계가 필요한 이유입니다. 유니버설 빌드도 계획하고 있습니다. (이 앱은 전에 iPhone Dedupe라는 이름이었습니다. 기존 기록과 환경설정은 자동으로 이어집니다.)

## License

[MIT](LICENSE)
