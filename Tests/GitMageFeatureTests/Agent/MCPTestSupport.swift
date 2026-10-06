import AinkradAppKit
import Foundation

/// Records every payload the MCP tools forward, and answers with a fixed result
/// so the tests never touch a real repository.
@MainActor
final class RecordingForwarder {
    private(set) var payloads: [String] = []

    func forward(_ json: String) async -> AgentActionResult {
        payloads.append(json)
        return AgentActionResult(text: "ok", isError: false)
    }

    var lastObject: [String: Any]? {
        guard let json = payloads.last, let data = json.data(using: .utf8) else { return nil }
        return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
    }
}

// MARK: - helpers

@MainActor
func listedTools(_ server: MCPAppServer) async -> [[String: Any]] {
    let reply = await server.handle(#"{"jsonrpc":"2.0","id":1,"method":"tools/list"}"#)
    guard let data = reply.data(using: .utf8),
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
        let result = root["result"] as? [String: Any],
        let tools = result["tools"] as? [[String: Any]]
    else { return [] }
    return tools
}

@MainActor
func call(
    _ server: MCPAppServer, _ name: String,
    arguments: [String: Any]
) async -> (text: String, isError: Bool) {
    let params: [String: Any] = ["name": name, "arguments": arguments]
    let request: [String: Any] = ["jsonrpc": "2.0", "id": 7, "method": "tools/call", "params": params]
    let data = try! JSONSerialization.data(withJSONObject: request)
    let reply = await server.handle(String(decoding: data, as: UTF8.self))
    guard let replyData = reply.data(using: .utf8),
        let root = (try? JSONSerialization.jsonObject(with: replyData)) as? [String: Any],
        let result = root["result"] as? [String: Any],
        let content = result["content"] as? [[String: Any]]
    else {
        return ("<no result>", true)
    }
    return (content.first?["text"] as? String ?? "", result["isError"] as? Bool ?? false)
}

func destructiveHint(_ tool: [String: Any]) -> Bool {
    (tool["annotations"] as? [String: Any])?["destructiveHint"] as? Bool ?? false
}
