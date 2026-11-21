import Foundation
import JTCopilotCore

enum ZhipuError: LocalizedError {
    case missingApiKey
    case invalidResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingApiKey:
            return "未配置智谱 API Key。"
        case .invalidResponse(let message):
            return message
        }
    }
}

final class ZhipuSpeechRecognitionProvider {
    private let endpoint = URL(string: "https://open.bigmodel.cn/api/paas/v4/audio/transcriptions")!
    private let model = "glm-asr-2512"
    private let apiKeyStore: ZhipuApiKeyStore
    private let session: URLSession

    init(apiKeyStore: ZhipuApiKeyStore) {
        self.apiKeyStore = apiKeyStore
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: configuration)
    }

    func transcribe(wavData: Data, transcriptContext: String) async throws -> String {
        guard !wavData.isEmpty else { return "" }
        guard let apiKey = apiKeyStore.apiKey() else {
            throw ZhipuError.missingApiKey
        }

        var lastError: Error?

        for attempt in 1...2 {
            do {
                let request = makeRequest(apiKey: apiKey, wavData: wavData, transcriptContext: transcriptContext)
                let (data, response) = try await session.data(for: request)
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw ZhipuError.invalidResponse("智谱语音识别返回了无效响应。")
                }

                let body = String(data: data, encoding: .utf8) ?? ""

                if (200..<300).contains(httpResponse.statusCode) {
                    return parseTranscription(body: body, contentType: httpResponse.value(forHTTPHeaderField: "Content-Type"))
                }

                let message = extractErrorMessage(body)
                let status = httpResponse.statusCode
                if attempt == 1 && (status == 429 || status >= 500) {
                    try await Task.sleep(nanoseconds: 450_000_000)
                    continue
                }

                throw ZhipuError.invalidResponse("智谱语音识别失败（\(status)）：\(message)")
            } catch {
                lastError = error
                if attempt == 1, error is URLError {
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    continue
                }
                throw error
            }
        }

        throw lastError ?? ZhipuError.invalidResponse("智谱语音识别失败。")
    }

    private func makeRequest(apiKey: String, wavData: Data, transcriptContext: String) -> URLRequest {
        let boundary = "Boundary-\(UUID().uuidString)"
        var body = Data()

        func append(_ value: String) {
            if let data = value.data(using: .utf8) {
                body.append(data)
            }
        }

        func appendField(name: String, value: String) {
            append("--\(boundary)\r\n")
            append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            append("\(value)\r\n")
        }

        appendField(name: "model", value: model)
        appendField(name: "stream", value: "true")

        if !transcriptContext.isEmpty {
            let clipped = String(transcriptContext.suffix(6_000))
            appendField(name: "prompt", value: clipped)
        }

        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"file\"; filename=\"segment.wav\"\r\n")
        append("Content-Type: audio/wav\r\n\r\n")
        body.append(wavData)
        append("\r\n--\(boundary)--\r\n")

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        return request
    }

    private func parseTranscription(body: String, contentType: String?) -> String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)

        if (contentType?.contains("event-stream") == true) || trimmed.hasPrefix("data:") {
            var completed = ""
            for rawLine in body.split(separator: "\n") {
                let line = String(rawLine).trimmingCharacters(in: .whitespaces)
                guard line.hasPrefix("data:") else { continue }

                let payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
                guard !payload.isEmpty, payload != "[DONE]" else { continue }

                guard let data = payload.data(using: .utf8),
                      let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    continue
                }

                if object["type"] as? String == "transcript.text.done",
                   let text = object["text"] as? String {
                    completed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                }
            }
            return completed
        }

        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let text = object["text"] as? String else {
            return ""
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func extractErrorMessage(_ body: String) -> String {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return "未知错误"
        }
        return message
    }
}

final class ZhipuWritingModelProvider {
    private let endpoint = URL(string: "https://open.bigmodel.cn/api/paas/v4/chat/completions")!
    private let guidanceModel = "glm-4.5-air"
    private let editingModel = "glm-4.6"
    private let apiKeyStore: ZhipuApiKeyStore
    private let session: URLSession

    init(apiKeyStore: ZhipuApiKeyStore) {
        self.apiKeyStore = apiKeyStore
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 120
        self.session = URLSession(configuration: configuration)
    }

    var isConfigured: Bool {
        apiKeyStore.hasApiKey
    }

