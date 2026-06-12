import Foundation
import ServiceManagement

// LoginItem：开机自启(SMAppService 登录项)。需 .app 有签名身份；dev(swift run)会抛错，忽略。
enum LoginItem {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    static func setEnabled(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("horae login item: %@", String(describing: error))
        }
    }
}
