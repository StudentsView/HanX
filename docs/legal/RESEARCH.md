# 공개 배포를 위한 법적 근거 조사

확인일: 2026-10-30. 이 문서는 공식 법령, 권리자의 공개 조건, 프로젝트 자체 문서와 로컬 소스에서 확인한 사실을 구분한다. 공개 가능성을 확정하는 법률 의견이나 프로젝트의 라이선스 부여 문서가 아니다. 아래 라이선스 비교는 초기 조사 당시의 선택지를 기록한다. 현재 공개 준비본의 MIT 선택과 출처 고지는 마지막 절과 루트 LICENSE 및 NOTICE에 정리했다.

## 가장 직접적인 근거: 한컴의 공개 명세 사용 조건

한컴은 HWP 5.0과 HWPML 등의 명세를 공개하고, 명세를 참고해 개발한 결과물의 저작권은 개발한 개인 또는 단체에 있다고 설명한다. 다음 문구를 결과물의 UI, 매뉴얼, 도움말 및 소스 중 존재하는 구성물 모두에 표시하도록 요구한다.


명세 문서 자체의 배포는 내용을 수정하지 않은 원본 또는 복사본으로 제한하며 최신 버전을 포함하도록 한다. 결과물에 근거한 독점적 권리를 한컴에 행사하는 경우 권리행사를 할 수 있다는 조건도 명시한다. 개발 결과물의 사용 조건과 명세 PDF 자체의 복제 조건을 분리해야 한다. 배포 저장소에는 명세 링크를 제공하고 원문 전체의 복제를 피하는 편이 관리하기 쉽다. [한컴 공식 공개 조건](https://www2.hancom.com/support/downloadCenter/hwpOwpml)

현재 소스의 HWP5Reader는 한컴의 공개 명세로 작성했다는 주석이 있고 README도 공개 명세를 구현 근거로 설명한다. 그러나 확인 당시 위 한컴 요구 문구는 README, CLI 안내, Sources, Resources에서 발견되지 않았다. 연구 문서에 넣는 것만으로 UI와 도움말 등의 표시 요구가 모두 충족되지는 않는다.

## LibreOffice가 실제로 한 일

LibreOffice의 공식 라이선스 안내는 현재 배포를 MPL 2.0으로 설명한다. Apache OpenOffice의 Apache 2.0 코드와 여러 다른 라이선스의 구성요소를 포함하므로 실제 파일과 배포판의 LICENSE를 확인하도록 한다. 새 기여에는 MPL 2.0과 LGPL v3 이상으로 함께 이용허락할 것을 요청하며 저작권 양도는 요구하지 않는다. 이 구조는 한글 또는 Office 상용 코드의 복제 허락을 뜻하지 않는다. [LibreOffice 공식 안내](https://www.libreoffice.org/licenses/)

The Document Foundation은 파일 형식 분석과 별도 변환 라이브러리 개발을 공개적으로 설명한다. 예를 들어 Document Liberation Project는 역공학한 Publisher 형식을 읽는 libmspub를 만들었고 LibreOffice가 이를 이용한다. 공식 개발 블로그의 mso-dumper 설명은 DOC, PPT, XLS 등의 문서 바이너리 구조를 덤프하여 분석하는 도구를 소개한다. 이는 파일을 관찰하고 독립 파서를 작성한 구체적인 실무 근거다. 조사한 자료에서는 모든 상용 앱 분석에 일괄 적용되는 법적 승인이나 HanX와 같은 분석에 대한 법원 판단을 확인하지 못했다. [TDF의 libmspub 설명](https://blog.documentfoundation.org/blog/2026/10/14/libreoffice-come-to-the-rescue-of-microsoft-publisher-users/), [공식 mso-dumper 설명](https://dev.blog.documentfoundation.org/2022/04/26/supporting-metafile-formats-wmf-emf-emfplus/)

LibreOffice hwpfilter의 README는 새로운 HWP 형식을 올바르게 처리하지 못하고 조용히 손상시킬 수 있다고 경고한다. 따라서 LibreOffice의 존재를 HanX의 HWP 5 호환성이나 법적 적합성의 증명으로 제시하면 안 된다. 실제 hwpfile.cxx 헤더에는 MPL 2.0과 기존 Apache 라이선스 관련 고지가 함께 있다. 이 코드를 가져오거나 번역한다면 각 파일의 조건을 따라야 한다. [hwpfilter README](https://github.com/LibreOffice/core/blob/master/hwpfilter/README.md), [실제 소스 헤더](https://github.com/LibreOffice/core/blob/master/hwpfilter/source/hwpfile.cxx)

## rHWP가 실제로 설명한 근거와 한계

주된 조사 대상은 edwardkim/rhwp다. ic4u2u/rHWP의 README 역시 이 원본 프로젝트의 링크를 사용한다. 원본의 LICENSE는 Edward Kim의 저작권 고지와 MIT 조건을 담는다. 재사용 시 해당 저작권 고지와 이용허락 문구를 유지해야 한다. 자체 LICENSE와 별도로 THIRD_PARTY_LICENSES.md에서 Rust, npm, 폰트 등 구성요소를 관리한다. MIT 표지만으로 모든 자산의 조건이 없어지는 것은 아니다. [rHWP LICENSE](https://github.com/edwardkim/rhwp/blob/main/LICENSE), [서드파티 목록](https://github.com/edwardkim/rhwp/blob/main/THIRD_PARTY_LICENSES.md)

rHWP의 2026-04-09 Legal FAQ는 한컴 공개 명세를 바탕으로 개발했고 실제 HWP 파일을 분석해 명세 불일치를 보정했다고 설명한다. 한국 저작권법 제101조의4, 미국 DMCA 1201(f), EU 소프트웨어 지침 제6조를 근거로 들지만 이는 프로젝트의 입장이다. FAQ의 짧은 법률 요약은 한국법의 정당한 이용권, 정보 획득의 불가피성, 필요한 부분으로의 제한을 모두 전달하지 않는다. 따라서 그 문서를 그대로 HanX의 적법성 결론으로 인용할 수 없다. 실제 정오표는 검증 방법과 수정 파일을 기록한다. [Legal FAQ](https://github.com/edwardkim/rhwp/wiki/Legal-FAQ), [정오표](https://github.com/edwardkim/rhwp/blob/main/mydocs/tech/hwp_spec_errata.md)

같은 FAQ는 초기에 포함했던 상용 폰트 83개를 Git 기록에서 제거하고 릴리스를 다시 만든 조치를 공개한다. 배포에는 공개 라이선스 폰트만 사용한다고 설명한다. README에는 한컴 공개 명세 출처와 제휴 또는 승인 관계가 없다는 고지가 있다. 이 사례의 실질적 교훈은 라이선스 이름보다 자산별 출처와 배포 기록까지 관리해야 한다는 점이다. [rHWP README](https://github.com/edwardkim/rhwp/blob/main/README.md), [폰트 조치 기록](https://github.com/edwardkim/rhwp/wiki/Legal-FAQ)

## 한국법상 호환성 분석의 범위

2026-10-29 시행 저작권법 제101조의3 제1항 제6호는 정당한 이용자가 이용 중 프로그램의 아이디어와 원리를 확인하기 위해 기능을 조사, 연구, 시험하는 경우의 복제를 규정한다. 제101조의4는 정당한 이용권이 있는 자 또는 그 허락을 받은 자에 대해, 호환 정보를 쉽게 구할 수 없고 획득이 불가피할 때 필요한 프로그램 부분에 한정한 코드 역분석을 허용한다. 얻은 정보의 호환 외 목적 이용이나 제공, 표현이 실질적으로 유사한 프로그램 제작 등에 대한 제한도 있다. 공개 명세로 얻을 수 있는 정보와 추가 분석이 꼭 필요했던 정보를 나눠 기록할 이유가 여기에 있다. [현행 공식 조문](https://law.go.kr/lsLinkCommonInfo.do?lsJoLnkSeq=1025203515)

문서 파일 자체의 구조 관찰, 정당한 실행 중 기능 시험, 상용 실행 파일의 코드 또는 UI 자원 분석은 서로 다른 사실관계다. 파일 호환성이 목적이라는 설명만으로 리본 UI 모사나 전체 앱 구조 분석까지 전부 제101조의4 요건에 해당한다고 단정할 수 없다. 이용권, 실제 분석 범위, 공개 정보로 부족했던 이유 및 구현에 옮긴 정보를 개별적으로 확인해야 한다.

미국 17 USC 1201(f)도 적법한 프로그램 이용권과 독립 프로그램의 상호운용성에 필요한 공개되지 않은 요소를 대상으로 하는 조건부 예외다. EU 지침 제5조 제3항과 제6조 역시 정당한 이용, 필요한 범위 및 정보의 사용 제한을 둔다. 한국에서 개발했다는 이유만으로 해외 배포 전반의 계약, 상표, 특허 문제까지 해결하는 조항은 아니다. [미국 공식 법전](https://uscode.house.gov/us/usc/119-124/t17/s1201/), [EU 공식 지침](https://eur-lex.europa.eu/legal-content/EN/ALL/?uri=CELEX%3A32009L0024)

OOXML은 공개 명세와 Microsoft의 Open Specifications 조건을 별도로 확인할 수 있다. 명세의 저작권 허락과 특허 약속은 다르다. OSP는 명시된 규격과 필요한 청구항에 대한 조건부 약속이며 상표나 타사의 특허 전체를 포괄하지 않는다. 실제 구현한 규격과 판을 대조해야 한다. [Microsoft OSP](https://learn.microsoft.com/en-us/openspecs/dev_center/ms-devcentlp/1c24c7c8-28b0-4ce1-a47d-95fe1ff504bc), [MS-PPTX의 권리 고지](https://learn.microsoft.com/en-us/openspecs/office_standards/ms-pptx/efd8bb2d-d888-4e2e-af25-cad476730c9f)

## 공개 준비 전 검사에서 확인한 항목

- README와 docs/rea/README.md는 상용 앱 바이너리와 전환 자원을 복사하지 않았다고 설명한다. REA 기록은 실행 파일 정보와 일부 Interface Builder 객체를 분석한 기록이며 Hopper 함수 분석은 시간 초과였다. 이 설명과 기록은 완전한 소스 기원 감사 또는 분석자와 구현자를 분리한 clean-room 절차의 증명이 아니다.
- 빌드 스크립트는 Swift 소스 파일을 직접 컴파일한다. 확인한 import는 Apple 또는 시스템 프레임워크이며 외부 패키지나 LibreOffice/rHWP 연결 의존성은 발견되지 않았다. 링크 의존성이 없다는 사실만으로 복사한 코드가 전혀 없음을 증명하지는 못한다. Sources의 Swift 파일에서 저작권 헤더도 발견되지 않아 기여자와 참고 출처를 별도로 정리해야 한다.
- Resources에는 아이콘, Info.plist, 설치 안내 HTML이 있다. Tools/make-icon.swift는 시스템 글꼴과 도형으로 아이콘을 그리는 로컬 생성 코드를 제공한다. 실제 배포 아이콘이 이 코드로 생성되었는지는 빌드 이력 또는 재생성 비교로 확인할 수 있다.
- 초기 FontResolver.swift는 사용자의 설치된 한컴 앱과 Word 앱 번들에서 폰트를 찾아 프로세스에 등록한다. 확인한 소스 Resources에 폰트 파일은 없지만 다른 앱 전용 폰트의 사용권 확인은 별도 문제다. Microsoft의 Windows 폰트 FAQ도 다른 앱과 함께 제공된 폰트는 해당 이용약관을 보라고 구분한다. 시스템 또는 적법하게 설치한 공개 폰트를 기본값으로 쓰는 방식이 관리하기 쉽다. [Microsoft 폰트 FAQ](https://learn.microsoft.com/en-us/typography/fonts/font-faq)
- Tests/samples/brochure.hwp와 writ01.hwp의 제작자 및 재배포 허락을 확인할 문서가 발견되지 않았다. 침해라고 단정할 수 없지만 공개 패키지에는 허락이 확인된 자체 제작 샘플만 포함해야 한다.
- 초기 PPTXWriter.swift의 Office 테마 XML과 HWP5Writer.swift에서 언급한 Normal.hwt 및 CLEAN011.hwt 관찰의 기원을 기록해야 한다. 형식 상수나 호환성 관찰과 기존 문서의 창작적 테마 또는 템플릿 자원 복제를 구분해야 한다. 현재 검사로 복제 여부는 확정할 수 없다.
- 원시 REA evidence JSON에는 상용 UI 자원의 디코딩 구조가 들어 있다. 공개 소스 패키지에서는 우선 제외하고 공개 명세 링크, 필요한 호환성 사실, 새 구현 설명을 담은 요약만 배포하는 것을 권한다. 필요한 분석 기록은 비공개 근거로 보관할 수 있다.
- 한컴 공식 지원 페이지는 기존 서비스 이름으로 이미 한워드를 사용한다. 이 프로젝트는 공개 이름을 HanX로 변경했다. 이전 프로젝트 이름인 한워드/HanWord와 HanX의 상표 등록 여부나 침해 여부는 이 조사로 확정하지 않았다. 비제휴 고지는 혼동 위험을 완전히 없애는 허락이 아니다. [한컴 공식 사용 안내](https://support.hancomdocs.com/d53fda05-422a-475c-b2a2-35dce5962e62)

## 출처 확인 후 선택할 배포 라이선스

1. MIT: CLI와 네이티브 라이브러리의 넓은 재사용을 원하고 간단한 조건을 선호할 때 적합하다. 복사 또는 상당 부분 사용 시 저작권과 허락 고지를 보존해야 한다. rHWP와 같은 선택이지만 그 사실 자체가 HanX의 소스 권리를 입증하지 않는다. [MIT 원문](https://opensource.org/license/mit)
2. Apache 2.0: 상업적 재사용을 열어 두면서 기여자의 명시적인 특허 허락과 특허 소송 관련 조건을 원할 때 검토할 선택이다. 라이선스 사본, 변경 고지, 적용되는 출처 및 NOTICE 보존 요건을 관리한다. 기여자에게 없는 한컴 또는 Microsoft 권리를 새로 부여하지 않는다. [Apache 2.0 원문](https://www.apache.org/licenses/LICENSE-2.0)
3. MPL 2.0: 수정한 대상 파일을 배포할 때 그 파일의 소스 공개를 유지하고 별도 파일로 된 다른 구성요소와 결합할 수 있도록 하려면 검토한다. 실행 파일 배포 시 해당 소스를 구하는 방법도 안내한다. LibreOffice 코드를 실제 포함했다면 이 파일별 의무 등을 먼저 판별해야 하며 루트에 MIT를 붙여 대체할 수 없다. [MPL 2.0 원문](https://www.mozilla.org/en-US/MPL/2.0/)

관리 부담과 CLI 재사용이 우선이면 MIT, 기여자의 명시적 특허 허락을 중시하면 Apache 2.0, 수정한 코어 파일의 공개 유지를 원하면 MPL 2.0을 우선 비교하는 것을 권한다. 선택 전에 사용자와 실제 기여자의 권리, 고용 또는 계약에 따른 귀속, 참고하거나 가져온 코드 및 리소스의 조건을 확인한다. LICENSE의 저작권자 이름이나 연도를 추측해 채우지 않는다.

공개 준비본에는 고른 LICENSE, 실제 사용한 항목만 담은 출처 고지, 한컴 요구 문구, 독립 프로젝트 설명, 검증된 자체 샘플이 필요하다. 이 조사만으로 저작권 귀속이나 최종 라이선스를 설정하지 않았고 외부에 게시하지 않았다.

## 이번 공개 준비본에 적용한 조치

독립 작성 코드에는 MIT를 선택하고 LICENSE와 NOTICE를 추가했다. 한컴의 지정 문구는 소스, CLI 도움말과 capabilities, 사용 안내, 앱 정보의 Credits와 설치 안내에 표시한다. 원시 REA 자료와 허락이 확인되지 않은 HWP 샘플은 공개 준비본의 포함 목록에서 제외했다. 다른 앱 번들의 전용 폰트 자동 등록을 제거했으며 새 PPTX 기본 테마는 자체 색 구성과 시스템 글꼴 이름을 사용한다. 이 조치는 위 조사에서 미확인으로 표시한 모든 소스의 권리를 확정한다는 뜻은 아니다.
