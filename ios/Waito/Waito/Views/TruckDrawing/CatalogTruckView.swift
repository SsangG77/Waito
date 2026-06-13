import SwiftUI

struct CatalogTruckView: View {
    let cab: TruckCab
    let truckBody: TruckBody
    let wheels: TruckWheelType
    var size: CGFloat = 100

    var body: some View {
        ZStack {
            Image(truckBody.imageName)
                .resizable()
                .interpolation(.none)
            Image(wheels.imageName)
                .resizable()
                .interpolation(.none)
            Image(cab.imageName)
                .resizable()
                .interpolation(.none)
        }
        .aspectRatio(24 / 18, contentMode: .fit)
        .frame(width: size)
    }
}

#Preview {
    VStack(spacing: 20) {
        CatalogTruckView(cab: .truckSoftBlue, truckBody: .truckExpressBlack, wheels: .standard, size: 120)
        CatalogTruckView(cab: .truckRedStack, truckBody: .containerContainer, wheels: .chrome, size: 120)
        CatalogTruckView(cab: .truckBeacon, truckBody: .truckTanker, wheels: .flame, size: 120)

        HStack(spacing: 12) {
            ForEach([TruckCab.truckBlack, .truckMint, .truckPurple, .truckNavy], id: \.self) { cab in
                CatalogTruckView(cab: cab, truckBody: .truckMovingCream, wheels: .gold, size: 60)
            }
        }
    }
    .padding(24)
    .background(Color.black)
}
