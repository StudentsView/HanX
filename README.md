# HanX

로컬 AI 에이전트가 CLI로 엑셀 파일을 읽고 수정하고 수식을 계산할 수 있는 macOS 오피스 도구입니다. GUI 앱으로 문서와 도표와 프레젠테이션을 편집하고, CLI 또는 MCP로 같은 엔진을 호출합니다.

macOS 13 이상, Apple Silicon과 Intel을 지원합니다. 현재 버전은 2.7.0입니다.

[설치와 화면 보기](https://studentsview.github.io/HanX/) | [CLI 안내](docs/cli/README.md) | [릴리스](https://github.com/StudentsView/HanX/releases)

## 설치

```sh
npm install -g @juyoungsuh/hanx
# 또는
brew install StudentsView/tap/hanx
```

앱과 CLI를 함께 설치하려면 [릴리스](https://github.com/StudentsView/HanX/releases/tag/v2.7.0)의 `HanX-2.7.0.pkg`를 사용하세요. npm과 Homebrew는 CLI를 설치합니다.

## 엑셀 CLI

```sh
hanx spreadsheet read 매출.xlsx --sheet 매출 --range A1:D10 --pretty
hanx spreadsheet eval 매출.xlsx --sheet 매출 --formula '=SUM(D2:D10)' --pretty
hanx edit 매출.xlsx --ops 작업.json --output 매출-수정.xlsx
hanx spreadsheet recalculate 매출-수정.xlsx --output 매출-계산.xlsx
```

셀 값과 수식 원문과 표시값을 JSON으로 조회합니다. SUM, IF, SUMIFS, XLOOKUP, 날짜와 텍스트 함수, LET/LAMBDA, 동적 배열을 계산합니다. 범위 쓰기, 상대 참조 수식 채우기, 서식과 숫자 형식, 시트 추가와 삭제, 이름 정의와 틀 고정을 작업 단위로 제공합니다.

언어 모델은 포함하지 않습니다. 사용 중인 로컬 에이전트가 명령을 실행하거나 `hanx mcp`의 stdio 도구를 호출합니다. 클라우드 채팅이 설치만으로 Mac 파일에 접근할 수 있게 되는 것은 아닙니다.

에이전트에게 먼저 `hanx capabilities`와 응답의 `guidePath`를 읽도록 요청하세요. 지원되는 작업과 모든 매개변수는 CLI 안내에 있습니다. 생성과 수정에는 출력 경로가 필요하며, 기존 출력은 `--force`가 있을 때만 교체합니다.

## 문서와 프레젠테이션

HWP 5, HWPX, HWPML, DOCX의 본문과 표와 기본 서식을 읽고 저장합니다. PPTX의 슬라이드와 도형과 표와 노트, 지원 전환을 편집합니다. 일반 XML과 Office 패키지의 XML도 XPath로 수정할 수 있습니다. GUI의 최근 문서 목록은 항목별 삭제와 전체 지우기를 지원하며 실제 파일을 삭제하지 않습니다.

XLSX, CSV, TSV를 지원합니다. 구형 XLS, 복잡한 피벗과 매크로와 일부 개체는 지원하지 않습니다. 계산은 Microsoft Excel 프로세스가 아닌 HanX 엔진을 사용합니다. 모델을 거쳐 저장하면 미지원 요소가 빠질 수 있으므로 복사본으로 작업하고 결과를 확인하세요. 다른 XML 파트를 유지해야 하는 수정에는 `package patch`를 사용할 수 있습니다.

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

본 제품은 한컴의 HWP 문서 파일(.hwp) 공개 문서를 참고하여 개발하였습니다.

독립 작성 소스는 [MIT 라이선스](LICENSE)로 배포합니다. [NOTICE](NOTICE), [구현과 출처](PROVENANCE.md), [법적 근거 조사](docs/legal/RESEARCH.md)를 함께 확인하세요. 한컴의 지정 출처 고지는 MIT 조건과 별도로 유지합니다.

이 프로젝트는 한글과컴퓨터, Microsoft, LibreOffice 또는 rHWP의 공식 제품이나 배포판이 아닙니다. 제휴나 승인 관계를 주장하지 않습니다. 원본 상용 실행 파일과 전용 폰트와 템플릿은 포함하지 않습니다. macOS의 시스템 카탈로그에 설치된 글꼴을 사용합니다.
