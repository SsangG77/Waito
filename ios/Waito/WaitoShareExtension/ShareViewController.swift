//
//  ShareViewController.swift
//  WaitoShareExtension
//
//  공유시트로 받은 배송 알림 스크린샷을 App Group 컨테이너에 저장하고 Waito 앱을 연다.
//  OCR/파싱은 앱이 담당(CaptureTrackingParser 재사용) — 익스텐션은 Vision 비의존, 파일 I/O만.
//

import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    private let appGroupID = "group.com.sangjin.Waito"
    private let captureFileName = "shared_capture.dat"

    override func viewDidLoad() {
        super.viewDidLoad()
        handleSharedImage()
    }

    private func handleSharedImage() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .compactMap { $0.attachments }.flatMap { $0 } ?? []

        guard let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }) else {
            finish()
            return
        }

        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
            if let data { self?.saveToAppGroup(data) }
            DispatchQueue.main.async {
                self?.openHostApp()
                self?.finish()
            }
        }
    }

    private func saveToAppGroup(_ data: Data) {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return }
        try? data.write(to: container.appendingPathComponent(captureFileName))
    }

    /// 앱 익스텐션에서 호스트 앱 열기 — 리스폰더 체인으로 UIApplication 찾아 openURL.
    private func openHostApp() {
        guard let url = URL(string: "waito://capture") else { return }
        var responder: UIResponder? = self
        while let r = responder {
            if let app = r as? UIApplication {
                app.open(url)
                return
            }
            responder = r.next
        }
    }

    private func finish() {
        extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
    }
}
