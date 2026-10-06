import AinkradAppKit
import SwiftUI

/// A lightweight, language-agnostic syntax highlighter for diff code lines.
/// Not a full parser — it colors strings, comments, numbers, and a broad set
/// of common keywords across C-like / Swift / JS / Python / Go, which is enough
/// to read like GitHub's diff view. Per-line only (no multi-line block state).
enum SyntaxHighlighter {
    private enum Kind { case plain, keyword, string, comment, number }

    private static let keywords: Set<String> = [
        "func", "let", "var", "class", "struct", "enum", "protocol", "extension", "import",
        "return", "if", "else", "for", "while", "switch", "case", "default", "break", "continue",
        "guard", "defer", "do", "try", "catch", "throw", "throws", "async", "await", "in", "is", "as",
        "public", "private", "internal", "fileprivate", "static", "final", "override", "mutating",
        "self", "super", "nil", "true", "false", "init", "deinit", "where", "some", "any", "typealias",
        "def", "function", "const", "int", "void", "new", "this", "null", "undefined", "typeof",
        "package", "type", "interface", "map", "range", "go", "chan", "select", "from", "with",
        "lambda", "yield", "None", "True", "False", "and", "or", "not", "elif", "print", "using",
        "namespace", "template", "virtual", "operator", "unsigned", "signed", "bool", "double", "float", "long", "char",
    ]

    private static func color(_ kind: Kind, _ tokens: HostThemeTokens, _ skin: AinkradSkin) -> Color {
        // The skin's syntax hues are toned for the surface they sit on.
        let onDark = tokens.background.relativeLuminance < 0.5
        switch kind {
        case .keyword: return skin.color(skin.syntax.color(.keyword, onDark: onDark))
        case .string: return skin.color(skin.syntax.color(.string, onDark: onDark))
        case .comment: return skin.color(skin.syntax.color(.comment, onDark: onDark))
        case .number: return skin.color(skin.syntax.color(.number, onDark: onDark))
        case .plain: return tokens.foreground.opacity(skin.opacity.o88)
        }
    }

    static func highlight(_ code: String, tokens: HostThemeTokens, skin: AinkradSkin) -> AttributedString {
        var result = AttributedString()
        let chars = Array(code)
        let n = chars.count
        var i = 0

        func emit(_ text: String, _ kind: Kind) {
            var piece = AttributedString(text)
            piece.foregroundColor = color(kind, tokens, skin)
            result += piece
        }

        while i < n {
            let c = chars[i]

            // Line comments: // … , # … , -- … , ; …
            if (c == "/" && i + 1 < n && chars[i + 1] == "/")
                || c == "#"
                || (c == "-" && i + 1 < n && chars[i + 1] == "-")
                || c == ";"
            {
                emit(String(chars[i...]), .comment)
                break
            }

            // Strings: " … " , ' … ' , ` … `
            if c == "\"" || c == "'" || c == "`" {
                var j = i + 1
                while j < n {
                    if chars[j] == "\\" {
                        j += 2
                        continue
                    }
                    if chars[j] == c { break }
                    j += 1
                }
                let end = min(j, n - 1)
                emit(String(chars[i...end]), .string)
                i = end + 1
                continue
            }

            // Numbers
            if c.isNumber {
                var j = i
                while j < n,
                    chars[j].isNumber || chars[j] == "." || chars[j] == "_"
                        || chars[j] == "x" || (chars[j].isHexDigit && j > i)
                {
                    j += 1
                }
                emit(String(chars[i..<j]), .number)
                i = j
                continue
            }

            // Identifiers / keywords
            if c.isLetter || c == "_" {
                var j = i
                while j < n, chars[j].isLetter || chars[j].isNumber || chars[j] == "_" { j += 1 }
                let word = String(chars[i..<j])
                emit(word, keywords.contains(word) ? .keyword : .plain)
                i = j
                continue
            }

            emit(String(c), .plain)
            i += 1
        }
        return result
    }
}
