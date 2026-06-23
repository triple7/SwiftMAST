//
//  SpaceRegion.swift
//  SwiftMAST
//
//  Utilities for parsing and comparing CAOM `s_region` footprints.
//

import Foundation
import SwiftQValue

/// How strictly a candidate CAOM footprint should match a source footprint.
public enum SpaceRegionContainmentMode: String, Codable, CaseIterable, Identifiable {
    /// Match if the candidate observation center (`s_ra`, `s_dec`) lies inside the source footprint.
    ///
    /// This is fast and useful for finding observations whose pointing center falls within an
    /// existing product footprint. It can miss large observations that overlap the footprint while
    /// their center is outside it.
    case centerInside

    /// Match if the candidate footprint overlaps or touches the source footprint.
    ///
    /// This is the broadest useful footprint match. It includes products that partially overlap
    /// the source footprint, even when their center is outside it.
    case footprintIntersects

    /// Match if the candidate footprint is fully contained by the source footprint.
    ///
    /// This is the strictest match. It is useful when the caller wants products wholly covered by
    /// the source footprint, not merely nearby or partially overlapping products.
    case footprintContained

    public var id: String { rawValue }
}

/// Parsed representation of a CAOM `s_region` value.
public struct SpaceRegion: Codable, Equatable {
    public struct Coordinate: Codable, Equatable, Hashable {
        public let ra: Double
        public let dec: Double

        public init(ra: Double, dec: Double) {
            self.ra = SpaceRegion.normalizedDegrees(ra)
            self.dec = dec
        }
    }

    public struct BoundingCone: Codable, Equatable {
        public let ra: Double
        public let dec: Double
        public let radius: Double
    }

    public enum Shape: Codable, Equatable {
        case circle(center: Coordinate, radius: Double)
        case polygon(vertices: [Coordinate])
    }

    public let shapes: [Shape]

    public init(shapes: [Shape]) {
        self.shapes = shapes
    }

    public init?(_ region: String) {
        guard let parsed = Self.parse(region), !parsed.shapes.isEmpty else { return nil }
        self = parsed
    }

    /// Bounding cone suitable for MAST's `Mast.Caom.Filtered.Position` input.
    public var boundingCone: BoundingCone? {
        let samples = samplePoints(includeInterior: true)
        guard !samples.isEmpty else { return nil }

        let center = Self.sphericalMean(samples)
        let radius = samples
            .map { Self.angularDistanceDegrees(center, $0) }
            .max() ?? 0

        return BoundingCone(ra: center.ra, dec: center.dec, radius: max(radius, 0.000_001))
    }

    public func contains(_ point: Coordinate) -> Bool {
        shapes.contains { shapeContainsPoint($0, point) }
    }

    public func matches(
        candidate: SpaceRegion,
        candidateCenter: Coordinate?,
        mode: SpaceRegionContainmentMode
    ) -> Bool {
        switch mode {
        case .centerInside:
            if let candidateCenter {
                return contains(candidateCenter)
            }

            guard let center = candidate.boundingCone.map({ Coordinate(ra: $0.ra, dec: $0.dec) }) else {
                return false
            }
            return contains(center)

        case .footprintIntersects:
            return intersects(candidate)

        case .footprintContained:
            return contains(region: candidate)
        }
    }

    public func intersects(_ other: SpaceRegion) -> Bool {
        let selfSamples = samplePoints(includeInterior: true)
        let otherSamples = other.samplePoints(includeInterior: true)

        if otherSamples.contains(where: contains) || selfSamples.contains(where: other.contains) {
            return true
        }

        for lhs in polygonSegments() {
            for rhs in other.polygonSegments() {
                if Self.segmentsIntersect(lhs.0, lhs.1, rhs.0, rhs.1) {
                    return true
                }
            }
        }

        for circle in circles() {
            if otherSamples.contains(where: { Self.angularDistanceDegrees(circle.center, $0) <= circle.radius }) {
                return true
            }
        }

        for circle in other.circles() {
            if selfSamples.contains(where: { Self.angularDistanceDegrees(circle.center, $0) <= circle.radius }) {
                return true
            }
        }

        for lhs in circles() {
            for rhs in other.circles() {
                if Self.angularDistanceDegrees(lhs.center, rhs.center) <= lhs.radius + rhs.radius {
                    return true
                }
            }
        }

        return false
    }

    public func contains(region other: SpaceRegion) -> Bool {
        let samples = other.samplePoints(includeInterior: true)
        guard !samples.isEmpty else { return false }
        return samples.allSatisfy(contains)
    }

    static func qValueDouble(_ value: QValue) -> Double? {
        if let double = value.value as? Double { return double }
        if let float = value.value as? Float { return Double(float) }
        if let int = value.value as? Int { return Double(int) }
        if let string = value.value as? String { return Double(string) }
        return nil
    }

