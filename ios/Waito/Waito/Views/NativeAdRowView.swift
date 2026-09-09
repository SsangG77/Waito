import SwiftUI
import UIKit
import GoogleMobileAds

/// 택배 목록 사이에 끼는 광고 한 칸. 목록 행과 같은 픽셀 상자를 쓰되
/// "광고" 배지와 광고 선택 아이콘으로 택배 항목과 구분한다(구글·애플 정책 요구사항).
struct NativeAdRowView: View {
    @State private var loader = NativeAdLoader()

    var body: some View {
        Group {
            if let ad = loader.ad {
                NativeAdContainer(ad: ad)
                    .frame(height: 96)
                    .pixelBox(border: Color.pixelBorder, bg: Color.pixelSurface, lineWidth: 1.5, notch: 4)
                    .accessibilityIdentifier("native_ad_row")
            } else {
                // 광고가 아직 없어도 자리를 완전히 비우면 목록이 이 칸을 만들지 않아
                // 불러오기 자체가 시작되지 않는다. 눈에 안 보이는 최소 높이만 남긴다.
                Color.clear.frame(height: 1)
            }
        }
        // 동의 절차가 끝나 광고 요청이 허용되는 순간 다시 시도한다.
        .task(id: AdConsentService.shared.canRequestAds) { loader.load() }
    }
}

/// 광고 재료를 픽셀 스타일로 그린다.
/// 각 재료를 광고 뷰에 등록하고 마지막에 광고 객체를 연결해야 클릭·노출이 집계된다(SDK 요구 순서).
private struct NativeAdContainer: UIViewRepresentable {
    let ad: NativeAd

    func makeUIView(context: Context) -> NativeAdView {
        let adView = NativeAdView()
        adView.backgroundColor = .clear

        let icon = UIImageView()
        icon.contentMode = .scaleAspectFit
        icon.translatesAutoresizingMaskIntoConstraints = false
        icon.widthAnchor.constraint(equalToConstant: 44).isActive = true
        icon.heightAnchor.constraint(equalToConstant: 44).isActive = true

        let badge = UILabel()
        badge.text = " 광고 "
        badge.font = Self.font(9)
        badge.textColor = UIColor(Color.bg)
        badge.backgroundColor = UIColor(Color.pixelOrange)

        let headline = UILabel()
        headline.font = Self.font(12)
        headline.textColor = UIColor(Color.pixelText)
        headline.numberOfLines = 1

        let body = UILabel()
        body.font = Self.font(10)
        body.textColor = UIColor(Color.pixelMuted)
        body.numberOfLines = 2

        var ctaStyle = UIButton.Configuration.plain()
        ctaStyle.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)
        ctaStyle.baseForegroundColor = UIColor(Color.pixelText)
        ctaStyle.background.backgroundColor = UIColor(Color.pixelRed)
        ctaStyle.titleTextAttributesTransformer = .init { attributes in
            var updated = attributes
            updated.font = Self.font(10)
            return updated
        }

        let cta = UIButton(configuration: ctaStyle)
        // 터치는 SDK 가 처리한다 — 버튼이 직접 받으면 클릭이 집계되지 않는다
        cta.isUserInteractionEnabled = false

        let titleRow = UIStackView(arrangedSubviews: [badge, headline])
        titleRow.axis = .horizontal
        titleRow.spacing = 6
        titleRow.alignment = .center

        let textColumn = UIStackView(arrangedSubviews: [titleRow, body])
        textColumn.axis = .vertical
        textColumn.spacing = 4

        let row = UIStackView(arrangedSubviews: [icon, textColumn, cta])
        row.axis = .horizontal
        row.spacing = 10
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(top: 12, left: 14, bottom: 12, right: 14)
        row.translatesAutoresizingMaskIntoConstraints = false

        adView.addSubview(row)
        NSLayoutConstraint.activate([
            row.leadingAnchor.constraint(equalTo: adView.leadingAnchor),
            row.trailingAnchor.constraint(equalTo: adView.trailingAnchor),
            row.topAnchor.constraint(equalTo: adView.topAnchor),
            row.bottomAnchor.constraint(equalTo: adView.bottomAnchor),
        ])

        adView.iconView = icon
        adView.headlineView = headline
        adView.bodyView = body
        adView.callToActionView = cta
        return adView
    }

    func updateUIView(_ adView: NativeAdView, context: Context) {
        (adView.headlineView as? UILabel)?.text = ad.headline

        let bodyLabel = adView.bodyView as? UILabel
        bodyLabel?.text = ad.body
        bodyLabel?.isHidden = ad.body == nil

        let iconView = adView.iconView as? UIImageView
        iconView?.image = ad.icon?.image
        iconView?.isHidden = ad.icon == nil

        let cta = adView.callToActionView as? UIButton
        cta?.configuration?.title = ad.callToAction
        cta?.isHidden = ad.callToAction == nil

        // 재료를 다 채운 뒤 마지막에 연결 — 순서가 바뀌면 클릭·노출이 집계되지 않는다
        adView.nativeAd = ad
    }

    private static func font(_ size: CGFloat) -> UIFont {
        UIFont(name: "Galmuri9-Regular", size: size) ?? .systemFont(ofSize: size)
    }
}
