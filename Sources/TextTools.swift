import Foundation

// MARK: - 断句与折行（贴合口播节奏）

enum TextTools {

    /// 按标点优先断句，长句按字数硬折。返回适合逐行滚动阅读的行数组。
    static func wrap(_ text: String, maxChars: Int) -> [String] {
        guard maxChars > 3 else { return text.isEmpty ? [""] : [text] }

        var result: [String] = []
        let paragraphs = text.components(separatedBy: .newlines)

        for paragraph in paragraphs {
            let trimmed = paragraph.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                result.append("")
                continue
            }

            // 先按句末标点切分
            var sentences: [String] = []
            var buffer = ""
            for ch in trimmed {
                buffer.append(ch)
                if isSentenceEnd(ch) {
                    sentences.append(buffer)
                    buffer = ""
                }
            }
            if !buffer.isEmpty { sentences.append(buffer) }

            // 再对每句按字数折行（按字符，中文友好）
            for sentence in sentences {
                let chars = Array(sentence)
                if chars.count <= maxChars {
                    result.append(sentence)
                    continue
                }
                var start = 0
                while start < chars.count {
                    let end = min(start + maxChars, chars.count)
                    result.append(String(chars[start..<end]))
                    start = end
                }
            }
        }
        return result.isEmpty ? [""] : result
    }

    /// 根据字号和渲染宽度估算每行最大字数
    static func suggestedMaxChars(fontSize: CGFloat, width: CGFloat = 1280, margin: CGFloat = 120) -> Int {
        let usable = width - margin
        return max(6, Int(usable / fontSize))
    }

    /// 生成带停顿提示的排版（在句末加轻微停顿空行，便于跟读）
    static func withPauses(_ text: String) -> String {
        var out = ""
        for ch in text {
            out.append(ch)
            if isSentenceEnd(ch) { out.append("\n") }
        }
        return out
    }

    private static func isSentenceEnd(_ ch: Character) -> Bool {
        switch ch {
        case "。", "！", "？", "；", ".", "!", "?", ";":
            return true
        default:
            return false
        }
    }
}