    private static func parse(_ region: String) -> SpaceRegion? {
        let tokens = region
            .split { $0.isWhitespace }
            .map(String.init)

        guard !tokens.isEmpty else { return nil }

        var index = 0
        var shapes: [Shape] = []

        while index < tokens.count {
            let shape = tokens[index].uppercased()
            switch shape {
            case "CIRCLE":
                guard let parsed = parseCircle(tokens, startingAt: index) else { return nil }
                shapes.append(.circle(center: parsed.center, radius: parsed.radius))
                index = parsed.nextIndex

            case "POLYGON":
                guard let parsed = parsePolygon(tokens, startingAt: index) else { return nil }
                shapes.append(.polygon(vertices: parsed.vertices))
                index = parsed.nextIndex

            default:
                return nil
            }
        }

        return SpaceRegion(shapes: shapes)
    }

    private static func parseCircle(
        _ tokens: [String],
        startingAt index: Int
    ) -> (center: Coordinate, radius: Double, nextIndex: Int)? {
        let valueStart = firstNumericValueIndex(in: tokens, afterShapeAt: index)
        guard tokens.count >= valueStart + 3,
              let ra = Double(tokens[valueStart]),
              let dec = Double(tokens[valueStart + 1]),
              let radius = Double(tokens[valueStart + 2]),
              radius > 0
        else {
            return nil
        }

        return (Coordinate(ra: ra, dec: dec), radius, valueStart + 3)
    }

    private static func parsePolygon(
        _ tokens: [String],
        startingAt index: Int
    ) -> (vertices: [Coordinate], nextIndex: Int)? {
        var valueIndex = firstNumericValueIndex(in: tokens, afterShapeAt: index)
        var vertices: [Coordinate] = []

        while valueIndex < tokens.count {
            let token = tokens[valueIndex].uppercased()
            if token == "CIRCLE" || token == "POLYGON" {
                break
            }

            guard valueIndex + 1 < tokens.count,
                  let ra = Double(tokens[valueIndex]),
                  let dec = Double(tokens[valueIndex + 1])
            else {
                return nil
            }

            vertices.append(Coordinate(ra: ra, dec: dec))
            valueIndex += 2
        }

        if vertices.first == vertices.last {
            vertices.removeLast()
        }

        guard vertices.count >= 3 else { return nil }
        return (vertices, valueIndex)
    }

    private static func firstNumericValueIndex(in tokens: [String], afterShapeAt index: Int) -> Int {
        let nextIndex = index + 1
        guard nextIndex < tokens.count else { return nextIndex }
        return Double(tokens[nextIndex]) == nil ? nextIndex + 1 : nextIndex
    }

    private func samplePoints(includeInterior: Bool) -> [Coordinate] {
        shapes.flatMap { shape -> [Coordinate] in
            switch shape {
            case .circle(let center, let radius):
                var points = [
                    Self.offsetPoint(from: center, raOffset: radius, decOffset: 0),
                    Self.offsetPoint(from: center, raOffset: -radius, decOffset: 0),
                    Coordinate(ra: center.ra, dec: min(90, center.dec + radius)),
                    Coordinate(ra: center.ra, dec: max(-90, center.dec - radius)),
                ]
                if includeInterior {
                    points.append(center)
                }
                return points

            case .polygon(let vertices):
                guard includeInterior else { return vertices }
                return vertices + [Self.sphericalMean(vertices)]
            }
        }
    }

    private func circles() -> [(center: Coordinate, radius: Double)] {
        shapes.compactMap {
            if case .circle(let center, let radius) = $0 {
                return (center, radius)
            }
            return nil
        }
    }

    private func polygonSegments() -> [(Coordinate, Coordinate)] {
        shapes.flatMap { shape -> [(Coordinate, Coordinate)] in
            guard case .polygon(let vertices) = shape, vertices.count >= 2 else { return [] }
            return vertices.indices.map { index in
                (vertices[index], vertices[(index + 1) % vertices.count])
            }
        }
    }

    private func shapeContainsPoint(_ shape: Shape, _ point: Coordinate) -> Bool {
        switch shape {
        case .circle(let center, let radius):
            return Self.angularDistanceDegrees(center, point) <= radius + 1e-9

        case .polygon(let vertices):
            return polygonContains(point, vertices: vertices)
        }
    }

    private func polygonContains(_ point: Coordinate, vertices: [Coordinate]) -> Bool {
        guard vertices.count >= 3 else { return false }

        let projectedVertices = vertices.map { Self.project($0, around: point) }
        let projectedPoint = (x: 0.0, y: 0.0)
        var inside = false
        var previous = projectedVertices.count - 1

        for current in projectedVertices.indices {
            let a = projectedVertices[current]
            let b = projectedVertices[previous]

            if Self.pointOnSegment(projectedPoint, a, b) {
                return true
            }

            let intersects =
                ((a.y > projectedPoint.y) != (b.y > projectedPoint.y))
                && (projectedPoint.x
                    < (b.x - a.x) * (projectedPoint.y - a.y) / ((b.y - a.y) == 0 ? .ulpOfOne : (b.y - a.y)) + a.x)
            if intersects {
                inside.toggle()
            }

            previous = current
        }

        return inside
    }

