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

    func testH264Payloader() {
        let payloader = H264Payloader()
        let _ = payloader.payload(Data(count: 1000))
    }
}
