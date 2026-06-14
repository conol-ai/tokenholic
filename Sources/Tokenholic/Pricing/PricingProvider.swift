import Foundation

/// Loads the per-model price table, mirroring ccusage's source of truth.
///
/// Resolution order: fresh on-disk cache (< 24h) → live LiteLLM JSON (then
/// cached) → stale cache → embedded snapshot. The embedded snapshot is always
/// merged underneath so even a partial/old live table can't drop a known model.
enum PricingProvider {
    static let sourceURL = URL(string:
        "https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json")!
    static let cacheTTL: TimeInterval = 24 * 3600

    private static var cacheFile: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Tokenholic", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("litellm_prices.json")
    }

    /// Synchronous (blocking) load — call off the main thread.
    static func loadTable(allowNetwork: Bool = true, networkTimeout: TimeInterval = 8) -> [String: ModelPrice] {
        let file = cacheFile

        // 1. Fresh disk cache.
        if let mod = (try? FileManager.default.attributesOfItem(atPath: file.path))?[.modificationDate] as? Date,
           Date().timeIntervalSince(mod) < cacheTTL,
           let data = try? Data(contentsOf: file) {
            let table = parse(data)
            if !table.isEmpty { return merged(table) }
        }

        // 2. Live fetch (then persist).
        if allowNetwork, let data = fetchSync(networkTimeout) {
            let table = parse(data)
            if !table.isEmpty {
                try? data.write(to: file)
                return merged(table)
            }
        }

        // 3. Stale disk cache, better than nothing.
        if let data = try? Data(contentsOf: file) {
            let table = parse(data)
            if !table.isEmpty { return merged(table) }
        }

        // 4. Embedded snapshot.
        return EmbeddedPricing.table
    }

    /// Live table layered on top of the embedded snapshot.
    private static func merged(_ live: [String: ModelPrice]) -> [String: ModelPrice] {
        var out = EmbeddedPricing.table
        for (key, value) in live { out[key] = value }
        return out
    }

    private static func fetchSync(_ timeout: TimeInterval) -> Data? {
        var request = URLRequest(url: sourceURL)
        request.timeoutInterval = timeout
        let semaphore = DispatchSemaphore(value: 0)
        var result: Data?
        let task = URLSession.shared.dataTask(with: request) { data, response, _ in
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                result = data
            }
            semaphore.signal()
        }
        task.resume()
        _ = semaphore.wait(timeout: .now() + timeout + 2)
        return result
    }

    /// Parse the LiteLLM JSON into per-token prices.
    static func parse(_ data: Data) -> [String: ModelPrice] {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return [:] }
        var out: [String: ModelPrice] = [:]
        for (key, value) in root {
            guard let entry = value as? [String: Any],
                  let input = (entry["input_cost_per_token"] as? NSNumber)?.doubleValue,
                  let output = (entry["output_cost_per_token"] as? NSNumber)?.doubleValue
            else { continue }
            let cacheRead = (entry["cache_read_input_token_cost"] as? NSNumber)?.doubleValue ?? input * 0.1
            let cacheWrite5m = (entry["cache_creation_input_token_cost"] as? NSNumber)?.doubleValue ?? input * 1.25
            let cacheWrite1h = (entry["cache_creation_input_token_cost_above_1hr"] as? NSNumber)?.doubleValue ?? cacheWrite5m
            out[key] = ModelPrice(
                inputPerToken: input,
                outputPerToken: output,
                cacheReadPerToken: cacheRead,
                cacheWrite5mPerToken: cacheWrite5m,
                cacheWrite1hPerToken: cacheWrite1h
            )
        }
        return out
    }
}
