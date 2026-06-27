//
//  SwiftMAST+FileSizes.swift
//  SwiftMAST
//

import Foundation

extension SwiftMAST {
    internal func enrichCoamResultsWithFileSizes(
        _ results: [CoamResult],
        completion: @escaping ([CoamResult]) -> Void
    ) {
        guard !results.isEmpty else {
            completion([])
            return
        }

        let requestLimit = max(maxConcurrentRequests, 1)
        fetchProductFileSizes(for: results, maxConcurrentRequests: requestLimit) { productSizes in
            var enriched = results.map { coam -> CoamResult in
                coam.withFileSizes(
                    dataURLSizeBytes: self.productSize(for: coam.dataURL, in: productSizes),
                    jpegURLSizeBytes: self.productSize(for: coam.jpegURL, in: productSizes)
                )
            }

            self.fetchMissingHeaderSizes(
                for: enriched, maxConcurrentRequests: requestLimit
            ) { headerSizes in
                for index in enriched.indices {
                    let coam = enriched[index]
                    enriched[index] = coam.withFileSizes(
                        dataURLSizeBytes: coam.dataURLSizeBytes ?? headerSizes[coam.dataURL],
                        jpegURLSizeBytes: coam.jpegURLSizeBytes ?? headerSizes[coam.jpegURL]
                    )
                }
                completion(enriched)
            }
        }
    }

    private struct ProductFileSize {
        let dataURI: String
        let productFilename: String
        let size: Int64
    }

    private func fetchProductFileSizes(
        for results: [CoamResult],
        maxConcurrentRequests: Int,
        completion: @escaping ([ProductFileSize]) -> Void
    ) {
        let obsids = Array(Set(results.map(\.obsid).filter { $0 > 0 })).sorted()
        guard !obsids.isEmpty else {
            completion([])
            return
        }

        let chunks = stride(from: 0, to: obsids.count, by: 50).map {
            Array(obsids[$0..<min($0 + 50, obsids.count)])
        }

        let group = DispatchGroup()
        let lock = NSLock()
        var output = [ProductFileSize]()
        var nextIndex = 0

        func nextChunk() -> [Int]? {
            lock.lock()
            defer { lock.unlock() }
            guard nextIndex < chunks.count else { return nil }
            let chunk = chunks[nextIndex]
            nextIndex += 1
            return chunk
        }

        func startWorker() {
            group.enter()
            func fetchNext() {
                guard let chunk = nextChunk() else {
                    group.leave()
                    return
                }
                fetchProductFileSizes(forObsids: chunk) { sizes in
                    lock.lock()
                    output.append(contentsOf: sizes)
                    lock.unlock()
                    fetchNext()
                }
            }
            fetchNext()
        }

        let workerCount = min(max(maxConcurrentRequests, 1), chunks.count)
        for _ in 0..<workerCount {
            startWorker()
        }

        group.notify(queue: .main) {
            completion(output)
        }
    }

    private func fetchProductFileSizes(
        forObsids obsids: [Int],
        completion: @escaping ([ProductFileSize]) -> Void
    ) {
        let payload: [String: Any] = [
            "service": Service.Mast_Caom_Products.id,
            "params": ["obsid": obsids.map(String.init).joined(separator: ",")],
            "format": APIReturnType.json.id,
        ]

        guard let data = try? JSONSerialization.data(withJSONObject: payload) else {
            completion([])
            return
        }
        let url = MASTRequest(searchType: .apiRequest).getApiUrl(json: data)
        let request = URLRequest(url: url)
        let requestBody = String(data: data, encoding: .utf8) ?? ""
        let start = Date().timeIntervalSinceReferenceDate
        log(
            .OK,
            message:
                "MAST API \(Service.Mast_Caom_Products.id): Request sent method=GET, url=\(url.absoluteString), bodyBytes=\(data.count), body=\(requestBody)"
        )

        URLSession.shared.dataTask(with: request) { data, response, error in
            let elapsed = Date().timeIntervalSinceReferenceDate - start
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            self.log(
                error == nil ? .OK : .RequestError,
                message:
                    "MAST API \(Service.Mast_Caom_Products.id): Response received status=\(statusCode.map(String.init) ?? "none"), bytes=\(data?.count ?? 0), time=\(String(format: "%.3f", elapsed))s, url=\(url.absoluteString)"
            )
            guard
                error == nil,
                let httpResponse = response as? HTTPURLResponse,
                (200..<300).contains(httpResponse.statusCode),
                let data,
                let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let rows = json["data"] as? [[String: Any]]
            else {
                completion([])
                return
            }

            let sizes = rows.compactMap { row -> ProductFileSize? in
                guard
                    let dataURI = row["dataURI"] as? String,
                    let size = Self.int64Value(row["size"])
                else {
                    return nil
                }
                return ProductFileSize(
                    dataURI: dataURI,
                    productFilename: row["productFilename"] as? String ?? "",
                    size: size
                )
            }
            completion(sizes)
        }.resume()
    }

