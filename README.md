# HanX

HWP, 문서, 도표, 프레젠테이션과 모두 호환되는 새로운 macOS용 사무 도구입니다 :)
macOS 13 이상, Apple Silicon과 Intel을 지원합니다.

.pkg형 설치 GUI 프로그램 뿐만 아니라 CLI형 프로그램도 제공하며
AI 에이전트 ChatGPT, Claude 등을 이용해 모든 작업을 진행할 수 있습니다.

GUI 프로그램은 완전한 형태로 제공중이며, CLI 프로그램은 도표 함수 관련 내용만
우선적으로 호환성을 확보하여 배포중입니다.

[설치와 화면 보기](https://studentsview.github.io/HanX/) | [CLI 안내](docs/cli/README.md) | [릴리스](https://github.com/StudentsView/HanX/releases)

## 설치

CLI는 npm과 Homebrew 설치를 지원합니다. macOS 13 이상, Apple Silicon과 Intel을 지원합니다.

### npm

```sh
npm install -g @juyoungsuh/hanx
```

Node.js 18 이상이 필요합니다. [공개 npm 패키지](https://www.npmjs.com/package/@juyoungsuh/hanx)를 설치합니다.

### Homebrew

```sh
brew install StudentsView/tap/hanx
```

[공개 tap](https://github.com/StudentsView/homebrew-tap)에서 CLI를 설치하며 Node.js는 필요하지 않습니다.

### 설치 확인

어느 방법으로 설치해도 실행 명령은 같습니다.

```sh
hanx --version
hanx capabilities --pretty
```

AI 에이전트의 MCP 연결에는 `hanx mcp`를 사용합니다. [CLI 안내](docs/cli/README.md)에서 연결과 엑셀 작업 예제를 확인하세요.

### 업데이트

npm으로 설치했다면 `npm install -g @juyoungsuh/hanx`를 다시 실행합니다. Homebrew로 설치했다면 다음 명령을 실행합니다.

```sh
brew update
brew upgrade StudentsView/tap/hanx
```

### macOS 앱 설치

앱과 CLI를 함께 설치하려면 [릴리스](https://github.com/StudentsView/HanX/releases/tag/v2.7.0)의 `HanX-2.7.0.pkg`를 사용하세요. npm과 Homebrew는 CLI를 설치합니다.

## 엑셀 CLI

```sh
hanx spreadsheet read 매출.xlsx --sheet 매출 --range A1:D10 --pretty
hanx spreadsheet eval 매출.xlsx --sheet 매출 --formula '=SUM(D2:D10)' --pretty
hanx edit 매출.xlsx --ops 작업.json --output 매출-수정.xlsx
hanx spreadsheet recalculate 매출-수정.xlsx --output 매출-계산.xlsx
```

JSON을 이용해 도표 내 정보와 상호작용 하는 구조로 이루어져 있습니다. SUM, IF, SUMIFS, XLOOKUP, 날짜와 텍스트 함수, LET/LAMBDA 등의 함수 호환성을 확보하였습니다. 범위 쓰기, 상대 참조 수식 채우기, 서식과 숫자 형식, 시트 추가와 삭제, 이름 정의와 틀 고정을 작업 단위로 제공합니다.

언어 모델은 포함하지 않습니다. 사용 중인 로컬 에이전트가 명령을 실행하거나 `hanx mcp`의 stdio 도구를 호출합니다. 클라우드 채팅이 설치만으로 Mac 파일에 접근할 수 있게 되는 것은 아닙니다.

에이전트에게 먼저 `hanx capabilities`와 응답의 `guidePath`를 읽도록 요청하세요. 지원되는 작업과 모든 매개변수는 CLI 안내에 있습니다. 생성과 수정에는 출력 경로가 필요하며, 기존 출력은 `--force`가 있을 때만 교체합니다.

만약 잘 이해되지 않는 경우, 이 Github 레포를 AI 에이전트에게 링크 형태로 제공해주세요.

## 문서와 프레젠테이션

HWP, HWPX, HWPML, DOCX의 본문과 표와 기본 서식을 읽고 저장합니다. PPTX의 슬라이드와 도형과 표와 노트, 지원 전환을 편집합니다. XML도 XPath로 수정할 수 있습니다.

XLSX, CSV, TSV를 지원합니다. 구형 XLS, 복잡한 피벗과 매크로와 일부 개체는 아직 호환되지 않을 수 있습니다. 모든 연산은 자체 개발된 HanX 엔진을 사용합니다. 모델을 거쳐 저장하면 미지원 요소가 빠질 수 있으므로 복사본으로 작업하고 결과를 확인하세요. 다른 XML 파트를 유지해야 하는 수정에는 `package patch`를 사용할 수 있습니다.

## 소스에서 빌드

Xcode 또는 Swift 개발 도구가 설치된 Mac에서 실행합니다.

```sh
./build-cli.sh --universal
./build-app.sh
./install-cli.sh
```

빌드된 앱은 `build/HanX.app`입니다. 기본 빌드는 로컬 서명을 적용하며, 공개 배포에는 별도 Developer ID 서명과 공증이 필요합니다. 인증서와 공증 자격 증명은 저장소에 포함하지 않습니다.

```sh
python3 -m unittest discover -s Tests/AgentCLI
Tests/StartWindow/run.sh
Tests/run-editing.sh
build/hanx-cli formula-suite Tests/formulas.tsv
```

npm 패키지는 `packaging/npm`에서 빌드된 네이티브 실행 파일을 포함합니다. 배포판을 다시 만들 때는 해당 폴더의 설명을 따르세요. Homebrew와 pkg는 같은 엔진을 각 채널의 설치 경로에 배치합니다. 다른 방식으로 설치한 기존 명령을 자동 덮어쓰지 않습니다.

## 출처와 라이선스

독립 작성 소스는 [MIT 라이선스](LICENSE)로 배포합니다.
