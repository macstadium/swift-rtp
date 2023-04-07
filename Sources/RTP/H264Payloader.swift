import Foundation

private struct StartCodeIndex {
    let index: Int
    let byteCount: Int
}

public struct H264Payloader: Payloader {
    let mtu: UInt64 = 1400

    var spsNalu: Data?
    var ppsNalu: Data?

    func isAnnexBStartCode(_ bytes: [UInt8]) -> Bool {
        if bytes.count == 3 {
            return bytes == [0x00, 0x00, 0x01]
        } else if bytes.count == 4 {
            return bytes == [0x00, 0x00, 0x00, 0x01]
        } else {
            return false
        }
    }

    func splitNalus(_ payload: Data) -> [Data] {
        var nalus: [Data] = []

        var startCodeIndices: [StartCodeIndex] = []

        var i = 0
        while i < payload.count {
            let bytesLeftToParse = payload.count - i
            if bytesLeftToParse >= 4, isAnnexBStartCode([payload[i], payload[i + 1], payload[i + 2], payload[i + 3]]) {
                let idx = StartCodeIndex(index: i, byteCount: 4)
                startCodeIndices.append(idx)
                i += 4
            } else if bytesLeftToParse >= 3, isAnnexBStartCode([payload[i], payload[i + 1], payload[i + 2]]) {
                let idx = StartCodeIndex(index: i, byteCount: 3)
                startCodeIndices.append(idx)
                i += 3
            } else {
                i += 1
            }
        }

        for i in 0 ..< startCodeIndices.count {
            var nalu: Data
            if i == (startCodeIndices.count - 1) {
                let currentIndex = startCodeIndices[i]

                let dataStart = currentIndex.index + currentIndex.byteCount
                let dataEnd = payload.count

                nalu = payload[dataStart ..< dataEnd]
            } else {
                let currentIndex = startCodeIndices[i]
                let nextIndex = startCodeIndices[i + 1]

                let dataStart = currentIndex.index + currentIndex.byteCount
                let dataEnd = nextIndex.index

                nalu = payload[dataStart ..< dataEnd]
            }
            nalus.append(nalu)
        }

        return nalus
    }

    func payload(_ payload: Data) -> [Data] {
        let nalus = splitNalus(payload)

        for nalu in nalus {}

        return []
    }
}
