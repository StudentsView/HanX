import Foundation
#if canImport(FoundationXML)
import FoundationXML
#endif
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Required attribution for Hancom's publicly documented file format.
/// 본 제품은 한컴의 HWP 문서 파일(.hwp) 공개 문서를 참고하여 개발하였습니다.
enum LegalNotices {
    static let hwp = "본 제품은 한컴의 HWP 문서 파일(.hwp) 공개 문서를 참고하여 개발하였습니다."
    static let independence = "이 프로젝트는 한글과컴퓨터 또는 Microsoft의 공식 제품이 아닙니다."
}
