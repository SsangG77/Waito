import Foundation

// 픽셀 카탈로그 — 트럭/탱크/기차/건설 부품을 자유 조합한다.
// rawValue = 에셋 카탈로그(PixelCatalog)의 imageset 이름과 정확히 일치 → imageName 은 rawValue 그대로.
// 무료(비구독)는 각 부위의 기본 1종만, 나머지는 Waito Plus 필요.

// MARK: - TruckCab (앞부분: 트럭 헤드 / 탱크 포신 / 기관차 / 건설 암)

enum TruckCab: String, CaseIterable, Codable, Hashable {
    // 🚚 트럭 헤드
    case truckCream        = "01_TruckHead_Cream"
    case truckSoftBlue     = "02_TruckHead_SoftBlue"
    case truckNavy         = "03_TruckHead_Navy"
    case truckRedStack     = "04_TruckHead_RedStack"
    case truckBlack        = "05_TruckHead_Black"
    case truckOrangeBar    = "06_TruckHead_OrangeBar"
    case truckMint         = "07_TruckHead_Mint"
    case truckBeacon       = "08_TruckHead_Beacon"
    case truckGreen        = "09_TruckHead_Green"
    case truckPurple       = "10_TruckHead_Purple"
    case truckPink         = "11_TruckHead_Pink"
    case truckBrown        = "12_TruckHead_Brown"
    // 🪖 탱크 포신
    case tankGunStandard   = "13_TankGun_GunStandard"
    case tankGunLong       = "14_TankGun_GunLong"
    case tankGunHowitzer   = "15_TankGun_GunHowitzer"
    // 🚆 기관차
    case trainLocoSteam    = "16_Train_LocoSteam"
    case trainLocoDiesel   = "17_Train_LocoDiesel"
    case trainLocoElectric = "18_Train_LocoElectric"
    case trainLocoBullet   = "19_Train_LocoBullet"
    case trainLocoFunnel   = "20_Train_LocoFunnel"
    case trainLocoMetro    = "21_Train_LocoMetro"
    // 🏗️ 건설 암
    case constArmExcavator    = "22_Construction_ArmExcavator"
    case constArmCrane        = "23_Construction_ArmCrane"
    case constArmConcretePump = "24_Construction_ArmConcretePump"
    case constArmBreaker      = "25_Construction_ArmBreaker"
    case constArmTelehandler  = "26_Construction_ArmTelehandler"
    case constArmCherryPicker = "27_Construction_ArmCherryPicker"

    var imageName: String { rawValue }
    var displayName: String { catalogDisplayName(rawValue) }
    /// 무료 개방 = 트럭 헤드 일부만. 탱크 포신·기관차·건설 암은 모두 Plus.
    static let freeCases: Set<TruckCab> = [.truckSoftBlue, .truckCream]
    var requiresPlus: Bool { !Self.freeCases.contains(self) }
}

// MARK: - TruckBody (짐칸: 트럭 / 컨테이너 / 탱크로리 / 탱크 포탑 / 기차 차량 / 건설 차체)

enum TruckBody: String, CaseIterable, Codable, Hashable {
    // 🚚 트럭 바디
    case truckOrangeBox    = "01_Truck_OrangeBox"
    case truckMovingCream  = "02_Truck_MovingCream"
    case truckReefer       = "03_Truck_Reefer"
    case truckSemiStrapped = "04_Truck_SemiStrapped"
    case truckExpressBlack = "05_Truck_ExpressBlack"
    case truckFlatbed      = "06_Truck_Flatbed"
    case truckTanker       = "07_Truck_Tanker"
    case truckFoodTruck    = "08_Truck_FoodTruck"
    case truckDumpBody     = "09_Truck_DumpBody"
    case truckGarbage      = "10_Truck_Garbage"
    case truckLoadedBoxes  = "11_Truck_LoadedBoxes"
    // 📦 컨테이너
    case containerContainer = "12_Container_Container"
    case containerStacked   = "13_Container_StackedContainers"
    case containerOpenTop   = "14_Container_OpenTopContainer"
    case containerReefer    = "15_Container_ReeferContainer"
    // 🛢️ 탱크로리
    case liquidMilk = "16_LiquidTank_MilkTank"
    case liquidFuel = "17_LiquidTank_FuelTank"
    case liquidGas  = "18_LiquidTank_GasTank"
    // 🪖 탱크 포탑
    case tankTurretOlive  = "19_Tank_TurretOlive"
    case tankTurretDesert = "20_Tank_TurretDesert"
    case tankTurretHeavy  = "21_Tank_TurretHeavy"
    // 🚆 기차 차량
    case trainPassenger = "22_Train_TrainPassenger"
    case trainBoxcar    = "23_Train_TrainBoxcar"
    case trainTankCar   = "24_Train_TrainTankCar"
    case trainHopper    = "25_Train_TrainHopper"
    case trainFlatcar   = "26_Train_TrainFlatcar"
    case trainCaboose   = "27_Train_TrainCaboose"
    // 🏗️ 건설 차체
    case constExcavatorHouse = "28_Construction_ExcavatorHouse"
    case constCraneBase      = "29_Construction_CraneBase"
    case constMixerDrum      = "30_Construction_MixerDrum"
    case constDumpBed        = "31_Construction_DumpBed"
    case constDozerBody      = "32_Construction_DozerBody"
    case constRollerFrame    = "33_Construction_RollerFrame"

