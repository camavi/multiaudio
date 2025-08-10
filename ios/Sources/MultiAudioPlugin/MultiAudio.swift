import Foundation

@objc public class MultiAudio: NSObject {
    @objc public func echo(_ value: String) -> String {
        print(value)
        return value
    }
}
