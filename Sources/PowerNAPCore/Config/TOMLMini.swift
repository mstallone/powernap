import Foundation

public indirect enum TOMLValue: Sendable, Equatable {
    case string(String)
    case integer(Int64)
    case double(Double)
    case bool(Bool)
    case array([TOMLValue])
    case table([String: TOMLValue])

    public var stringValue: String? { if case let .string(s) = self { return s } else { return nil } }
    public var intValue: Int? {
        if case let .integer(n) = self { return Int(n) }
        if case let .double(d) = self { return Int(d) }
        return nil
    }
    public var boolValue: Bool? { if case let .bool(b) = self { return b } else { return nil } }
    public var arrayValue: [TOMLValue]? { if case let .array(a) = self { return a } else { return nil } }
    public var tableValue: [String: TOMLValue]? { if case let .table(t) = self { return t } else { return nil } }
}

public enum TOMLMiniError: Swift.Error, LocalizedError {
    case syntaxError(line: Int, message: String)
    case unexpectedValue(line: Int, message: String)

    public var errorDescription: String? {
        switch self {
        case .syntaxError(let line, let message): return "TOML syntax error line \(line): \(message)"
        case .unexpectedValue(let line, let message): return "TOML value error line \(line): \(message)"
        }
    }
}

public enum TOMLMini {

