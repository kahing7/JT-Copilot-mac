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
    private let fastModel = "glm-4.5-air"
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

    func analyze(transcript: String, previousGuidance: WritingGuidance?) async throws -> WritingGuidance {
        let previousFramework = previousGuidance?.framework.joined(separator: "；") ?? "无"
        let previousTemplate = previousGuidance.map {
            DocumentTemplateCatalog.displayName(for: $0.template)
        } ?? "自动识别"
        let content = try await completeJSON(
            system: "你是实时中文口述写作教练。只输出JSON，不要解释，不要输出思考过程。"
                + "第一步必须根据当前全文判断用户正在写什么文档，不能要求用户先声明类型。"
                + "可选模板：project_management（项目管理文档）、meeting_minutes（会议纪要）、"
                + "prd（产品需求文档）、weekly_report（工作周报）、solution（方案文档）、general（通用写作）。"
                + "第二步按所选文档的标准框架继续写作，框架示例：项目管理为项目背景、目标、范围、里程碑、职责、风险、交付验收；"
                + "会议纪要为会议信息、会议目标、讨论要点、结论决策、行动项、待确认事项；"
                + "PRD为用户场景、目标指标、功能范围、流程交互、需求细节、验收；"
                + "周报为进展、结果、问题风险、下周计划、协作依赖；方案为背景、目标约束、总体方案、关键设计、实施、风险、验收。"
                + "第三步结合全文判断哪些栏目已写、当前在哪个栏目，并给出用户现在可以直接接着说的下一句提示。"
                + "已有框架只用于保持连续性；如果最新内容表明文档类型不对，必须立即切换。"
                + "输出字段：template字符串、framework字符串数组、next_sentence字符串、directions字符串数组、missing_points字符串数组。"
                + "framework使用所选模板的完整栏目并在当前栏目后标“当前”；next_sentence要具体点明下一栏和应说内容，不超过40字。",
            user: "上次判断：\(previousTemplate)\n已有框架：\(previousFramework)\n当前全文：\(clip(transcript))",
            maxTokens: 640,
            model: fastModel,
            temperature: 0.1
        )

        let decoded = try JSONDecoder().decode(GuidanceDTO.self, from: Data(content.utf8))
        let template = Self.template(
            from: decoded.template,
            fallback: previousGuidance?.template ?? .general
        )
        return WritingGuidance(
            framework: Self.clean(decoded.framework),
            nextSentence: decoded.nextSentence?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
            directions: Self.clean(decoded.directions),
            missingPoints: Self.clean(decoded.missingPoints),
            template: template
        )
    }

    func optimize(transcript: String) async throws -> String {
        guard !transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ""
        }

        let content = try await completeJSON(
            system: "你是中文文字编辑。只输出JSON，不要解释，不要输出思考过程。"
                + "只修正错别字、同音字、语法、标点、明显重复和不通顺表达，保持原意、专有名词、数字和业务结论。"
                + "不要扩写，不要改变结构。输出字段：optimized_text字符串、changes数组。"
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
                + "请将这些片段合并为一段完整自然的文字，去除重复，修正错别字、语法和标点。"
                + "只做必要修改，保持原意，保留专有名词、数字和业务结论，不得扩写或添加事实。"
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

    private static func template(
        from value: String?,
        fallback: DocumentTemplate
    ) -> DocumentTemplate {
        let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() ?? ""

        switch normalized {
        case "project_management", "project-management", "projectmanagement", "项目管理文档", "项目管理":
            return .projectManagement
        case "meeting_minutes", "meeting-minutes", "meetingminutes", "会议纪要", "会议记录":
            return .meetingMinutes
        case "prd", "产品需求文档":
            return .prd
        case "weekly_report", "weekly-report", "weeklyreport", "工作周报", "周报":
            return .weeklyReport
        case "solution", "方案文档", "技术方案":
            return .solution
        case "general", "通用写作":
            return .general
        default:
            return fallback
        }
    }

    private static func extractJSONObject(_ content: String) -> String {
        guard let first = content.firstIndex(of: "{"),
              let last = content.lastIndex(of: "}"),
              first < last else {
            return content
        }

        return String(content[first...last])
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
        let framework: [String]?
        let nextSentence: String?
        let directions: [String]?
        let missingPoints: [String]?

        enum CodingKeys: String, CodingKey {
            case template
            case framework
            case nextSentence = "next_sentence"
            case directions
            case missingPoints = "missing_points"
        }
    }

    private struct OptimizeDTO: Decodable {
        let optimizedText: String?

        enum CodingKeys: String, CodingKey {
            case optimizedText = "optimized_text"
        }
    }
}
