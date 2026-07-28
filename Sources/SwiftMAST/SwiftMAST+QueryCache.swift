//
//  SwiftMAST+QueryCache.swift
//  SwiftMAST
//

import CryptoKit
import Foundation

internal struct MASTQueryCacheEntry: Codable {
    let createdAt: Date
    let service: String
    let returnType: String
    let key: String
    let data: Data
}

extension SwiftMAST {
    public static let defaultQueryCacheTTL: TimeInterval = 7 * 24 * 60 * 60

    internal func queryCacheDirectoryURL() -> URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)
            .first?
            .appendingPathComponent("MAST", isDirectory: true)
            .appendingPathComponent(".cache", isDirectory: true)
            .appendingPathComponent("queries", isDirectory: true)
    }

    internal func queryCacheURL(for key: String) -> URL? {
        queryCacheDirectoryURL()?.appendingPathComponent("\(key).json")
    }

    internal func mastQueryCacheKey(
        service: Service,
        returnType: APIReturnType,
        params: MASTJson
    ) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(params) else {
            return nil
        }
        return queryCacheKey(
            namespace: "mast",
            service: service.id,
            returnType: returnType.id,
            requestData: data
        )
    }

    internal func tapQueryCacheKey(
        query: String,
        format: APIReturnType
    ) -> String? {
        let body = "QUERY=\(query)&LANG=ADQL-2.0&responseformat=\(format.id)"
        guard let data = body.data(using: .utf8) else {
            return nil
        }
        return queryCacheKey(
            namespace: "tap",
            service: "MAST TAP",
            returnType: format.id,
            requestData: data
        )
    }

    internal func cachedQueryResponse(
        key: String,
        ttl: TimeInterval = SwiftMAST.defaultQueryCacheTTL
    ) -> Data? {
        guard let cacheURL = queryCacheURL(for: key),
              let data = try? Data(contentsOf: cacheURL),
              let entry = try? JSONDecoder().decode(MASTQueryCacheEntry.self, from: data)
        else {
            return nil
        }

        guard Date().timeIntervalSince(entry.createdAt) <= ttl else {
            try? FileManager.default.removeItem(at: cacheURL)
            log(
                .OK,
                message: "Refreshing cached MAST query results",
                metadata: [
                    "audience": "developer",
                    "event": "queryCacheExpired",
                    "cacheKey": key,
                    "service": entry.service,
                    "returnType": entry.returnType,
                ]
            )
            return nil
        }

        let targetId = currentTargetId?.trimmingCharacters(in: .whitespacesAndNewlines)
        let targetDescription = targetId?.isEmpty == false ? targetId : nil

        log(
            .OK,
            message: targetDescription.map { "Using cached MAST query results for \($0)" }
                ?? "Using cached MAST query results",
            metadata: [
                "audience": "user",
                "event": "queryCacheHit",
                "cacheKey": key,
                "service": entry.service,
                "returnType": entry.returnType,
                "targetId": targetDescription ?? "",
            ]
        )
        return entry.data
    }

    internal func storeCachedQueryResponse(
        _ data: Data,
        key: String,
        service: String,
        returnType: String,
        createdAt: Date = Date()
    ) {
        guard !data.isEmpty,
              let cacheURL = queryCacheURL(for: key)
        else {
            return
        }

        let entry = MASTQueryCacheEntry(
            createdAt: createdAt,
            service: service,
            returnType: returnType,
            key: key,
            data: data
        )

        do {
            try FileManager.default.createDirectory(
                at: cacheURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let encoded = try JSONEncoder().encode(entry)
            try encoded.write(to: cacheURL, options: .atomic)
        } catch {
            log(
                .RequestError,
                message: "Unable to write query cache",
                metadata: [
                    "audience": "developer",
                    "event": "queryCacheWriteFailed",
                    "cacheKey": key,
                    "service": service,
                    "returnType": returnType,
                    "error": error.localizedDescription,
                ]
            )
        }
    }

    public func resetQueryCache() {
        guard let cacheDirectoryURL = queryCacheDirectoryURL() else {
            return
        }
        try? FileManager.default.removeItem(at: cacheDirectoryURL)
        log(.OK, message: "Cleared MAST query cache", metadata: ["event": "queryCacheReset"])
    }

    public func clearQueryCache() {
        resetQueryCache()
    }

    private func queryCacheKey(
        namespace: String,
        service: String,
        returnType: String,
        requestData: Data
    ) -> String {
        var data = Data()
        data.append(Data(namespace.utf8))
        data.append(0)
        data.append(Data(service.utf8))
        data.append(0)
        data.append(Data(returnType.utf8))
        data.append(0)
        data.append(requestData)

        let digest = SHA256.hash(data: data)
        let hex = digest.map { String(format: "%02x", $0) }.joined()
        return "\(namespace)-\(hex)"
    }
}
