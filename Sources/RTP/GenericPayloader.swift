import Foundation

public struct GenericPayloader: Payloader {
    let mtu: UInt64 = 0

    func payload(_ payload: Data) -> [Data] {
        return [Data(payload)]
    }
}
