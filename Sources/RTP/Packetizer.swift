import Foundation

// Sequencer is an internal glue protocol to allow a Packetizer to easily create Packets.
// It should not be created directly.
protocol Sequencer {
    var payloadType: PayloadType { get }
    var ssrc: SourceID { get }
    var sequenceNumber: SequenceNumber { get }
    var timestamp: Timestamp { get }

    mutating func nextSequenceNumber() -> SequenceNumber
}

// A Packetizer emits a sequence of RTP packets with monotonic sequence numbers.
public struct Packetizer: Sequencer {
    public let payloadType: PayloadType
    public let ssrc: SourceID
    public var sequenceNumber: SequenceNumber
    public var timestamp: Timestamp

    var payloader: Payloader {
        switch payloadType {
        default:
            return GenericPayloader()
        }
    }

    public init(
        for payloadType: PayloadType,
        ssrc: SourceID = .random(),
        sequenceNumber: SequenceNumber = SequenceNumber.random(),
        timestamp: Timestamp = Timestamp.random()
    ) {
        self.payloadType = payloadType
        self.ssrc = ssrc
        self.sequenceNumber = sequenceNumber
        self.timestamp = timestamp
    }

    mutating func nextSequenceNumber() -> SequenceNumber {
        let currentSequenceNumber = sequenceNumber
        (sequenceNumber, _) = sequenceNumber.addingReportingOverflow(1)
        return currentSequenceNumber
    }

    mutating func increment(_ samples: Timestamp) {
        (timestamp, _) = timestamp.addingReportingOverflow(samples)
    }

    public mutating func packetize(_ payload: Data, _ samples: Timestamp) throws -> [Packet] {
        let payloads = payloader.payload(payload)

        var packets: [Packet] = []
        for (index, payload) in payloads.enumerated() {
            let packet = try Packet(
                payloadType: payloadType,
                payload: payload,
                ssrc: ssrc,
                sequenceNumber: nextSequenceNumber(),
                timestamp: timestamp,
                marker: index == payloads.count - 1
            )
            packets.append(packet)
        }
        increment(samples)
        return packets
    }
}
