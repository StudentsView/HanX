# HanX 2.9

로컬 문서 GUI, CLI 및 MCP 도구입니다. macOS, Windows, Linux용으로 빌드된 네이티브 엔진을 사용합니다. npm 설치에는 Node.js 18 이상이 필요합니다.

```sh
npm install -g @juyoungsuh/hanx
hanx setup
```

`hanx setup`은 실제 터미널에서 ↑/↓와 Enter로 **CLI only / GUI only / GUI + CLI**를 선택합니다. 취소는 Esc 또는 Ctrl-C입니다. npm은 설치 스크립트의 입력을 연결하지 않는 경우가 많으므로 설치가 끝나면 직접 `hanx setup`을 실행하세요. 입력이 연결되지 않은 설치는 CLI만 선택하며 GUI를 내려받지 않습니다. 자동화에서는 다음처럼 선택합니다.

```sh
hanx setup --components cli --yes
hanx setup --components gui --yes
hanx setup --components all --yes
hanx gui
```

GUI only는 터미널 문서 명령을 비활성화하고 따로 내려받았던 CLI를 제거합니다. `hanx setup`과 `hanx gui`를 위한 작은 npm 실행기는 남습니다. npm 패키지 또는 Homebrew가 관리하는 원본 파일은 유지되며 GUI는 자체 내부 엔진을 포함합니다. CLI only는 GUI를 설치하지 않습니다. 기존 GUI 앱은 삭제하지 않습니다.

런처는 정확한 운영체제와 아키텍처의 동봉 파일, 설치된 선택적 플랫폼 패키지, 검증한 GitHub 릴리스 CLI 순으로 찾습니다. 파일이 없으면 같은 버전의 공식 릴리스에서 내려받고 SHA-256을 확인한 뒤 설치합니다. 잘못된 체크섬, 손상된 매니페스트, 지원하지 않는 아키텍처에서는 설치를 중단합니다. 기존 GUI 또는 다른 버전의 설치 파일을 덮어쓰지 않습니다. macOS universal 바이너리는 Apple Silicon과 Intel 모두에서 사용할 수 있습니다. 실제 릴리스가 없는 아키텍처는 명확한 오류를 반환합니다.

GUI 설치 위치는 macOS `~/Applications/HanX.app`, Windows 사용자별 `Programs/HanX`, Linux 사용자별 AppImage 및 앱 메뉴입니다. Linux에서는 관리자 권한을 자동 요청하지 않습니다. AppImage 실행에 FUSE가 필요하면 배포판의 libfuse2를 직접 설치하거나 `.deb` 릴리스를 선택하세요. Windows 설치 마법사에서도 GUI/CLI/둘 다를 고를 수 있습니다.

```sh
hanx --help
hanx capabilities --pretty
hanx spreadsheet read 매출.xlsx --sheet 매출 --range A1:D5 --pretty
hanx spreadsheet eval 매출.xlsx --formula '=SUM(매출!D2:D5)' --pretty
hanx edit 매출.xlsx --ops 작업.json --output 수정.xlsx
hanx mcp
```

PDF 렌더링은 선택적 로컬 LibreOffice와 Poppler가 필요할 수 있습니다. `hanx capabilities --pretty`로 현재 사용 가능한 도구를 확인하세요. `hanx setup --pdf-dependencies --components cli --yes`는 필요한 도구의 설치 안내만 표시하며 추가 프로그램을 자동 설치하지 않습니다. Windows에서 런타임 오류가 나타나면 Microsoft의 공식 Visual C++ 2015–2022 재배포 패키지를 직접 설치하세요.

출력 경로를 명시하며 기본적으로 원본을 덮어쓰지 않습니다. 모든 함수와 개체가 Microsoft Excel과 같은 것은 아닙니다. CLI의 capabilities 응답에서 guidePath를 읽어 전체 작업 명세와 제한을 확인하세요.

한글과컴퓨터 또는 Microsoft의 공식 제품이 아닙니다. 독립 작성 코드는 MIT 라이선스입니다. LICENSE와 NOTICE를 함께 확인하세요.

## Maintainers

Run `npm test` here. Native payload trees are `native/<platform>-<architecture>/`, with the legacy macOS universal payload at `native/hanx`. Keep complete adjacent runtime libraries. `build-platform-packages.js` can create optional platform packages from real staged payloads; publish those before adding optionalDependencies to the bootstrap package. An unpublished platform package is not required: the verified same-version GitHub archive is the fallback.

The release includes `hanx-install-manifest.json` with `{ "version": "2.9.0", "assets": [{ "component": "cli", "platform": "linux", "arch": "x64", "name": "HanX-CLI-2.9.0-linux-x64.tar.gz", "sha256": "...64 hex characters..." }] }`, or a standard `SHA256SUMS` file. URLs always come from the pinned StudentsView/HanX release, never from manifest-provided URLs. Missing or malformed metadata fails closed. Do not publish an asset manifest until every referenced artifact has passed its native smoke tests.

Homebrew uses a small `HanX-Setup-2.9.0.tar.gz` containing `bin/`, `lib/`, and `package.json` from this directory. Its formula retains checksum verification for both native and setup archives. Windows Homebrew is unsupported upstream; use npm or the NSIS installer. Native CI builds Windows x64 and Linux x64; arm64 availability is determined by actual release artifacts.
