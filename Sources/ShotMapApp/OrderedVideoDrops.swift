import Foundation

/// Item providers can finish in any order. Keep each drop's original order and
/// the order of consecutive drops, then add ready batches to the UI together.
/// Only URL slots are retained; completed or cancelled batches release them.
struct OrderedVideoDrops {
    struct Completion {
        let urls: [URL]
        let failedCount: Int
    }
    private struct Batch {
        let id: UUID
        var urls: [URL?]
        var resolved: [Bool]
        var remaining: Int
    }

    private var batches: [Batch] = []
    var isEmpty: Bool { batches.isEmpty }

    mutating func register(count: Int) -> UUID? {
        guard count > 0 else { return nil }
        let id = UUID()
        batches.append(Batch(id: id, urls: Array(repeating: nil, count: count),
                             resolved: Array(repeating: false, count: count), remaining: count))
        return id
    }

    func isPending(_ batchID: UUID) -> Bool {
        batches.contains { $0.id == batchID && $0.remaining > 0 }
    }

    mutating func resolve(_ url: URL?, at index: Int, batchID: UUID) -> Completion? {
        guard let batch = batches.firstIndex(where: { $0.id == batchID }),
              batches[batch].urls.indices.contains(index), !batches[batch].resolved[index] else { return nil }
        batches[batch].urls[index] = url
        batches[batch].resolved[index] = true
        batches[batch].remaining -= 1
        return flushReadyBatches()
    }

    mutating func expire(_ batchID: UUID) -> Completion? {
        guard let batch = batches.firstIndex(where: { $0.id == batchID }) else { return nil }
        batches[batch].resolved = Array(repeating: true, count: batches[batch].urls.count)
        batches[batch].remaining = 0
        return flushReadyBatches()
    }

    private mutating func flushReadyBatches() -> Completion? {
        guard batches.first?.remaining == 0 else { return nil }
        let readyCount = batches.prefix { $0.remaining == 0 }.count
        let readyURLs = batches.prefix(readyCount).flatMap { $0.urls.compactMap { $0 } }
        let totalCount = batches.prefix(readyCount).reduce(0) { $0 + $1.urls.count }
        batches.removeFirst(readyCount)
        return Completion(urls: readyURLs, failedCount: totalCount - readyURLs.count)
    }

    mutating func cancelAll() {
        batches.removeAll()
    }
}
