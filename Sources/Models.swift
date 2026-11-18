import Foundation
import UIKit

// MARK: - 提词器配置

struct PrompterConfig: Codable, Equatable {
    var fontSize: CGFloat = 88          // 字号（渲染坐标系 1280x720）
    var speed: CGFloat = 95             // 滚动速度：点/秒
    var lineSpacing: CGFloat = 1.5      // 行距倍数
    var mirrored = false                // 镜像（分光镜提词器用）
    var foregroundHex = "#FFFFFF"
    var backgroundHex = "#000000"

    var foreground: UIColor { UIColor(hex: foregroundHex) ?? .white }
    var background: UIColor { UIColor(hex: backgroundHex) ?? .black }
}

// MARK: - 口播稿

struct ScriptItem: Identifiable, Codable, Equatable {
    let id: UUID
    var title: String
    var text: String
    var createdAt: Date

    init(id: UUID = UUID(), title: String, text: String, createdAt: Date = Date()) {
        self.id = id
        self.title = title
        self.text = text
        self.createdAt = createdAt
    }
}

// MARK: - 测评模板（贴合房产测评口播工作流）

enum ScriptTemplate: String, CaseIterable, Identifiable {
    case layout = "户型测评"
    case lighting = "采光测评"
    case noise = "噪音测评"
    case delivery = "交付测评"
    case location = "配套测评"

    var id: String { rawValue }

    var sample: String {
        switch self {
        case .layout:
            return """
            今天这套【面积】平的房子，我实地走了一遍。
            先说户型，【几房几厅】，【朝向】。
            客厅开间【X】米，进深【X】米，
            实测面积【X】平，得房率大概【X】%。
            主卧【X】平，放两米床还剩【X】米过道。
            次卧【X】平，做儿童房刚好。
            厨房是【开放式/封闭式】，操作台长【X】米。
            两个卫生间，主卫【X】平，干湿分离【有/没有】。
            最大的问题是【痛点】，
            最惊喜的是【亮点】。
            评论区打户型，领这份户型的完整测评表。
            """
        case .lighting:
            return """
            这套房子采光，我用照度计实测了一整天。
            上午十点，客厅靠窗【X】勒克斯，
            进深三米处掉到【X】勒克斯。
            中午十二点，主卧【X】勒克斯，
            采光面宽【X】米，进深【X】米。
            下午三点，【房间名】已经需要开灯。
            楼间距目测【X】米，前面是【X】层。
            【冬至/夏至】日，直射光能进屋【X】小时。
            结论：【几居室采光达标，哪间偏暗】。
            评论区打采光，领这份实测照度记录。
            """
        case .noise:
            return """
            这套房子的噪音，我分三个时段测了。
            工作日上午十点，客厅关窗【X】分贝，
            开窗【X】分贝。
            晚高峰七点，靠马路一侧飙到【X】分贝。
            周五晚上，楼上脚步声明显。
            窗户是【几层中空玻璃】，实测隔音【X】分贝。
            主卧朝【小区内/马路】，夜间【X】分贝。
            临路房源，建议重点看【几号楼】。
            评论区打噪音，领这份分贝实测表。
            """
        case .delivery:
            return """
            这个盘是【现房/期房】，交付标准【精装/毛坯】。
            我按验房清单逐项过了。
            层高【X】米，实测净高【X】米。
            墙面空鼓，敲了【X】处。
            门窗是【品牌】，五金【品牌/型号】。
            地砖平整度，靠尺测最大缝隙【X】毫米。
            卫生间闭水试验做了【48】小时。
            水电点位【X】个，插座高度【X】厘米。
            最良心的是【用料/工艺】，
            最敷衍的是【减配项】。
            评论区打交付，领这份验房清单。
            """
        case .location:
            return """
            这个盘的位置，我按生活半径走了一遍。
            地铁【X】号线【站名】站，步行实测【X】分钟。
            自驾到【核心商圈】【X】公里，早高峰【X】分钟。
            学校是【学校名】，步行【X】分钟。
            菜市场在【X】，走路【X】分钟。
            医院【医院名】，车程【X】分钟。
            商业配套【商场名】，体量【X】万方。
            最大的短板是【短板】，
            最加分的是【亮点】。
            评论区打配套，领这份配套实测地图。
            """
        }
    }
}

// MARK: - 本地存储

final class ScriptStore: ObservableObject {
    @Published var scripts: [ScriptItem] = []
    @Published var config = PrompterConfig()

    private let scriptKey = "teleprompter.scripts.v1"
    private let configKey = "teleprompter.config.v1"

    init() { load() }

    func load() {
        if let data = UserDefaults.standard.data(forKey: scriptKey),
           let decoded = try? JSONDecoder().decode([ScriptItem].self, from: data) {
            scripts = decoded
        }
        if let data = UserDefaults.standard.data(forKey: configKey),
           let decoded = try? JSONDecoder().decode(PrompterConfig.self, from: data) {
            config = decoded
        }
    }

    func saveScripts() {
        if let data = try? JSONEncoder().encode(scripts) {
            UserDefaults.standard.set(data, forKey: scriptKey)
        }
    }

    func saveConfig() {
        if let data = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(data, forKey: configKey)
        }
    }

    func addScript(title: String, text: String) {
        let item = ScriptItem(title: title.isEmpty ? "未命名稿件" : title, text: text)
        scripts.insert(item, at: 0)
        saveScripts()
    }

    func deleteScript(_ item: ScriptItem) {
        scripts.removeAll { $0.id == item.id }
        saveScripts()
    }
}

// MARK: - 颜色工具

extension UIColor {
    convenience init?(hex: String) {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") { value.removeFirst() }
        guard value.count == 6 else { return nil }
        var number: UInt64 = 0
        guard Scanner(string: value).scanHexInt64(&number) else { return nil }
        let r = CGFloat((number & 0xFF0000) >> 16) / 255
        let g = CGFloat((number & 0x00FF00) >> 8) / 255
        let b = CGFloat(number & 0x0000FF) / 255
        self.init(red: r, green: g, blue: b, alpha: 1)
    }

    func hexString() -> String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}
