# 한워드 GitHub Pages

빌드 과정과 외부 의존성이 없는 정적 사이트입니다. GitHub Pages의 게시 대상은 이 디렉터리의 내용입니다. 하위 경로에서도 동작하도록 내부 경로는 상대 경로를 사용합니다.

## 공개 전 설정

- `config.js`의 `HANWORD_GITHUB_OWNER`, `HANWORD_NPM_PACKAGE`를 실제 값으로 바꿉니다. 저장소 이름, 버전, 라이선스 및 출처 문서 경로도 확인합니다.
- 실제 공개 설치가 확인된 채널만 `available: true`로 바꿉니다. npm과 Homebrew는 CLI 설치 명령을 제공하며, pkg는 지정한 릴리스 태그 `v<version>`의 설치 파일로 연결합니다.
- CLI 안내의 정적 HTML을 `cli/index.html`에 생성합니다. 경로가 다르면 `config.js`의 `guide`를 바꿉니다.
- 실제 앱 스크린샷을 `images/start.png`, `images/spreadsheet.png`, `images/document.png`, `images/presentation.png`에 추가합니다. 이미지를 찾지 못하면 화면 준비 상태를 표시하며 가상의 앱 화면은 만들지 않습니다. 이미지 크기는 비율을 유지하며 자동 조정됩니다.
- GitHub 저장소의 기본 브랜치가 `main`이 아니면 `site.js`의 문서 링크를 맞춥니다.

로컬 확인: 이 폴더에서 Python의 정적 HTTP 서버 등으로 실행합니다. 설치 탭은 좌우 화살표와 Home/End로 전환되며 선택한 탭 다음에 내용이 이어집니다. 복사 버튼은 Clipboard API를 우선 사용하고 지원하지 않는 환경에서는 선택 복사를 시도합니다.

외부 폰트, 분석 스크립트, 패키지 설치 과정은 없습니다.