    public static func parse(_ input: String) throws -> [String: TOMLValue] {
        var root: [String: TOMLValue] = [:]
        var currentPath: [String] = []
        var currentIsArray = false

        let lines = input.components(separatedBy: .newlines)
        var lineNumber = 0
        for rawLine in lines {
            lineNumber += 1
            let line = stripInlineComment(rawLine).trimmingCharacters(in: .whitespaces)
            if line.isEmpty { continue }

            if line.hasPrefix("[[") && line.hasSuffix("]]") {
                let inner = String(line.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespaces)
                guard !inner.isEmpty else {
                    throw TOMLMiniError.syntaxError(line: lineNumber, message: "empty array table header")
                }
                let path = inner.split(separator: ".").map { $0.trimmingCharacters(in: .whitespaces) }
                currentPath = path
                currentIsArray = true
                try ensureArrayTable(in: &root, path: path, lineNumber: lineNumber)
                continue
            }

            if line.hasPrefix("[") && line.hasSuffix("]") {
                let inner = String(line.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                guard !inner.isEmpty else {
                    throw TOMLMiniError.syntaxError(line: lineNumber, message: "empty table header")
                }
                let path = inner.split(separator: ".").map { $0.trimmingCharacters(in: .whitespaces) }
                currentPath = path
                currentIsArray = false
                try ensureTable(in: &root, path: path, lineNumber: lineNumber)
                continue
            }

            guard let equalsIdx = line.firstIndex(of: "=") else {
                throw TOMLMiniError.syntaxError(line: lineNumber, message: "no '=' in key/value pair")
            }
            let key = line[line.startIndex..<equalsIdx].trimmingCharacters(in: .whitespaces)
            let valueStr = line[line.index(after: equalsIdx)..<line.endIndex].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else {
                throw TOMLMiniError.syntaxError(line: lineNumber, message: "empty key")
            }
            let value = try parseValue(valueStr, line: lineNumber)
            try setKey(in: &root, path: currentPath, key: key, value: value, isArrayTable: currentIsArray, lineNumber: lineNumber)
        }
        return root
    }

    private static func stripInlineComment(_ s: String) -> String {
        var inString = false
        var escaped = false
        var result = ""
        for ch in s {
            if escaped {
                result.append(ch)
                escaped = false
                continue
            }
            if ch == "\\" && inString {
                result.append(ch)
                escaped = true
                continue
            }
            if ch == "\"" {
                inString.toggle()
                result.append(ch)
                continue
            }
            if ch == "#" && !inString {
                break
            }
            result.append(ch)
        }
        return result
    }

    private static func parseValue(_ s: String, line: Int) throws -> TOMLValue {
        if s.hasPrefix("\"") && s.hasSuffix("\"") && s.count >= 2 {
            let inner = String(s.dropFirst().dropLast())
            return .string(unescape(inner))
        }
        if s == "true" { return .bool(true) }
        if s == "false" { return .bool(false) }
        if let i = Int64(s) { return .integer(i) }
        if let d = Double(s) { return .double(d) }
        if s.hasPrefix("[") && s.hasSuffix("]") {
            let inner = String(s.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
            if inner.isEmpty { return .array([]) }
            let parts = splitArrayItems(inner)
            var items: [TOMLValue] = []
            for part in parts {
                items.append(try parseValue(part.trimmingCharacters(in: .whitespaces), line: line))
            }
            return .array(items)
        }
        throw TOMLMiniError.unexpectedValue(line: line, message: "unrecognized value: \(s)")
    }

    private static func splitArrayItems(_ s: String) -> [String] {
        var result: [String] = []
        var current = ""
        var inString = false
        var escaped = false
        var depth = 0
        for ch in s {
            if escaped {
                current.append(ch)
                escaped = false
                continue
            }
            if inString {
                if ch == "\\" { escaped = true; current.append(ch); continue }
                if ch == "\"" { inString = false }
                current.append(ch)
                continue
            }
            if ch == "\"" { inString = true; current.append(ch); continue }
            if ch == "[" { depth += 1; current.append(ch); continue }
            if ch == "]" { depth -= 1; current.append(ch); continue }
            if ch == "," && depth == 0 {
                result.append(current)
                current = ""
                continue
            }
            current.append(ch)
        }
        if !current.trimmingCharacters(in: .whitespaces).isEmpty {
            result.append(current)
        }
        return result
    }

    private static func unescape(_ s: String) -> String {
        var out = ""
        var iter = s.makeIterator()
        while let ch = iter.next() {
            if ch == "\\" {
                if let next = iter.next() {
                    switch next {
                    case "n": out.append("\n")
                    case "t": out.append("\t")
                    case "r": out.append("\r")
                    case "\\": out.append("\\")
                    case "\"": out.append("\"")
                    default: out.append(next)
                    }
                }
            } else {
                out.append(ch)
            }
        }
        return out
    }

    private static func ensureTable(in root: inout [String: TOMLValue], path: [String], lineNumber: Int) throws {
        try mutateTable(&root, path: path) { table in
        }
    }

    private static func ensureArrayTable(in root: inout [String: TOMLValue], path: [String], lineNumber: Int) throws {
        guard !path.isEmpty else { return }
        let parentPath = Array(path.dropLast())
        let last = path.last!
        try mutateTable(&root, path: parentPath) { table in
            var arr: [TOMLValue] = []
            if let existing = table[last], case let .array(a) = existing { arr = a }
            arr.append(.table([:]))
            table[last] = .array(arr)
        }
    }

    private static func setKey(
        in root: inout [String: TOMLValue],
        path: [String],
        key: String,
        value: TOMLValue,
        isArrayTable: Bool,
        lineNumber: Int
    ) throws {
        if path.isEmpty {
            root[key] = value
            return
        }
        if isArrayTable {
            let parentPath = Array(path.dropLast())
            let last = path.last!
            try mutateTable(&root, path: parentPath) { table in
                guard case var .array(arr) = table[last] ?? .array([]) else {
                    table[last] = .array([.table([key: value])])
                    return
                }
                if arr.isEmpty {
                    arr.append(.table([key: value]))
                } else {
                    let idx = arr.count - 1
                    if case var .table(t) = arr[idx] {
                        t[key] = value
                        arr[idx] = .table(t)
                    } else {
                        arr.append(.table([key: value]))
                    }
                }
                table[last] = .array(arr)
            }
        } else {
            try mutateTable(&root, path: path) { table in
                table[key] = value
            }
        }
    }

    private static func mutateTable(
        _ root: inout [String: TOMLValue],
        path: [String],
        body: (inout [String: TOMLValue]) -> Void
    ) throws {
        if path.isEmpty {
            body(&root)
            return
        }
        let head = path.first!
        let rest = Array(path.dropFirst())
        var child: [String: TOMLValue]
        if let existing = root[head] {
            switch existing {
            case .table(let t):
                child = t
            case .array(var a):
                if rest.isEmpty {
                    var t: [String: TOMLValue] = [:]
                    body(&t)
                    if case var .table(lastTable) = a.last ?? .table([:]) {
                        for (k, v) in t { lastTable[k] = v }
                        a[a.count - 1] = .table(lastTable)
                    } else {
                        a.append(.table(t))
                    }
                    root[head] = .array(a)
                    return
                } else {
                    var lastTable: [String: TOMLValue] = [:]
                    if case let .table(t) = a.last ?? .table([:]) { lastTable = t }
                    try mutateTableInner(&lastTable, path: rest, body: body)
                    if a.isEmpty {
                        a.append(.table(lastTable))
                    } else {
                        a[a.count - 1] = .table(lastTable)
                    }
                    root[head] = .array(a)
                    return
                }
            default:
                child = [:]
            }
        } else {
            child = [:]
        }
        try mutateTableInner(&child, path: rest, body: body)
        root[head] = .table(child)
    }

    private static func mutateTableInner(
        _ table: inout [String: TOMLValue],
        path: [String],
        body: (inout [String: TOMLValue]) -> Void
    ) throws {
        if path.isEmpty {
            body(&table)
            return
        }
        var root = table
        try mutateTable(&root, path: path, body: body)
        table = root
    }
}