    private func productSize(for productURL: String, in products: [ProductFileSize]) -> Int64? {
        let normalizedURL = normalizeProductLocator(productURL)
        guard !normalizedURL.isEmpty else { return nil }

        for product in products {
            let normalizedURI = normalizeProductLocator(product.dataURI)
            let filename = product.productFilename.lowercased()
            if normalizedURL == normalizedURI
                || normalizedURL.contains(normalizedURI)
                || normalizedURI.contains(normalizedURL)
                || (!filename.isEmpty && normalizedURL.contains(filename))
            {
                return product.size
            }

            if let uriSuffix = normalizedURI.components(separatedBy: "url/").last,
                normalizedURL.contains(uriSuffix)
            {
                return product.size
            }
        }

        return nil
    }

    private func fetchMissingHeaderSizes(
        for results: [CoamResult],
        maxConcurrentRequests: Int,
        completion: @escaping ([String: Int64]) -> Void
    ) {
        let missingURLs = Set(
            results.flatMap { coam -> [String] in
                var urls = [String]()
                if !coam.dataURL.isEmpty, coam.dataURLSizeBytes == nil {
                    urls.append(coam.dataURL)
                }
                if !coam.jpegURL.isEmpty, coam.jpegURLSizeBytes == nil {
                    urls.append(coam.jpegURL)
                }
                return urls
            }
        )

        guard !missingURLs.isEmpty else {
            completion([:])
            return
        }

        fetchHeaderSizes(
            for: Array(missingURLs),
            maxConcurrentRequests: maxConcurrentRequests,
            completion: completion)
    }

    internal func fetchHeaderSizes(
        for productURLs: [String],
        maxConcurrentRequests: Int? = nil,
        completion: @escaping ([String: Int64]) -> Void
    ) {
        let urls = Array(Set(productURLs.filter { !$0.isEmpty }))
        guard !urls.isEmpty else {
            completion([:])
            return
        }

        let requestLimit = max(maxConcurrentRequests ?? self.maxConcurrentRequests, 1)
        let workerCount = min(requestLimit, urls.count)
        let group = DispatchGroup()
        let lock = NSLock()
        var sizes = [String: Int64]()
        var nextIndex = 0

        func nextURL() -> String? {
            lock.lock()
            defer { lock.unlock() }

            guard nextIndex < urls.count else { return nil }
            let url = urls[nextIndex]
            nextIndex += 1
            return url
        }

        func startWorker() {
            group.enter()
            func fetchNext() {
                guard let productURL = nextURL() else {
                    group.leave()
                    return
                }

                self.fetchContentLength(for: productURL) { size in
                    if let size {
                        lock.lock()
                        sizes[productURL] = size
                        lock.unlock()
                    }
                    fetchNext()
                }
            }
            fetchNext()
        }

        for _ in 0..<workerCount {
            startWorker()
        }

        group.notify(queue: .main) {
            completion(sizes)
        }
    }

    private func fetchContentLength(for productURL: String, completion: @escaping (Int64?) -> Void) {
        guard let url = downloadURL(for: productURL) else {
            completion(nil)
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.timeoutInterval = 20
        let start = Date().timeIntervalSinceReferenceDate
        log(
            .OK,
            message: "MAST size HEAD: Request sent method=HEAD, url=\(url.absoluteString)"
        )

        URLSession.shared.dataTask(with: request) { _, response, error in
            let elapsed = Date().timeIntervalSinceReferenceDate - start
            let statusCode = (response as? HTTPURLResponse)?.statusCode
            let contentLength = (response as? HTTPURLResponse)?
                .value(forHTTPHeaderField: "Content-Length")
            self.log(
                error == nil ? .OK : .RequestError,
                message:
                    "MAST size HEAD: Response received status=\(statusCode.map(String.init) ?? "none"), contentLength=\(contentLength ?? "unknown"), time=\(String(format: "%.3f", elapsed))s, url=\(url.absoluteString)"
            )
            guard
                error == nil,
                let httpResponse = response as? HTTPURLResponse,
                (200..<400).contains(httpResponse.statusCode)
            else {
                completion(nil)
                return
            }

            if let contentLength = httpResponse.value(forHTTPHeaderField: "Content-Length"),
                let size = Int64(contentLength), size > 0
            {
                completion(size)
                return
            }

            let expected = httpResponse.expectedContentLength
            completion(expected > 0 ? expected : nil)
        }.resume()
    }

    private func downloadURL(for productURL: String) -> URL? {
        if productURL.lowercased().hasPrefix("http") {
            let unescaped = productURL.replacingOccurrences(of: "&amp;", with: "&")
            let secureURL = unescaped.replacingOccurrences(of: "http://", with: "https://")
            return URL(string: secureURL)
        }

        return MASTRequest(searchType: .image).getFileDownloadUrl(
            service: .Download_file,
            parameters: ["uri": productURL]
        )
    }

    private func normalizeProductLocator(_ value: String) -> String {
        let unescaped = value
            .replacingOccurrences(of: "&amp;", with: "&")
        return (unescaped.removingPercentEncoding ?? unescaped).lowercased()
    }

    private static func int64Value(_ value: Any?) -> Int64? {
        if let int = value as? Int { return Int64(int) }
        if let int64 = value as? Int64 { return int64 }
        if let double = value as? Double { return Int64(double) }
        if let string = value as? String { return Int64(string) }
        return nil
    }
}
