import XCTest

@testable import RTP

class H264PayloaderTests: XCTestCase {
    func testIsAnnexBStartCode() {
        let payloader = H264Payloader()

        let case1: [UInt8] = [0x00, 0x00, 0x01]
        XCTAssertTrue(payloader.isAnnexBStartCode(case1))
        let case2: [UInt8] = [0x00, 0x00, 0x00, 0x01]
        XCTAssertTrue(payloader.isAnnexBStartCode(case2))

        let case3: [UInt8] = [0x00]
        XCTAssertFalse(payloader.isAnnexBStartCode(case3))
        let case4: [UInt8] = [0xFF, 0xFF, 0xFF]
        XCTAssertFalse(payloader.isAnnexBStartCode(case4))
        let case5: [UInt8] = [0xFF, 0xFF, 0xFF, 0xFF]
        XCTAssertFalse(payloader.isAnnexBStartCode(case5))
    }

    func testSplitNalus() {
        let payloader = H264Payloader()
        var naluPayload = Data()
        naluPayload.append(contentsOf: [0x00, 0x00, 0x01])
        naluPayload.append(Data(count: 1024))
        naluPayload.append(contentsOf: [0x00, 0x00, 0x00, 0x01])
        naluPayload.append(Data(count: 1024))

        let nalus = payloader.splitNalus(naluPayload)
        XCTAssertEqual(nalus.count, 2)
        XCTAssertEqual(nalus[0].count, 1024)
        XCTAssertEqual(nalus[1].count, 1024)
    }

    func testExtractNaluType() {
        let payloader = H264Payloader()

        let testCases: [UInt8: NaluType] = [
            0b0001_1000: NaluType.stapA,
            0b0001_1100: NaluType.fuA,
            0b0001_1101: NaluType.fuB,
            0b0000_0111: NaluType.sps,
            0b0000_1000: NaluType.pps,
            0b0000_1001: NaluType.aud,
            0b0000_1100: NaluType.filler,
            0b0000_1010: NaluType.unknown,
        ]
        for (header, expectedType) in testCases {
            var naluPayload = Data()
            naluPayload.append(contentsOf: [header])
            let (extractedNaluType, rawNaluType) = payloader.extractNaluType(naluPayload)
            XCTAssertEqual(extractedNaluType, expectedType)
            XCTAssertEqual(rawNaluType, header)
        }
    }

    func testPackStapANalu() {
        let payloader = H264Payloader()

        let ppsNalu = Data(count: 100)
        let spsNalu = Data(count: 100)

        let stapAPayload = payloader.packStapANalu(spsNalu: spsNalu, ppsNalu: ppsNalu)
        XCTAssertEqual(stapAPayload[0], 0x78) // Assert STAP-A header is first byte
        // header + spsLen + spsNaluLen + ppsLen + ppsNaluLen
        let expectedPayloadSize = 1 + 2 + spsNalu.count + 2 + ppsNalu.count
        XCTAssertEqual(stapAPayload.count, expectedPayloadSize) // Assert size of payload is correct

        // Ensure correct sizes are in the STAP-A packet for the PPS and SPS lengths
        XCTAssertEqual(stapAPayload[1], 0)
        XCTAssertEqual(stapAPayload[2], 100)
        XCTAssertEqual(stapAPayload[103], 0)
        XCTAssertEqual(stapAPayload[104], 100)
    }

    func testFuASplitter() {
        let payloader = H264Payloader()

        var nalu = Data()
        let naluType: UInt8 = 0b0000_0001
        let refIdc: UInt8 = 0b0010_0000
        let firstByte: UInt8 = naluType | refIdc
        nalu.append(contentsOf: [firstByte])
        nalu.append(Data(count: 3000))

        let fuANalus = payloader.splitFuANalu(nalu)
        XCTAssertEqual(fuANalus.count, 3)
        XCTAssertEqual(fuANalus[0].count, 1200)
        XCTAssertEqual(fuANalus[1].count, 1200)
        // (naluSize + (fuACount * fuAHeaderSize)) - ((fuACount - 1) * mtu)
        let expectedThirdNaluSize = (3000 + (3 * 2)) - ((3 - 1) * 1200)
        XCTAssertEqual(fuANalus[2].count, expectedThirdNaluSize)

        XCTAssertEqual(fuANalus[0][0], UInt8(0b0011_1100))
        let fuAStart: UInt8 = 0x80
        XCTAssertEqual(fuANalus[0][1], UInt8(fuAStart | naluType))

        XCTAssertEqual(fuANalus[1][0], UInt8(0b0011_1100))
        XCTAssertEqual(fuANalus[1][1], UInt8(naluType))

        XCTAssertEqual(fuANalus[2][0], UInt8(0b0011_1100))
        let fuAEnd: UInt8 = 0x40
        XCTAssertEqual(fuANalus[2][1], UInt8(fuAEnd | naluType))
    }

    func testSimpleH264Payloader() throws {
        guard let fixturePath = Bundle.module.url(forResource: "fixture", withExtension: "h264") else {
            XCTFail("missing H264 fixture file, can't run payloader test")
            return
        }

        let fixtureData = try Data(contentsOf: fixturePath)

        // Fixture constants
        let expectedPayloadCount = 63 // SEI + STAP-A + I-Frame + P-Frames

        let expectedSEICount = 1
        let expectedStapACount = 1
        let expectedIFrameCount = 1
        let expectedPFrameCount = 60

        let payloader = H264Payloader()
        let payloads = payloader.payload(fixtureData)
        XCTAssertEqual(payloads.count, expectedPayloadCount)
        var counts: [NaluType: Int] = [:]
        for p in payloads {
            let (naluType, _) = payloader.extractNaluType(p)
            if let count = counts[naluType] {
                counts[naluType] = count + 1
            } else {
                counts[naluType] = 1
            }
        }
        XCTAssertEqual(counts[NaluType.stapA], expectedStapACount)
        XCTAssertEqual(counts[NaluType.sei], expectedSEICount)
        XCTAssertEqual(counts[NaluType.iFrame], expectedIFrameCount)
        XCTAssertEqual(counts[NaluType.pFrame], expectedPFrameCount)
        XCTAssertNil(counts[NaluType.aud])
    }

    func testComplexH264Payload() throws {
        let payloader = H264Payloader()

        guard let fixturePath = Bundle.module.url(forResource: "complex_fixture", withExtension: "h264") else {
            XCTFail("missing H264 fixture file, can't run payloader test")
            return
        }

        let fixtureData = try Data(contentsOf: fixturePath)

        // Calculate expectations for the fixture
        var expectedFramePayloadCount = 0

        var nalus = payloader.splitNalus(fixtureData)
        for nalu in nalus {
            let (naluType, _) = payloader.extractNaluType(nalu)
            if naluType == NaluType.iFrame || naluType == NaluType.pFrame {
                expectedFramePayloadCount += Int(ceil(Double(nalu.count) / Double(payloader.mtu)))
            }
        }

        // STAP-A + I-Frames + P-Frames + FU-A Frames
        // expectedFramePayloadCount = I-Frames + P-Frames + FU-A Frames
        let expectedPayloadCount = 1 + expectedFramePayloadCount

        let payloads = payloader.payload(fixtureData)
        XCTAssertEqual(payloads.count, expectedPayloadCount)
    }
}
