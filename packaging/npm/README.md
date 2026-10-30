# HanX CLI

로컬 AI 에이전트가 XLSX의 셀과 수식을 읽고 수정하고 계산하도록 연결하는 CLI입니다. HWP, DOCX, PPTX, XML도 지원합니다. macOS 13 이상, Apple Silicon과 Intel에서 실행합니다.

```sh
npm install -g @juyoungsuh/hanx
```

설치 후 `hanx --help`, `hanx capabilities --pretty`로 시작하세요. npm 설치에는 Node.js 18 이상이 필요하고, 네이티브 실행 파일은 이 패키지에 포함되어 있습니다. 설치 후 추가 바이너리를 내려받는 스크립트는 없습니다.

```sh
hanx spreadsheet read 매출.xlsx --sheet 매출 --range A1:D5 --pretty
hanx spreadsheet eval 매출.xlsx --formula '=SUM(매출!D2:D5)' --pretty
hanx edit 매출.xlsx --ops 작업.json --output 수정.xlsx
hanx mcp
```

출력 경로를 명시하며 기본적으로 원본을 덮어쓰지 않습니다. 모든 함수와 개체가 Microsoft Excel과 같은 것은 아닙니다. CLI의 capabilities 응답에서 guidePath를 읽어 전체 작업 명세와 제한을 확인하세요.

본 제품은 한컴의 HWP 문서 파일(.hwp) 공개 문서를 참고하여 개발하였습니다.

한글과컴퓨터 또는 Microsoft의 공식 제품이 아닙니다. 독립 작성 코드는 MIT 라이선스입니다. LICENSE와 NOTICE를 함께 확인하세요.

## 유지보수자

저장소 루트에서 `./build-cli.sh --universal`로 빌드하고, Developer ID로 서명한 `build/hanx-cli`를 이 폴더의 `native/hanx`로 복사합니다. CLI 안내와 예제를 `native/README.md`와 `native/examples/`로 복사한 뒤 `npm pack --dry-run`과 실제 임시 경로 설치 검사를 실행합니다. 저장소의 Tests/Distribution/test_npm.py가 설치와 JSON 응답과 MCP 연결을 확인합니다. 게시 전 패키지 버전과 실행 파일의 --version이 같아야 합니다.
