import Foundation

public enum APIError: Error, Sendable {
    /// `x-app-secret` rejected, or the email is not in `ALLOWED_USER_EMAILS`.
    case forbidden
    case notFound
    case missingUserEmail
    case badURL(String)
    case http(status: Int, body: String?)
    case transport(any Error)
    case decoding(any Error)
}

extension APIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .forbidden:
            "이 계정은 허용 목록에 없거나 앱 시크릿이 올바르지 않습니다."
        case .notFound:
            "요청한 항목을 찾을 수 없습니다."
        case .missingUserEmail:
            "로그인이 필요합니다."
        case .badURL(let path):
            "잘못된 요청 주소입니다: \(path)"
        case .http(let status, let body):
            "서버 오류 (\(status))" + (body.map { ": \($0)" } ?? "")
        case .transport(let error):
            "네트워크 오류: \(error.localizedDescription)"
        case .decoding:
            "서버 응답을 해석하지 못했습니다."
        }
    }
}
