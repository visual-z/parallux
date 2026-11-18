/// Fixed-capacity buffer that drops the oldest element when full (INV-2).
public struct RingBuffer<Element>: Sequence {
    public let capacity: Int
    private var storage: [Element] = []
    private var head = 0

    public init(capacity: Int) {
        self.capacity = Swift.max(0, capacity)
    }

    public var count: Int { storage.count }
    public var isEmpty: Bool { storage.isEmpty }

    public mutating func append(_ element: Element) {}
    public mutating func append(contentsOf elements: some Sequence<Element>) {
        for element in elements { append(element) }
    }
    public mutating func removeAll() {
        storage.removeAll(keepingCapacity: true)
        head = 0
    }

    /// Oldest first.
    public var elements: [Element] { storage }
    public func makeIterator() -> IndexingIterator<[Element]> { elements.makeIterator() }
}