    func streamNextSentence(
        transcript: String,
        previousNextSentence: String,
        onTextChanged: @escaping (String) -> Void
    ) async throws -> String {
        guard let apiKey = apiKeyStore.apiKey() else {
            throw ZhipuError.missingApiKey
        }

        let body = StreamChatRequest(
            model: guidanceModel,
            messages: [
                ChatMessage(
                    role: "system",
                    content: "你是实时口述写作的接续助手。根据当前会话全文判断用户正在写什么，"
                        + "直接写出紧接着最自然的一句中文。适用于日志、复盘、会议纪要、邮件、方案、需求、"
                        + "笔记、说明等任何写作类型，禁止套用固定章节或管理模板。"
                        + "只输出这一句，不加标题、解释、序号或引号；控制在80字以内；"
                        + "可以承接未说完的意思，但不得虚构用户没有提供的事实。"
                ),
                ChatMessage(
                    role: "user",
                    content: "上一版下一句（仅用于保持衔接，可完全改写）：\(clip(previousNextSentence, maxLength: 300))"
                        + "\n当前全文：\(clip(transcript))"
                )
            ],
            temperature: 0.3,
            stream: true,
            maxTokens: 180,
            thinking: Thinking(type: "disabled")
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ZhipuError.invalidResponse("智谱下一句返回了无效响应。")
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ZhipuError.invalidResponse("智谱下一句生成失败（\(httpResponse.statusCode)）。")
        }

        var accumulated = ""
        for try await line in bytes.lines {
            guard line.hasPrefix("data:") else { continue }
            let payload = String(line.dropFirst(5))
                .trimmingCharacters(in: .whitespaces)
            guard !payload.isEmpty, payload != "[DONE]" else {
                if payload == "[DONE]" { break }
                continue
            }
            guard let delta = Self.extractStreamDelta(payload) else { continue }
            accumulated += delta
            let normalized = Self.normalizeNextSentence(accumulated)
            if !normalized.isEmpty {
                onTextChanged(normalized)
            }
        }

        let result = Self.normalizeNextSentence(accumulated)
        guard !result.isEmpty else {
            throw ZhipuError.invalidResponse("智谱没有返回可用的下一句。")
        }
        return result
    }

    func analyzeSupplement(
        transcript: String,
        previousGuidance: WritingGuidance
    ) async throws -> WritingGuidance {
        let previousFramework = previousGuidance.framework.joined(separator: "；")
        let content = try await completeJSON(
            system: "你是中文口述写作分析助手。根据当前全文动态理解内容，不要套用固定文档模板。"
                + "只输出JSON，不要解释，不要输出思考过程。"
                + "输出字段：framework字符串数组、directions字符串数组、missing_points字符串数组。"
                + "framework是当前内容自然形成的要点脉络；directions是接下来可展开的内容；"
                + "missing_points是可能遗漏但确实重要的信息。每项不超过40字，不要复述全文。",
            user: "已有动态脉络：\(previousFramework.isEmpty ? "无" : previousFramework)\n当前全文：\(clip(transcript))",
            maxTokens: 420,
            model: guidanceModel,
            temperature: 0.2
        )

        let decoded = try JSONDecoder().decode(
            GuidanceDTO.self,
            from: Self.guidancePayload(from: content)
        )
        return WritingGuidance(
            framework: Self.clean(decoded.framework?.values),
            directions: Self.clean(decoded.directions?.values),
            missingPoints: Self.clean(decoded.missingPoints?.values),
            template: previousGuidance.template
        )
    }

    func optimize(transcript: String) async throws -> String {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }

        let content = try await completeJSON(
            system: "你是中文文字编辑。只输出JSON，不要解释，不要输出思考过程。"
                + "检查并修正错别字、同音字、语法、标点、口癖、重复词句、自我重复、语序混乱和明显逻辑不通。"
                + "重点删除“那个那个”“嗯嗯”“就是说就是说”等口述填充，以及连续重复或前后矛盾但没有新增信息的表达。"
                + "可以调整句子衔接和语序，但不要扩写、不要添加事实、不要改变专有名词、数字和业务结论。"
                + "输出字段：optimized_text字符串、changes数组。"
                + "changes数组每项包含original、corrected、type。",
            user: clip(transcript, maxLength: 24_000),
            maxTokens: 2_048,
            model: editingModel,
            temperature: 0
        )