    var imageName: String { rawValue }
    var displayName: String { catalogDisplayName(rawValue) }
    /// 무료 개방 = 트럭 바디 일부만. 컨테이너·탱크로리(물탱크)·탱크 포탑·기차 차량·건설 차체는 모두 Plus.
    static let freeCases: Set<TruckBody> = [.truckExpressBlack, .truckOrangeBox, .truckMovingCream]
    var requiresPlus: Bool { !Self.freeCases.contains(self) }
}

// MARK: - TruckWheelType (바퀴: 트럭 / 탱크 궤도 / 기차 바퀴 / 건설 궤도·바퀴)

enum TruckWheelType: String, CaseIterable, Codable, Hashable {
    // 🚚 트럭 바퀴
    case standard  = "01_Wheels_Standard"
    case chrome    = "02_Wheels_Chrome"
    case gold      = "03_Wheels_Gold"
    case redRim    = "04_Wheels_RedRim"
    case mud       = "05_Wheels_Mud"
    case spoked    = "06_Wheels_Spoked"
    case whiteWall = "07_Wheels_WhiteWall"
    case heavyDuty = "08_Wheels_HeavyDuty"
    case offRoad   = "09_Wheels_OffRoad"
    case mini      = "10_Wheels_Mini"
    case neon      = "11_Wheels_Neon"
    case flame     = "12_Wheels_Flame"
    // 🪖 탱크 궤도
    case tankTrackSteel  = "13_TankTrack_TrackSteel"
    case tankTrackDesert = "14_TankTrack_TrackDesert"
    case tankTrackHeavy  = "15_TankTrack_TrackHeavy"
    // 🚆 기차 바퀴
    case trainWheels    = "16_Train_TrainWheels"
    case trainDrivers   = "17_Train_TrainDrivers"
    case trainBogie     = "18_Train_TrainBogie"
    case trainSubway    = "19_Train_TrainSubway"
    case trainBulletLow = "20_Train_TrainBulletLow"
    case trainFreight   = "21_Train_TrainFreight"
    // 🏗️ 건설 궤도·바퀴
    case constTrack        = "22_ConstructionTrack_ConstTrack"
    case constLoaderTires  = "23_ConstructionTrack_ConstLoaderTires"
    case constCraneCarrier = "24_ConstructionTrack_ConstCraneCarrier"
    case constRollerDrum   = "25_ConstructionTrack_ConstRollerDrum"
    case constDozerTrack   = "26_ConstructionTrack_ConstDozerTrack"
    case const6Wheel       = "27_ConstructionTrack_Const6Wheel"

    var imageName: String { rawValue }
    var displayName: String { catalogDisplayName(rawValue) }
    /// 무료 개방 = 트럭 바퀴 일부만. 탱크 궤도·기차 바퀴·건설 궤도는 모두 Plus.
    static let freeCases: Set<TruckWheelType> = [.standard, .chrome]
    var requiresPlus: Bool { !Self.freeCases.contains(self) }
}

// MARK: - 표시 이름 (UI 미사용이지만 디버그/추후 대비) — "01_TruckHead_Cream" → "Cream"
private func catalogDisplayName(_ rawValue: String) -> String {
    let parts = rawValue.split(separator: "_")
    return parts.count >= 3 ? parts.dropFirst(2).joined(separator: " ") : rawValue
}

// MARK: - 부품 등급(Tier) & 포인트 해제

enum PartTier {
    case free            // 무료 기본 제공
    case pointUnlockable // 배송완료 포인트로 해제 가능 (트럭 계열 추가 부품)
    case plusOnly        // Waito Plus 전용 — 포인트로 불가 (탱크·기차·물탱크·건설·컨테이너)
}

/// 부품 1개 해제 비용(포인트). 배송완료 1건 = 1포인트.
let pointUnlockCost = 3

/// 포인트로 해제 가능한 계열 토큰(에셋명 2번째 segment). 그 외 비무료 부품은 Plus 전용.
/// cab=TruckHead / body=Truck / wheel=Wheels 만 포인트 대상.
private let pointUnlockableFamilies: Set<String> = ["TruckHead", "Truck", "Wheels"]

private func catalogFamilyToken(_ rawValue: String) -> String {
    let parts = rawValue.split(separator: "_")
    return parts.count >= 2 ? String(parts[1]) : ""
}

private func partTier(rawValue: String, isFree: Bool) -> PartTier {
    if isFree { return .free }
    return pointUnlockableFamilies.contains(catalogFamilyToken(rawValue)) ? .pointUnlockable : .plusOnly
}

extension TruckCab {
    var tier: PartTier { partTier(rawValue: rawValue, isFree: Self.freeCases.contains(self)) }
}
extension TruckBody {
    var tier: PartTier { partTier(rawValue: rawValue, isFree: Self.freeCases.contains(self)) }
}
extension TruckWheelType {
    var tier: PartTier { partTier(rawValue: rawValue, isFree: Self.freeCases.contains(self)) }
}