    private static func sphericalMean(_ points: [Coordinate]) -> Coordinate {
        var x = 0.0
        var y = 0.0
        var z = 0.0

        for point in points {
            let ra = degreesToRadians(point.ra)
            let dec = degreesToRadians(point.dec)
            let cosDec = cos(dec)
            x += cosDec * cos(ra)
            y += cosDec * sin(ra)
            z += sin(dec)
        }

        let count = max(Double(points.count), 1)
        x /= count
        y /= count
        z /= count

        let hyp = sqrt(x * x + y * y)
        return Coordinate(
            ra: radiansToDegrees(atan2(y, x)),
            dec: radiansToDegrees(atan2(z, hyp))
        )
    }

    private static func offsetPoint(from center: Coordinate, raOffset: Double, decOffset: Double) -> Coordinate {
        let cosDec = max(0.000_001, cos(degreesToRadians(center.dec)))
        return Coordinate(ra: center.ra + raOffset / cosDec, dec: center.dec + decOffset)
    }

    private static func angularDistanceDegrees(_ a: Coordinate, _ b: Coordinate) -> Double {
        let ra1 = degreesToRadians(a.ra)
        let dec1 = degreesToRadians(a.dec)
        let ra2 = degreesToRadians(b.ra)
        let dec2 = degreesToRadians(b.dec)

        let sinDDec = sin((dec2 - dec1) / 2)
        let sinDRa = sin((ra2 - ra1) / 2)
        let h = sinDDec * sinDDec + cos(dec1) * cos(dec2) * sinDRa * sinDRa
        return radiansToDegrees(2 * asin(min(1, sqrt(max(0, h)))))
    }

    private static func project(_ coordinate: Coordinate, around origin: Coordinate) -> (x: Double, y: Double) {
        let deltaRA = wrappedDegrees(coordinate.ra - origin.ra)
        let scale = cos(degreesToRadians(origin.dec))
        return (x: deltaRA * scale, y: coordinate.dec - origin.dec)
    }

    private static func segmentsIntersect(
        _ a: Coordinate,
        _ b: Coordinate,
        _ c: Coordinate,
        _ d: Coordinate
    ) -> Bool {
        let origin = Self.sphericalMean([a, b, c, d])
        let a2 = Self.project(a, around: origin)
        let b2 = Self.project(b, around: origin)
        let c2 = Self.project(c, around: origin)
        let d2 = Self.project(d, around: origin)

        let o1 = orientation(a2, b2, c2)
        let o2 = orientation(a2, b2, d2)
        let o3 = orientation(c2, d2, a2)
        let o4 = orientation(c2, d2, b2)

        if o1 * o2 < 0 && o3 * o4 < 0 {
            return true
        }

        return Self.pointOnSegment(c2, a2, b2)
            || Self.pointOnSegment(d2, a2, b2)
            || Self.pointOnSegment(a2, c2, d2)
            || Self.pointOnSegment(b2, c2, d2)
    }

    private static func orientation(
        _ a: (x: Double, y: Double),
        _ b: (x: Double, y: Double),
        _ c: (x: Double, y: Double)
    ) -> Double {
        (b.x - a.x) * (c.y - a.y) - (b.y - a.y) * (c.x - a.x)
    }

    private static func pointOnSegment(
        _ p: (x: Double, y: Double),
        _ a: (x: Double, y: Double),
        _ b: (x: Double, y: Double)
    ) -> Bool {
        let cross = orientation(a, b, p)
        guard abs(cross) < 1e-9 else { return false }

        return p.x >= min(a.x, b.x) - 1e-9
            && p.x <= max(a.x, b.x) + 1e-9
            && p.y >= min(a.y, b.y) - 1e-9
            && p.y <= max(a.y, b.y) + 1e-9
    }

    private static func normalizedDegrees(_ degrees: Double) -> Double {
        let value = degrees.truncatingRemainder(dividingBy: 360)
        return value < 0 ? value + 360 : value
    }

    private static func wrappedDegrees(_ degrees: Double) -> Double {
        var value = degrees.truncatingRemainder(dividingBy: 360)
        if value > 180 { value -= 360 }
        if value < -180 { value += 360 }
        return value
    }

    private static func degreesToRadians(_ degrees: Double) -> Double {
        degrees * Double.pi / 180
    }

    private static func radiansToDegrees(_ radians: Double) -> Double {
        radians * 180 / Double.pi
    }
}

extension CoamResult {
    /// Parsed CAOM footprint from `s_region`, when it uses a supported CIRCLE or POLYGON shape.
    public var spaceRegion: SpaceRegion? {
        SpaceRegion(s_region)
    }

    /// CAOM observation center from `s_ra`/`s_dec`, when available.
    public var spaceRegionCenter: SpaceRegion.Coordinate? {
        guard let ra = SpaceRegion.qValueDouble(s_ra),
              let dec = SpaceRegion.qValueDouble(s_dec)
        else {
            return nil
        }
        return SpaceRegion.Coordinate(ra: ra, dec: dec)
    }
}
