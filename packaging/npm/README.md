# HanX

로컬 AI 에이전트가 엑셀의 셀과 수식을 읽고 수정하고 계산하는 CLI와 문서 편집 앱입니다. HWP, DOCX, HWPX, PPTX, XLSX, XML과 PDF를 지원합니다.

macOS 13 이상(Apple Silicon/Intel), Windows x64, Ubuntu 22.04 이상 x64를 대상으로 합니다. npm에는 Node.js 18 이상이 필요합니다.

```sh
npm install -g @juyoungsuh/hanx
hanx setup
```

방향키와 Enter로 GUI만, CLI만, 둘 다를 선택합니다. npm이 입력을 연결하지 않는 환경에서는 CLI를 먼저 준비합니다. 앱과 CLI는 각각 필요한 파일만 내려받고 SHA256을 확인합니다.

```sh
hanx setup --components gui --yes
hanx setup --components cli --yes
hanx setup --components all --yes
hanx gui
hanx --convert
```

GUI만 설치해도 작은 설정 실행기는 남습니다. 문서 처리 CLI는 활성화하지 않으며 앱 안의 엔진은 편집과 MCP 연결에 사용합니다.

Windows/Linux의 PDF 출력에는 LibreOffice, 읽기에는 Poppler가 필요합니다. 설치 화면에서 PDF 도구를 선택하거나 `--pdf-dependencies`를 명시하면 설치를 진행합니다. macOS 기본 네이티브 배포판은 PDF 처리를 포함합니다.

```sh
hanx spreadsheet read 매출.xlsx --sheet 매출 --range A1:D5 --pretty
hanx spreadsheet eval 매출.xlsx --formula '=SUM(D2:D5)' --pretty
hanx convert 원본.hwp --output 결과.docx
hanx mcp
```

AI 모델과 외부 API 키를 포함하거나 요구하지 않습니다. 사용 중인 로컬 AI 에이전트에서 CLI 또는 MCP를 연결하세요. GUI의 AI 연결 화면에서 내부 엔진 경로와 연결 설정을 확인할 수 있습니다.

[전체 CLI 안내](https://studentsview.github.io/HanX/cli/) / [설치 파일](https://github.com/StudentsView/HanX/releases)

출력 경로를 명시하며 기본적으로 원본을 덮어쓰지 않습니다. 지원하지 않는 문서 개체와 함수가 있으므로 복사본에서 작업하고 결과를 확인하세요. PDF 입력은 텍스트 추출 방식이며 원본 배치 복원과 OCR은 지원하지 않습니다.

독립 작성 코드는 MIT 라이선스입니다. LICENSE와 NOTICE에서 구성요소별 조건을 확인하세요.
