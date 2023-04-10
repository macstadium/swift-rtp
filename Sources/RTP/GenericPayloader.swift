import Foundation

public struct GenericPayloader: Payloader {
    let mtu: UInt16 = 0

    func payload(_ payload: Data) -> [Data] {
        [Data(payload)]
    }
}
