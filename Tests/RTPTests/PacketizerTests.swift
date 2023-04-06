import XCTest

@testable import RTP

class PacketizerTests: XCTestCase {
    func testIncrementOverflow() {
        var packetizer = RTP.Packetizer(for: .opus, sequenceNumber: .max, timestamp: .max)

        packetizer.increment(48000)
        XCTAssertEqual(packetizer.sequenceNumber, 0)
        XCTAssertEqual(packetizer.timestamp, 48000 - 1)

        packetizer.increment(48000)
        XCTAssertEqual(packetizer.sequenceNumber, 1)
        XCTAssertEqual(packetizer.timestamp, 48000 * 2 - 1)
    }

    func testOpusPacketize() throws {
        var packetizer = RTP.Packetizer(for: .opus, sequenceNumber: 0, timestamp: 0)

        let fakePayload = Data(count: 1000)
        
        // Make sure first packet does not throw
        XCTAssertNoThrow(try packetizer.packetize(fakePayload, 48000))

        // Capture second packet to assert against
        let packet = try packetizer.packetize(fakePayload, 48000)
        
        XCTAssertEqual(packet.payloadType, PayloadType.opus)
        XCTAssertEqual(packet.sequenceNumber, 1)
        XCTAssertEqual(packet.timestamp, 48000)
    }
}
