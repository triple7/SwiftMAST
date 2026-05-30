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

        fetchProductFileSizes(for: results) { productSizes in
            var enriched = results.map { coam -> CoamResult in
                coam.withFileSizes(
                    dataURLSizeBytes: self.productSize(for: coam.dataURL, in: productSizes),
                    jpegURLSizeBytes: self.productSize(for: coam.jpegURL, in: productSizes)
                )
            }

            self.fetchMissingHeaderSizes(for: enriched) { headerSizes in
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

        for chunk in chunks {
            group.enter()
            fetchProductFileSizes(forObsids: chunk) { sizes in
                lock.lock()
                output.append(contentsOf: sizes)
                lock.unlock()
                group.leave()
            }
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

        URLSession.shared.dataTask(with: url) { data, response, error in
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

        let group = DispatchGroup()
        let lock = NSLock()
        var sizes = [String: Int64]()

        for productURL in missingURLs {
            group.enter()
            fetchContentLength(for: productURL) { size in
                if let size {
                    lock.lock()
                    sizes[productURL] = size
                    lock.unlock()
                }
                group.leave()
            }
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

        URLSession.shared.dataTask(with: request) { _, response, error in
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
