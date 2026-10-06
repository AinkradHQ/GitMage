import AinkradAppKit
import os

/// The module's loggers, one per area, all under the shared Ainkrad subsystem
/// (`AinkradLog`) so a single Console filter covers the host and Git Mage.
enum Log {
    static let store = AinkradLog.logger(app: "gitmage", area: "store")
    static let forge = AinkradLog.logger(app: "gitmage", area: "forge")
    static let persistence = AinkradLog.logger(app: "gitmage", area: "persistence")
}
