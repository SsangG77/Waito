//
//  ShareViewController.swift
//  WaitoShareExtension
//
//  공유시트로 받은 배송 알림 스크린샷(이미지) 또는 문자·카톡 텍스트를 App Group 에 저장하고
//  Waito 앱을 연다. OCR/파싱은 앱이 담당(CaptureTrackingParser 재사용) — 익스텐션은 저장만.
//

import UIKit
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    private let appGroupID = "group.com.sangjin.Waito"
    private let captureFileName = "shared_capture.dat"
    private let sharedTextKey = "shared_text"

    override func viewDidLoad() {
        super.viewDidLoad()
        handleShared()
    }

    private func handleShared() {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem])?
            .compactMap { $0.attachments }.flatMap { $0 } ?? []

        // 1) 이미지 (배송 알림 스크린샷)
        if let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.image.identifier)
        }) {
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
                if let data { self?.saveImageToAppGroup(data) }
                DispatchQueue.main.async {
                    self?.openHostApp()
                    self?.finish()
                }
            }
            return
        }

        // 2) 텍스트 (문자·카톡 내용 공유)
        if let provider = providers.first(where: {
            $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)
        }) {
            provider.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, _ in
                let text = (item as? String)
                    ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
                if let text, !text.isEmpty { self?.saveTextToAppGroup(text) }
                DispatchQueue.main.async {
                    self?.openHostApp()
                    self?.finish()
                }
            }
            return
        }

        finish()
    }

    private func saveImageToAppGroup(_ data: Data) {
        guard let container = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID) else { return }
        try? data.write(to: container.appendingPathComponent(captureFileName))
    }

    private func saveTextToAppGroup(_ text: String) {
        UserDefaults(suiteName: appGroupID)?.set(text, forKey: sharedTextKey)
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
