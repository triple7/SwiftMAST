//
//  SpaceRegionArea.swift
//

import Foundation

enum SpaceRegionArea {
    static let unit = "deg^2"

    private static let squareDegreesPerSteradian = pow(180.0 / Double.pi, 2.0)

    static func squareDegrees(from region: String) -> Double? {
        let tokens = region
            .split { $0.isWhitespace }
            .map(String.init)

        guard !tokens.isEmpty else { return nil }

        var index = 0
        var totalSteradians = 0.0
        var foundSupportedRegion = false

        while index < tokens.count {
            let shape = tokens[index].uppercased()
            switch shape {
            case "CIRCLE":
                guard let result = parseCircle(tokens, startingAt: index) else { return nil }
                totalSteradians += result.areaSteradians
                foundSupportedRegion = true
                index = result.nextIndex

            case "POLYGON":
                guard let result = parsePolygon(tokens, startingAt: index) else { return nil }
                totalSteradians += result.areaSteradians
                foundSupportedRegion = true
                index = result.nextIndex

            default:
                return nil
            }
        }

        guard foundSupportedRegion, totalSteradians.isFinite, totalSteradians > 0 else {
            return nil
        }

        return totalSteradians * squareDegreesPerSteradian
    }

    private static func parseCircle(
        _ tokens: [String],
        startingAt index: Int
    ) -> (areaSteradians: Double, nextIndex: Int)? {
        let valueStart = firstNumericValueIndex(in: tokens, afterShapeAt: index)
        guard tokens.count >= valueStart + 3,
              Double(tokens[valueStart]) != nil,
              Double(tokens[valueStart + 1]) != nil,
              let radiusDegrees = Double(tokens[valueStart + 2]),
              radiusDegrees > 0
        else {
            return nil
        }

        let radiusRadians = degreesToRadians(radiusDegrees)
        let areaSteradians = 2.0 * Double.pi * (1.0 - cos(radiusRadians))
        return (areaSteradians, valueStart + 3)
    }

    private static func parsePolygon(
        _ tokens: [String],
        startingAt index: Int
    ) -> (areaSteradians: Double, nextIndex: Int)? {
        var valueIndex = firstNumericValueIndex(in: tokens, afterShapeAt: index)
        var vertices: [SphericalPoint] = []

        while valueIndex < tokens.count {
            let token = tokens[valueIndex].uppercased()
            if token == "CIRCLE" || token == "POLYGON" {
                break
            }

            guard valueIndex + 1 < tokens.count,
                  let raDegrees = Double(tokens[valueIndex]),
                  let decDegrees = Double(tokens[valueIndex + 1])
            else {
                return nil
            }

            vertices.append(SphericalPoint(raDegrees: raDegrees, decDegrees: decDegrees))
            valueIndex += 2
        }

        if vertices.first == vertices.last {
            vertices.removeLast()
        }

        guard vertices.count >= 3 else { return nil }

        return (polygonAreaSteradians(vertices), valueIndex)
    }

    private static func firstNumericValueIndex(in tokens: [String], afterShapeAt index: Int) -> Int {
        let nextIndex = index + 1
        guard nextIndex < tokens.count else { return nextIndex }
        return Double(tokens[nextIndex]) == nil ? nextIndex + 1 : nextIndex
    }

    private static func polygonAreaSteradians(_ vertices: [SphericalPoint]) -> Double {
        let origin = vertices[0]
        var area = 0.0

        for index in 1..<(vertices.count - 1) {
            area += sphericalTriangleArea(
                origin,
                vertices[index],
                vertices[index + 1]
            )
        }

        return abs(area)
    }

    private static func sphericalTriangleArea(
        _ a: SphericalPoint,
        _ b: SphericalPoint,
        _ c: SphericalPoint
    ) -> Double {
        let sideA = angularDistance(b, c)
        let sideB = angularDistance(c, a)
        let sideC = angularDistance(a, b)
        let semiperimeter = (sideA + sideB + sideC) / 2.0

        let tangentProduct =
            tan(semiperimeter / 2.0)
            * tan((semiperimeter - sideA) / 2.0)
            * tan((semiperimeter - sideB) / 2.0)
            * tan((semiperimeter - sideC) / 2.0)

        guard tangentProduct > 0, tangentProduct.isFinite else {
            return 0.0
        }

        return 4.0 * atan(sqrt(tangentProduct))
    }

    private static func angularDistance(_ a: SphericalPoint, _ b: SphericalPoint) -> Double {
        let dotProduct = a.x * b.x + a.y * b.y + a.z * b.z
        return acos(min(1.0, max(-1.0, dotProduct)))
    }

    private static func degreesToRadians(_ degrees: Double) -> Double {
        degrees * Double.pi / 180.0
    }

    private struct SphericalPoint: Equatable {
        let raDegrees: Double
        let decDegrees: Double
        let x: Double
        let y: Double
        let z: Double

        init(raDegrees: Double, decDegrees: Double) {
            self.raDegrees = raDegrees
            self.decDegrees = decDegrees

            let ra = SpaceRegionArea.degreesToRadians(raDegrees)
            let dec = SpaceRegionArea.degreesToRadians(decDegrees)
            let cosDec = cos(dec)

            self.x = cosDec * cos(ra)
            self.y = cosDec * sin(ra)
            self.z = sin(dec)
        }
    }
}
