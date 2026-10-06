import AinkradAppKit
import Foundation
import GitMageFeature

@objc(GitMageEntryPoint)
final class GitMageEntryPoint: NSObject, AinkradPluginEntryPoint {
    static func app() -> any AinkradApp.Type {
        GitMageApp.self
    }
}
