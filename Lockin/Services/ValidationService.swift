import Foundation

enum LLMProvider: String, CaseIterable, Identifiable {
    case anthropic
    case openai
    var id: String { rawValue }
    var title: String { self == .anthropic ? "Anthropic" : "OpenAI" }
}

struct QuizQuestion: Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable {
        case multipleChoice
        case trueFalse
        case shortAnswer
        case longAnswer

        var title: String {
            switch self {
            case .multipleChoice: return "Multiple choice"
            case .trueFalse: return "True / False"
            case .shortAnswer: return "Short answer"
            case .longAnswer: return "Long answer"
            }
        }
    }

    var id = UUID()
    var kind: Kind
    var prompt: String
    var choices: [String]
    var correctIndex: Int?
    var correctTrue: Bool?
    var expectedFinalAnswer: String
    var solution: String
}

enum ValidationServiceError: LocalizedError {
    case missingAPIKey
    case badResponse
    case decodeFailed

    var errorDescription: String? {
        switch self {
        case .missingAPIKey: return "Add an LLM API key in Settings."
        case .badResponse: return "The grading service returned an unexpected response."
        case .decodeFailed: return "Could not parse the generated questions."
        }
    }
}

struct ValidationService {
    var provider: LLMProvider
    var apiKey: String

    func generate(
        milestoneTitle: String,
        scope: String,
        materials: String,
        mastery: Bool,
        count: Int = 4
    ) async throws -> [QuizQuestion] {
        guard !apiKey.isEmpty else { throw ValidationServiceError.missingAPIKey }
        let difficulty = mastery
            ? "MASTERY MODE: generate significantly harder, deep conceptual edge-case questions. The student is trying to unlock early."
            : "Standard exam-style difficulty matching typical university quizzes."
        let prompt = """
        You generate digital study-validation questions. Return ONLY JSON:
        {"questions":[{"kind":"multipleChoice|trueFalse|shortAnswer|longAnswer","prompt":"...","choices":["A","B","C","D"],"correctIndex":0,"correctTrue":true,"expectedFinalAnswer":"...","solution":"step-by-step solution"}]}

        Mix kinds. Include at least one multipleChoice, one trueFalse, and one short or long answer.
        For multipleChoice provide exactly 4 choices and correctIndex 0-3.
        For trueFalse set correctTrue.
        For short/long, expectedFinalAnswer is the final result only (number, expression, or short phrase). solution is the full worked solution.
        \(difficulty)
        Milestone: \(milestoneTitle)
        Scope: \(scope)
        Course materials:
        \(materials)
        Generate \(count) questions.
        """
        let raw = try await complete(prompt: prompt)
        return try parseQuestions(from: raw)
    }

    func grade(question: QuizQuestion, answer: String) async throws -> (passed: Bool, feedback: String) {
        switch question.kind {
        case .multipleChoice:
            guard let idx = Int(answer.trimmingCharacters(in: .whitespaces)),
                  let correct = question.correctIndex else {
                return (false, question.solution)
            }
            return (idx == correct, question.solution)
        case .trueFalse:
            let normalized = answer.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let expected = question.correctTrue == true
            let userTrue = normalized == "true" || normalized == "t" || normalized == "1"
            let actual = userTrue == expected
            return (actual, question.solution)
        case .shortAnswer, .longAnswer:
            guard !apiKey.isEmpty else { throw ValidationServiceError.missingAPIKey }
            let prompt = """
            Grade only the FINAL ANSWER. Ignore messy intermediate work. If the final answer is mathematically or conceptually equivalent to the expected answer, pass.
            Return ONLY JSON: {"passed":true,"reason":"brief"}
            Question: \(question.prompt)
            Expected final answer: \(question.expectedFinalAnswer)
            Student answer: \(answer)
            """
            let raw = try await complete(prompt: prompt)
            if let data = extractJSON(from: raw).data(using: .utf8),
               let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let passed = obj["passed"] as? Bool {
                return (passed, question.solution)
            }
            let passed = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                .localizedCaseInsensitiveCompare(question.expectedFinalAnswer) == .orderedSame
            return (passed, question.solution)
        }
    }

    private func complete(prompt: String) async throws -> String {
        switch provider {
        case .anthropic:
            return try await anthropic(prompt)
        case .openai:
            return try await openai(prompt)
        }
    }

    private func anthropic(_ prompt: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.addValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let body: [String: Any] = [
            "model": "claude-sonnet-4-20250514",
            "max_tokens": 2048,
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]],
              let text = content.first?["text"] as? String else {
            throw ValidationServiceError.badResponse
        }
        return text
    }

    private func openai(_ prompt: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let body: [String: Any] = [
            "model": "gpt-4.1-mini",
            "messages": [["role": "user", "content": prompt]]
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let choices = obj["choices"] as? [[String: Any]],
              let message = choices.first?["message"] as? [String: Any],
              let text = message["content"] as? String else {
            throw ValidationServiceError.badResponse
        }
        return text
    }

    private func parseQuestions(from raw: String) throws -> [QuizQuestion] {
        let json = extractJSON(from: raw)
        guard let data = json.data(using: .utf8),
              let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = obj["questions"] as? [[String: Any]] else {
            throw ValidationServiceError.decodeFailed
        }
        return items.compactMap { item in
            guard let kindRaw = item["kind"] as? String,
                  let kind = QuizQuestion.Kind(rawValue: kindRaw),
                  let prompt = item["prompt"] as? String else { return nil }
            return QuizQuestion(
                kind: kind,
                prompt: prompt,
                choices: item["choices"] as? [String] ?? [],
                correctIndex: item["correctIndex"] as? Int,
                correctTrue: item["correctTrue"] as? Bool,
                expectedFinalAnswer: item["expectedFinalAnswer"] as? String ?? "",
                solution: item["solution"] as? String ?? ""
            )
        }
    }

    private func extractJSON(from raw: String) -> String {
        if let start = raw.firstIndex(of: "{"), let end = raw.lastIndex(of: "}") {
            return String(raw[start...end])
        }
        return raw
    }
}
