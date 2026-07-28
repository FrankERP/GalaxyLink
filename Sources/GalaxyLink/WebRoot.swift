import Foundation

enum WebRoot {
    static func url() -> URL? {
        Bundle.module.url(forResource: "web", withExtension: nil)
    }
}
