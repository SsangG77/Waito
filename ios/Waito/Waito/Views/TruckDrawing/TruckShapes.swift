import SwiftUI

// MARK: - 트럭 파트 (4개 영역)

struct TruckParts {
    let head: Path     // 운전석 (캡)
    let cargo: Path    // 짐칸
    let box: Path      // 택배 상자
    let wheels: Path   // 바퀴 (항상 검정)
}

// MARK: - Standard Truck (기본 배송 트럭)
// 각진 짐칸 + 앞쪽 사선 보닛

struct StandardTruckShape {
    static func parts(in size: CGFloat) -> TruckParts {
        let u = size / 20

        let head: Path = {
            var p = Path()
            p.move(to: CGPoint(x: 12 * u, y: 6 * u))
            p.addLine(to: CGPoint(x: 16 * u, y: 6 * u))
            p.addLine(to: CGPoint(x: 19 * u, y: 9.5 * u))
            p.addLine(to: CGPoint(x: 19 * u, y: 15 * u))
            p.addLine(to: CGPoint(x: 12 * u, y: 15 * u))
            p.closeSubpath()
            return p
        }()

        let cargo: Path = {
            var p = Path()
            p.addRoundedRect(
                in: CGRect(x: 1 * u, y: 4 * u, width: 12 * u, height: 11 * u),
                cornerSize: CGSize(width: 1 * u, height: 1 * u)
            )
            return p
        }()

        let box: Path = {
            var p = Path()
            p.addRoundedRect(
                in: CGRect(x: 3 * u, y: 6 * u, width: 5 * u, height: 4 * u),
                cornerSize: CGSize(width: 0.8 * u, height: 0.8 * u)
            )
            return p
        }()

        let wheels: Path = {
            var p = Path()
            p.addEllipse(in: CGRect(x: 3 * u, y: 15 * u, width: 4 * u, height: 4 * u))
            p.addEllipse(in: CGRect(x: 14 * u, y: 15 * u, width: 4 * u, height: 4 * u))
            return p
        }()

        return TruckParts(head: head, cargo: cargo, box: box, wheels: wheels)
    }
}

// MARK: - Minivan (원피스 밴)
// 둥근 지붕 + 앞쪽 노즈 곡선

struct MinivanTruckShape {
    static func parts(in size: CGFloat) -> TruckParts {
        let u = size / 20

        let head: Path = {
            var p = Path()
            p.move(to: CGPoint(x: 13 * u, y: 7 * u))
            p.addLine(to: CGPoint(x: 16 * u, y: 7 * u))
            p.addQuadCurve(to: CGPoint(x: 19 * u, y: 12 * u),
                           control: CGPoint(x: 19 * u, y: 7 * u))
            p.addLine(to: CGPoint(x: 19 * u, y: 14.5 * u))
            p.addQuadCurve(to: CGPoint(x: 18.5 * u, y: 15 * u),
                           control: CGPoint(x: 19 * u, y: 15 * u))
            p.addLine(to: CGPoint(x: 13 * u, y: 15 * u))
            p.closeSubpath()
            return p
        }()

        let cargo: Path = {
            var p = Path()
            let r = 3 * u
            p.move(to: CGPoint(x: 1 * u + r, y: 15 * u))
            p.addLine(to: CGPoint(x: 14 * u, y: 15 * u))
            p.addLine(to: CGPoint(x: 14 * u, y: 7 * u))
            p.addQuadCurve(to: CGPoint(x: 1 * u, y: 7 * u),
                           control: CGPoint(x: 7 * u, y: 4 * u))
            p.addLine(to: CGPoint(x: 1 * u, y: 15 * u - r))
            p.addQuadCurve(to: CGPoint(x: 1 * u + r, y: 15 * u),
                           control: CGPoint(x: 1 * u, y: 15 * u))
            p.closeSubpath()
            return p
        }()

        let box: Path = {
            var p = Path()
            p.addRoundedRect(
                in: CGRect(x: 3 * u, y: 9 * u, width: 4 * u, height: 3.5 * u),
                cornerSize: CGSize(width: 0.6 * u, height: 0.6 * u)
            )
            return p
        }()

        let wheels: Path = {
            var p = Path()
            p.addEllipse(in: CGRect(x: 2.5 * u, y: 15 * u, width: 4 * u, height: 4 * u))
            p.addEllipse(in: CGRect(x: 14 * u, y: 15 * u, width: 4 * u, height: 4 * u))
            return p
        }()

        return TruckParts(head: head, cargo: cargo, box: box, wheels: wheels)
    }
}

// MARK: - Heavy Truck (대형 트럭)
// 높은 컨테이너 + 분리된 캡 + 바퀴 3개

struct HeavyTruckShape {
    static func parts(in size: CGFloat) -> TruckParts {
        let u = size / 24

        let head: Path = {
            var p = Path()
            p.move(to: CGPoint(x: 19 * u, y: 7 * u))
            p.addLine(to: CGPoint(x: 21 * u, y: 7 * u))
            p.addLine(to: CGPoint(x: 23 * u, y: 10 * u))
            let r = 1.2 * u
            p.addLine(to: CGPoint(x: 23 * u, y: 16 * u - r))
            p.addQuadCurve(to: CGPoint(x: 23 * u - r, y: 16 * u),
                           control: CGPoint(x: 23 * u, y: 16 * u))
            p.addLine(to: CGPoint(x: 19 * u, y: 16 * u))
            p.closeSubpath()
            return p
        }()

        let cargo: Path = {
            var p = Path()
            p.addRoundedRect(
                in: CGRect(x: 1 * u, y: 2 * u, width: 17 * u, height: 14 * u),
                cornerSize: CGSize(width: 1 * u, height: 1 * u)
            )
            return p
        }()

        let box: Path = {
            var p = Path()
            p.addRoundedRect(
                in: CGRect(x: 3 * u, y: 4 * u, width: 4 * u, height: 4 * u),
                cornerSize: CGSize(width: 0.5 * u, height: 0.5 * u)
            )
            p.addRoundedRect(
                in: CGRect(x: 8 * u, y: 4 * u, width: 4 * u, height: 4 * u),
                cornerSize: CGSize(width: 0.5 * u, height: 0.5 * u)
            )
            p.addRoundedRect(
                in: CGRect(x: 13 * u, y: 4 * u, width: 3.5 * u, height: 4 * u),
                cornerSize: CGSize(width: 0.5 * u, height: 0.5 * u)
            )
            return p
        }()

        let wheels: Path = {
            var p = Path()
            p.addEllipse(in: CGRect(x: 2 * u, y: 15.5 * u, width: 4 * u, height: 4 * u))
            p.addEllipse(in: CGRect(x: 9 * u, y: 15.5 * u, width: 4 * u, height: 4 * u))
            p.addEllipse(in: CGRect(x: 19 * u, y: 15.5 * u, width: 4 * u, height: 4 * u))
            return p
        }()

        return TruckParts(head: head, cargo: cargo, box: box, wheels: wheels)
    }
}
