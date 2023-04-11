import Foundation

private struct StartCodeIndex {
    let index: Int
    let byteCount: Int
}

enum NaluType: UInt8 {
    case stapA = 24
    case fuA = 28
    case fuB = 29
    case sei = 6
    case iFrame = 5
    case pFrame = 1
    case sps = 7
    case pps = 8
    case aud = 9
    case filler = 12
    case unknown = 0xFF
}

private enum Masks: UInt8 {
    case naluType = 0x1F
    case naluRefIdc = 0x60
    case fuStart = 0x80
    case fuEnd = 0x40
}

public struct H264Payloader: Payloader {
    let mtu: UInt16 = 1200

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

    func extractNaluType(_ nalu: Data) -> (NaluType, UInt8) {
        let rawValue = nalu.first! & Masks.naluType.rawValue
        let enumValue = NaluType(rawValue: rawValue) ?? NaluType.unknown
        return (enumValue, rawValue)
    }

    func packStapANalu(spsNalu: Data, ppsNalu: Data) -> Data {
        var stapAPayload = Data()
        let stapAHeader: UInt8 = 0x78
        stapAPayload.append(contentsOf: [stapAHeader])

        let spsLen = UInt16(spsNalu.count).bigEndian
        stapAPayload.append(spsLen.data)
        stapAPayload.append(spsNalu)
        let ppsLen = UInt16(ppsNalu.count).bigEndian
        stapAPayload.append(ppsLen.data)
        stapAPayload.append(ppsNalu)

        return stapAPayload
    }

    func splitFuANalu(_ nalu: Data) -> [Data] {
        var payloads: [Data] = []
        let (_, naluType) = extractNaluType(nalu)

        let fuaHeaderSize = 2
        let maxFragmentSize = Int(mtu) - fuaHeaderSize

        var naluDataIndex = 1
        var naluDataLength = nalu.count - naluDataIndex
        var naluDataRemaining = naluDataLength
        let naluRefIdc = nalu[0] & Masks.naluRefIdc.rawValue

        if min(maxFragmentSize, naluDataRemaining) <= 0 {
            return []
        }

        while naluDataRemaining > 0 {
            let currentFragmentSize = min(maxFragmentSize, naluDataRemaining)
            var out = Data()

            var firstByte = NaluType.fuA.rawValue | naluRefIdc
            out.append(contentsOf: [firstByte])

            var secondByte = naluType
            if naluDataRemaining == naluDataLength {
                // Start bit
                secondByte |= Masks.fuStart.rawValue
            } else if naluDataRemaining - currentFragmentSize == 0 {
                // End bit
                secondByte |= Masks.fuEnd.rawValue
            }
            out.append(contentsOf: [secondByte])
            out.append(nalu[naluDataIndex ..< (naluDataIndex + currentFragmentSize)])
            payloads.append(out)

            naluDataRemaining -= currentFragmentSize
            naluDataIndex += currentFragmentSize
        }
        return payloads
    }

    func payload(_ payload: Data) -> [Data] {
        var payloads: [Data] = []
        let nalus = splitNalus(payload)

        var spsNalu: Data?
        var ppsNalu: Data?

        for nalu in nalus {
            // Skip empty NALUs
            if nalu.count == 0 {
                continue
            }

            let (naluType, _) = extractNaluType(nalu)

            switch naluType {
            case .aud, .filler:
                continue
            case .sps:
                spsNalu = nalu
                continue
            case .pps:
                ppsNalu = nalu
                continue
            default:
                break
            }

            if let realSpsNalu = spsNalu,
               let realPpsNalu = ppsNalu
            {
                // Aggregate and PPS NALUs into STAP-A packets
                let stapAPayload = packStapANalu(
                    spsNalu: realSpsNalu,
                    ppsNalu: realPpsNalu
                )

                if stapAPayload.count <= mtu {
                    payloads.append(stapAPayload)
                }

                spsNalu = nil
                ppsNalu = nil
            }

            if nalu.count <= mtu {
                payloads.append(nalu)
            } else {
                let fuANalus = splitFuANalu(nalu)
                for p in fuANalus {
                    payloads.append(p)
                }
            }
        }

        return payloads
    }
}
