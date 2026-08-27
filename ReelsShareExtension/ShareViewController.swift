import ReelsKit
import UIKit
import UniformTypeIdentifiers

/// Intercepts a Reel shared from Instagram, kicks off `POST /reels`, writes the
/// job id into the App Group, and gets out of the way.
///
/// Config and networking come from ReelsKit so the extension and the app cannot
/// drift apart; see `docs/IOS_SHARE_EXTENSION_GUIDE.md` for the original outline.
final class ShareViewController: UIViewController {

    private let containerView: UIView = {
        let view = UIView()
        view.backgroundColor = UIColor.systemBackground.withAlphaComponent(0.95)
        view.layer.cornerRadius = 20
        view.layer.shadowColor = UIColor.black.cgColor
        view.layer.shadowOpacity = 0.2
        view.layer.shadowRadius = 15
        view.translatesAutoresizingMaskIntoConstraints = false
        return view
    }()

    private let spinner: UIActivityIndicatorView = {
        let indicator = UIActivityIndicatorView(style: .medium)
        indicator.translatesAutoresizingMaskIntoConstraints = false
        indicator.startAnimating()
        return indicator
    }()

    private let statusLabel: UILabel = {
        let label = UILabel()
        label.text = "인스타그램 릴스 운동 분석 중..."
        label.font = .systemFont(ofSize: 15, weight: .semibold)
        label.textColor = .label
        label.textAlignment = .center
        label.numberOfLines = 2
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }()

    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        Task { await handleShare() }
    }

    // MARK: - UI

    private func setupUI() {
        view.backgroundColor = UIColor.black.withAlphaComponent(0.4)
        view.addSubview(containerView)
        containerView.addSubview(spinner)
        containerView.addSubview(statusLabel)

        NSLayoutConstraint.activate([
            containerView.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            containerView.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            containerView.widthAnchor.constraint(equalToConstant: 260),
            containerView.heightAnchor.constraint(equalToConstant: 120),

            spinner.centerXAnchor.constraint(equalTo: containerView.centerXAnchor),
            spinner.topAnchor.constraint(equalTo: containerView.topAnchor, constant: 25),

            statusLabel.leadingAnchor.constraint(equalTo: containerView.leadingAnchor, constant: 16),
            statusLabel.trailingAnchor.constraint(equalTo: containerView.trailingAnchor, constant: -16),
            statusLabel.topAnchor.constraint(equalTo: spinner.bottomAnchor, constant: 15)
        ])
    }

    // MARK: - Flow

    private func handleShare() async {
        guard let reelURL = await extractSharedURL() else {
            return dismiss(withError: "공유 항목을 찾을 수 없습니다.")
        }

        let config: AppConfig
        do {
            config = try AppConfig.fromBundle()
        } catch {
            return dismiss(withError: "앱 설정이 완료되지 않았습니다.")
        }

        guard let identity = UserIdentityStore(appGroupID: config.appGroupID),
              let jobStore = PendingJobStore(appGroupID: config.appGroupID) else {
            return dismiss(withError: "앱 그룹에 접근할 수 없습니다.")
        }

        let fallbackEmail = config.developmentUserEmail
        let client = APIClient(config: config) { identity.email ?? fallbackEmail }

        do {
            let response = try await client.ingestReel(url: reelURL)
            jobStore.append(PendingJob(jobId: response.jobId, reelURL: reelURL))
            dismissWithSuccess()
        } catch APIError.missingUserEmail {
            dismiss(withError: "앱에서 먼저 로그인해 주세요.")
        } catch {
            dismiss(withError: error.localizedDescription)
        }
    }

    /// Instagram shares a Reel as a URL attachment, but occasionally as plain
    /// text with the link embedded — handle both.
    private func extractSharedURL() async -> String? {
        guard let item = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = item.attachments else { return nil }

        for provider in attachments {
            if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier),
               let url = try? await provider.loadItem(forTypeIdentifier: UTType.url.identifier) as? URL {
                return url.absoluteString
            }
            if provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
               let text = try? await provider.loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String,
               let url = Self.firstURL(in: text) {
                return url
            }
        }
        return nil
    }

    private static func firstURL(in text: String) -> String? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(location: 0, length: text.utf16.count)
        return detector?.matches(in: text, options: [], range: range).first?.url?.absoluteString
    }

    // MARK: - Dismissal

    private func dismissWithSuccess() {
        statusLabel.text = "✅ 분석 시작 완료!"
        spinner.stopAnimating()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil)
        }
    }

    private func dismiss(withError message: String) {
        statusLabel.text = "❌ \(message)"
        spinner.stopAnimating()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            self?.extensionContext?.cancelRequest(
                withError: NSError(domain: "ShareError", code: 1,
                                   userInfo: [NSLocalizedDescriptionKey: message])
            )
        }
    }
}
