import Testing
import EyrieCore

struct RingBufferTests {
    @Test func appendBelowCapacity() {
        var buffer = RingBuffer<Int>(capacity: 5)
        buffer.append(1)
        buffer.append(2)
        #expect(buffer.elements == [1, 2])
        #expect(buffer.count == 2)
        #expect(buffer.last == 2)
    }

    @Test func wraparoundKeepsNewestInOrder() {
        var buffer = RingBuffer<Int>(capacity: 3)
        for value in 1...5 { buffer.append(value) }
        #expect(buffer.elements == [3, 4, 5])
        #expect(buffer.count == 3)
        #expect(buffer.last == 5)
    }

    @Test func exactCapacityBoundary() {
        var buffer = RingBuffer<Int>(capacity: 3)
        for value in 1...3 { buffer.append(value) }
        #expect(buffer.elements == [1, 2, 3])
        buffer.append(4)
        #expect(buffer.elements == [2, 3, 4])
    }

    @Test func removeAllResets() {
        var buffer = RingBuffer<Int>(capacity: 3)
        for value in 1...5 { buffer.append(value) }
        buffer.removeAll()
        #expect(buffer.isEmpty)
        #expect(buffer.last == nil)
        buffer.append(9)
        #expect(buffer.elements == [9])
    }
}
