# ShotMap

[![최신 릴리스](https://img.shields.io/github/v/release/ixiehao/ShotMap?display_name=tag&label=release&color=2563eb)](https://github.com/ixiehao/ShotMap/releases/latest)
[![검증](https://img.shields.io/github/actions/workflow/status/ixiehao/ShotMap/ci.yml?branch=main&label=verify)](https://github.com/ixiehao/ShotMap/actions/workflows/ci.yml)
[![macOS 13+](https://img.shields.io/badge/macOS-13%2B-111827?logo=apple)](https://github.com/ixiehao/ShotMap/releases/latest)
[![MIT 라이선스](https://img.shields.io/badge/license-MIT-059669)](LICENSE)

[English](README.md) · [简体中文](README.zh-CN.md) · [Français](README.fr.md) · [Русский](README.ru.md) · [Español](README.es.md) · [日本語](README.ja.md) · [한국어](README.ko.md)

**앱은 7개 언어를 지원합니다:** English · 简体中文 · Français · Русский · Español · 日本語 · 한국어. 하나의 설치 파일에 모두 포함되어 있습니다.

![Tears of Steel의 장면을 스토리보드로 만드는 ShotMap 작업 화면 — 영어 인터페이스](website/assets/workspace-en.webp?v=20261017)

*스크린샷은 실제 앱의 영어 인터페이스입니다. 앱에서 한국어로 바꿀 수 있습니다.*

## 내 동영상을 더 쉽게 찾으세요.

가족 영상, 여행, 일상의 순간이 쌓일수록 파일 이름이나 썸네일 하나만으로는 원하는 동영상을 찾기 어렵습니다. **ShotMap**은 동영상 속 장면을 한 장의 스토리보드 이미지로 정리합니다. 파일을 하나씩 재생하지 않고도 장면을 훑어보며 기억 속 동영상을 찾을 수 있습니다.

스마트 선택으로 시작한 뒤 ‘프레임 직접 선택’에서 원하는 장면으로 바꾸세요. ShotMap은 macOS 네이티브 오픈 소스 앱입니다. 동영상 처리와 이미지 저장은 Mac에서 이루어지며, 계정이나 동영상 업로드가 필요하지 않습니다.

> **시작하기:** [최신 국제판 다운로드](https://github.com/ixiehao/ShotMap/releases/latest) · 범용 DMG · macOS 13 이상 · Apple Silicon 및 Intel Mac

> **데모 영상 출처:** *Tears of Steel*(2012) © Blender Foundation / Blender Institute, [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/). 이 문서의 스크린샷과 동작 예시에 사용한 영상입니다.

## 다시 보고 싶은 순간을 찾을 때

- **가족 영상과 개인 기록:** 파일을 하나씩 열지 않고 생일, 여행, 노을, 아이의 첫걸음이 담긴 동영상을 찾아보세요.
- **영상 제작과 편집:** 편집 프로그램으로 가져오기 전에 여러 클립을 훑어보고 필요한 장면을 고르세요.
- **동영상 폴더 정리:** 원본마다 한눈에 볼 수 있는 스토리보드를 저장하세요. 필요하면 타임코드와 파일 이름도 표시할 수 있습니다.

## 세 단계로 스토리보드 만들기

| 1. 동영상 추가 | 2. 장면 선택 | 3. 이미지 저장 |
| --- | --- | --- |
| 동영상 하나 또는 여러 개를 드래그하세요. | 스마트 선택으로 시작하고 필요한 프레임을 직접 바꾸세요. | 원본 동영상과 같은 폴더에 PNG 또는 JPG로 저장하세요. |

## 장면과 레이아웃을 원하는 대로

- 선명하고 다양한 장면을 우선 선택하고, 검은 화면·흐린 프레임·거의 같은 장면은 줄이도록 설계했습니다.
- ‘프레임 직접 선택’에서 플레이어, 시각적 타임라인, 프레임 이동 버튼, 후보 갤러리를 한 화면으로 사용할 수 있습니다.
- 동영상을 한꺼번에 추가하고, 현재 동영상 처리가 끝나면 일시 정지했다가 이어서 처리할 수 있습니다. 준비된 프레임부터 미리보기에 하나씩 표시합니다.
- 3 × 3부터 8 × 8까지의 격자, 화면 비율, 배경색, 이미지 너비를 선택할 수 있습니다. 타임코드와 파일 이름도 표시할 수 있습니다.
- MP4, MOV, MPEG 등 macOS에서 지원하는 동영상 형식을 처리합니다.
- 앱을 재시작하지 않고 7개 언어를 바꿔 쓸 수 있습니다. 화면 모드는 ‘라이트’, ‘다크’, ‘시스템 설정’ 중에서 고르세요.

### 실제 사용 모습

완성된 스토리보드에서 프레임 선택 화면을 열고, 타임라인에서 원하는 순간을 찾아 후보를 고른 뒤 저장하는 과정입니다.

![Tears of Steel 스토리보드에서 프레임 선택 화면으로 이동해 타임라인과 후보 갤러리를 사용하는 ShotMap 데모](docs/assets/video-to-storyboard-demo.gif?v=tears-20261016)

## 다운로드 및 설치

[최신 국제판 릴리스](https://github.com/ixiehao/ShotMap/releases/latest)에서 범용 `.dmg` 파일을 다운로드한 뒤 **ShotMap.app**을 **응용 프로그램** 폴더로 드래그하세요. 같은 설치 파일이 Apple Silicon과 Intel Mac에서 동작하며, 7개 언어를 모두 포함합니다.

릴리스 페이지에는 다운로드 파일을 확인할 수 있는 SHA-256 체크섬이 있습니다. ShotMap은 아직 Apple의 공증을 받지 않았습니다. macOS가 개발자 확인을 요청하면 응용 프로그램 폴더에서 Control 키를 누른 채 앱을 클릭하고 **열기**를 선택한 뒤 다시 **열기**를 눌러 확인하세요. 시스템 전체의 보안 설정을 낮출 필요는 없습니다.

### 인터페이스 언어 선택

오른쪽 위 언어 메뉴에서 바로 바꿀 수 있습니다. 앱을 재시작할 필요가 없으며 작업 목록도 유지됩니다. 처음 실행할 때는 지원하는 시스템 언어를 사용하고, 해당 언어가 없으면 영어로 표시합니다. 이후에는 선택한 언어를 기억합니다.

## 동영상은 내 Mac에만

ShotMap은 계정, 추적, 클라우드 업로드를 사용하지 않습니다. Electron, FFmpeg, Python 런타임도 포함하지 않습니다. 선택 사항인 업데이트 확인은 GitHub의 공개 릴리스 정보만 읽으며, 동영상이나 사용 데이터를 전송하지 않습니다.

## 도움말, 의견 및 커뮤니티

- **처음 사용하시나요?** [공식 웹사이트](https://ixiehao.github.io/ShotMap/ko/)에서 제품 소개와 실제 화면을 확인하세요.
- **도움이 필요하거나 버그·기능을 제안하고 싶으신가요?** [지원 안내](SUPPORT.md)를 먼저 확인하세요. 재현 가능한 문제나 구체적인 기능 제안은 [Issue 양식](https://github.com/ixiehao/ShotMap/issues/new/choose)으로 보내 주세요.
- **질문이나 활용법을 나누고 싶으신가요?** [GitHub Discussions](https://github.com/ixiehao/ShotMap/discussions)에 참여하세요.
- **개발에 기여하고 싶으신가요?** [CONTRIBUTING.md](CONTRIBUTING.md)를 읽어 주세요. 보안 문제는 비공개 [취약점 신고](https://github.com/ixiehao/ShotMap/security/advisories/new)를 이용하세요.
- **프로젝트 정보:** [CHANGELOG.md](CHANGELOG.md) · [PRIVACY.md](PRIVACY.md) · [개발자: ixiehao](https://github.com/ixiehao)

## 권리 및 라이선스

- ShotMap의 Swift 소스, 문서, Iris 아이콘은 이 프로젝트의 창작물이며 [MIT 라이선스](LICENSE)로 배포합니다.
- 앱은 Apple SDK 프레임워크만 사용합니다. 타사 애플리케이션 코드, 패키지, 분석 SDK, MoviePrint 에셋을 포함하지 않습니다.
- 포함된 [Tabler Icons Outline](https://github.com/tabler/tabler-icons) SVG는 수정 없이 [MIT 라이선스](ThirdPartyLicenses/TablerIcons-MIT.txt)에 따라 사용합니다. Noto Sans CJK 글꼴은 [SIL Open Font License 1.1](ThirdPartyLicenses/NotoSansCJK-OFL-1.1.txt)을 따릅니다. 자세한 내용은 [NOTICE.md](NOTICE.md)를 참조하세요.
- 문서의 데모 영상은 *Tears of Steel*(2012) © Blender Foundation / Blender Institute이며, [CC BY 3.0](https://creativecommons.org/licenses/by/3.0/)에 따라 사용합니다.
- 직접 소유하거나 분석할 권한이 있는 동영상만 처리하세요. 스토리보드를 만들었다고 원본 동영상을 게시하거나 재배포할 권리가 생기는 것은 아닙니다.

## 개발 문서

[문서 목록](docs/README.md) · [개발 및 검증](docs/DEVELOPMENT.md) · [웹사이트 유지 관리](docs/WEBSITE.md)

공식 웹사이트 소스는 `website/`에, 개발자용 문서는 `docs/`에 있습니다.
