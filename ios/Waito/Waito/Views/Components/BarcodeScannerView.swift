import SwiftUI
import VisionKit

/// 송장 바코드 스캐너 — 택배 추가 폼에서 운송장 번호를 카메라로 읽는다.
///
/// VisionKit DataScanner 래핑. 바코드(1D/QR)를 인식하면 payload 문자열을 넘기고 닫는다.
/// 시뮬레이터/카메라 미지원 기기는 `isSupported` 가 false — 호출부에서 버튼을 숨긴다.
struct BarcodeScannerView: UIViewControllerRepresentable {
    /// 인식된 바코드 문자열 (운송장 번호)
    let onScan: (String) -> Void

    static var isSupported: Bool {
        DataScannerViewController.isSupported && DataScannerViewController.isAvailable
    }

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode()],   // 모든 심볼로지(code128·code39·EAN·QR 등)
            qualityLevel: .balanced,
            recognizesMultipleItems: false,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var didScan = false   // 한 번 인식하면 이후 콜백 무시(중복 방지)

        init(onScan: @escaping (String) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(_ dataScanner: DataScannerViewController, didAdd addedItems: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !didScan else { return }
            for item in addedItems {
                if case .barcode(let barcode) = item, let payload = barcode.payloadStringValue {
                    didScan = true
                    dataScanner.stopScanning()
                    onScan(payload)
                    return
                }
            }
        }
    }
}

/// 스캐너 시트 — 상단 안내 + 닫기 버튼을 얹은 풀스크린 카메라
struct BarcodeScannerSheet: View {
    @Environment(\.dismiss) private var dismiss
    let onScan: (String) -> Void

    var body: some View {
        ZStack(alignment: .top) {
            BarcodeScannerView { payload in
                onScan(payload)
                dismiss()
            }
            .ignoresSafeArea()

            HStack {
                Text("송장 바코드를 비춰주세요")
                    .font(pixelFont(12))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("barcode_scanner_close")
            }
            .padding(16)
        }
        .accessibilityIdentifier("barcode_scanner_sheet")
    }
}