        let decoded = try JSONDecoder().decode(OptimizeDTO.self, from: Data(content.utf8))
        return decoded.optimizedText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? transcript
    }

    func optimizeSegments(_ segments: [String]) async throws -> String {
        guard !segments.isEmpty else { return "" }

        let segmentText = segments.enumerated()
            .map { "片段\($0.offset + 1)：\($0.element)" }
            .joined(separator: "\n")

        let content = try await completeJSON(
            system: "你是中文文字编辑。以下内容是同一段连续口述按时间切分后产生的ASR片段，"
                + "相邻片段可能存在重叠、重复、断句和同音字错误。"
                + "请将这些片段合并为一段完整自然的文字，去除相邻片段重复、口癖、自我重复和语序混乱。"
                + "重点删除“那个那个”“嗯嗯”“就是说就是说”等口述填充，修复明显逻辑不通，但不得扩写或添加事实。"
                + "保持原意，保留专有名词、数字和业务结论。"
                + "只输出JSON，不要解释，不要输出思考过程。输出字段：optimized_text字符串、changes数组。"
                + "changes数组每项包含original、corrected、type。",
            user: segmentText,
            maxTokens: 3_000,
            model: editingModel,
            temperature: 0
        )

        let decoded = try JSONDecoder().decode(OptimizeDTO.self, from: Data(content.utf8))
        return decoded.optimizedText?.trimmingCharacters(in: .whitespacesAndNewlines)
            ?? segments.joined()
    }

    private func completeJSON(
        system: String,
        user: String,
        maxTokens: Int,
        model: String,
        temperature: Double
    ) async throws -> String {
        guard let apiKey = apiKeyStore.apiKey() else {
            throw ZhipuError.missingApiKey
        }

        let body = ChatRequest(
            model: model,
            messages: [
                ChatMessage(role: "system", content: system),
                ChatMessage(role: "user", content: user)
            ],
            temperature: temperature,
            stream: false,
            maxTokens: maxTokens,
            responseFormat: ResponseFormat(type: "json_object"),
            thinking: Thinking(type: "disabled")
        )

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ZhipuError.invalidResponse("智谱写作分析返回了无效响应。")
        }

        let responseBody = String(data: data, encoding: .utf8) ?? ""

        guard (200..<300).contains(httpResponse.statusCode) else {
            throw ZhipuError.invalidResponse(
                "智谱写作分析失败（\(httpResponse.statusCode)）：\(Self.extractErrorMessage(responseBody))"
            )
        }

        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let content = message["content"] as? String,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ZhipuError.invalidResponse("智谱没有返回可解析的内容。")
        }

        return Self.extractJSONObject(content)
    }

    private func clip(_ value: String, maxLength: Int = 8_000) -> String {
        value.count <= maxLength ? value : String(value.suffix(maxLength))
    }

    private static func clean(_ items: [String]?) -> [String] {
        guard let items else { return [] }
        var seen = Set<String>()
        var result: [String] = []

        for item in items {
            let trimmed = item.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, !seen.contains(trimmed) else { continue }
            seen.insert(trimmed)
            result.append(trimmed)
            if result.count >= 6 { break }
        }

        return result
    }

    private static func extractStreamDelta(_ payload: String) -> String? {
        guard let data = payload.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = object["choices"] as? [[String: Any]],
              let delta = choices.first?["delta"] as? [String: Any] else {
            return nil
        }
        return delta["content"] as? String
    }

    private static func normalizeNextSentence(_ value: String) -> String {
        var text = value
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        for prefix in ["下一句：", "下一句:", "建议：", "建议:"] where text.hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        text = text.trimmingCharacters(in: CharacterSet(charactersIn: "“”\"'"))
        return text.count <= 120 ? text : String(text.prefix(120))
    }

    private static func extractJSONObject(_ content: String) -> String {
        guard let first = content.firstIndex(of: "{"),
              let last = content.lastIndex(of: "}"),
              first < last else {
            return content
        }

        return String(content[first...last])
    }

    private static func guidancePayload(from content: String) -> Data {
        let rootData = Data(content.utf8)
        guard let root = try? JSONSerialization.jsonObject(with: rootData) as? [String: Any] else {
            return rootData
        }

        if let answer = root["answer"] as? [String: Any],
           let answerData = try? JSONSerialization.data(withJSONObject: answer) {
            return answerData
        }
        if let data = root["data"] as? [String: Any],
           let wrappedData = try? JSONSerialization.data(withJSONObject: data) {
            return wrappedData
        }

        return rootData
    }

    private static func extractErrorMessage(_ body: String) -> String {
        guard let data = body.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let error = object["error"] as? [String: Any],
              let message = error["message"] as? String else {
            return "未知错误"
        }
        return message
    }

    private struct ChatRequest: Encodable {
        let model: String
        let messages: [ChatMessage]
        let temperature: Double
        let stream: Bool
        let maxTokens: Int
        let responseFormat: ResponseFormat
        let thinking: Thinking

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case temperature
            case stream
            case maxTokens = "max_tokens"
            case responseFormat = "response_format"
            case thinking
        }
    }

    private struct StreamChatRequest: Encodable {
        let model: String
        let messages: [ChatMessage]
        let temperature: Double
        let stream: Bool
        let maxTokens: Int
        let thinking: Thinking

        enum CodingKeys: String, CodingKey {
            case model
            case messages
            case temperature
            case stream
            case maxTokens = "max_tokens"
            case thinking
        }
    }

    private struct ChatMessage: Encodable {
        let role: String
        let content: String
    }

    private struct ResponseFormat: Encodable {
        let type: String
    }

    private struct Thinking: Encodable {
        let type: String
    }

    private struct GuidanceDTO: Decodable {
        let template: String?
        let framework: StringList?
        let nextSentence: String?
        let answer: String?
        let directions: StringList?
        let missingPoints: StringList?

        enum CodingKeys: String, CodingKey {
            case template
            case framework
            case nextSentence = "next_sentence"
            case answer
            case directions
            case missingPoints = "missing_points"
        }
    }

    private struct StringList: Decodable {
        let values: [String]

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let items = try? container.decode([String].self) {
                values = items
                return
            }

            let text = try container.decode(String.self)
            values = text.components(
                separatedBy: CharacterSet(charactersIn: "\n;；、|")
            )
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        }
    }

    private struct OptimizeDTO: Decodable {
        let optimizedText: String?

        enum CodingKeys: String, CodingKey {
            case optimizedText = "optimized_text"
        }
    }
}
