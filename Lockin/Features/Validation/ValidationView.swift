import SwiftUI
import SwiftData

struct ValidationView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var lockState: LockState
    @Query private var settingsList: [AppSettings]

    var session: SessionSnapshot
    var segment: SegmentSnapshot

    @State private var questions: [QuizQuestion] = []
    @State private var index = 0
    @State private var answer = ""
    @State private var selectedChoice: Int?
    @State private var trueFalse: Bool?
    @State private var lastSolution: String?
    @State private var lastPassed: Bool?
    @State private var loading = false
    @State private var error = ""
    @State private var passedCount = 0
    @State private var showContinuePrompt = false
    @State private var mastery = false

    var body: some View {
        NavigationStack {
            Group {
                if loading && questions.isEmpty {
                    ProgressView("Generating questions…")
                } else if showContinuePrompt {
                    continuePrompt
                } else if let question = questions[safe: index] {
                    questionView(question)
                } else {
                    Text("No questions yet.")
                }
            }
            .padding()
            .navigationTitle("Validate")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task { await start() }
        }
    }

    private var continuePrompt: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Segment unlocked")
                .font(.title.bold())
            Text("You proved \(segment.milestoneSubset.isEmpty ? session.milestoneTitle : segment.milestoneSubset).")
            Text("Continue into the next segment now, or stop until that window starts.")
                .foregroundStyle(.secondary)
            Button("Start next segment now") {
                lockState.startNextSegmentNow(sessionID: session.id, context: context)
                dismiss()
            }
            .buttonStyle(.borderedProminent)
            Button("Stop for now") { dismiss() }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func questionView(_ question: QuizQuestion) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(mastery ? "Mastery mode" : session.zoneTitle)
                .font(.caption.weight(.semibold))
                .foregroundStyle(mastery ? .orange : Color(hex: session.zoneColorHex))
            Text(question.kind.title.uppercased())
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(question.prompt)
                .font(.title3.weight(.semibold))

            switch question.kind {
            case .multipleChoice:
                ForEach(Array(question.choices.enumerated()), id: \.offset) { idx, choice in
                    Button {
                        selectedChoice = idx
                    } label: {
                        HStack {
                            Image(systemName: selectedChoice == idx ? "largecircle.fill.circle" : "circle")
                            Text(choice).multilineTextAlignment(.leading)
                        }
                    }
                    .buttonStyle(.plain)
                }
            case .trueFalse:
                Picker("Answer", selection: $trueFalse) {
                    Text("True").tag(Optional(true))
                    Text("False").tag(Optional(false))
                }
                .pickerStyle(.segmented)
            case .shortAnswer, .longAnswer:
                TextField(question.kind == .shortAnswer ? "Final answer" : "Write your answer", text: $answer, axis: .vertical)
                    .lineLimit(question.kind == .longAnswer ? 6...12 : 2...4)
                    .textFieldStyle(.roundedBorder)
            }

            if let passed = lastPassed, let solution = lastSolution {
                VStack(alignment: .leading, spacing: 8) {
                    Text(passed ? "Correct" : "Not yet")
                        .font(.headline)
                        .foregroundStyle(passed ? .green : .red)
                    Text("Solution")
                        .font(.subheadline.weight(.semibold))
                    Text(solution)
                }
                .padding()
                .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
            }

            if !error.isEmpty {
                Text(error).foregroundStyle(.red)
            }

            Button(lastPassed == nil ? "Submit" : (lastPassed == true ? "Continue" : "New question")) {
                Task { await submitOrAdvance(question) }
            }
            .buttonStyle(.borderedProminent)
            .disabled(loading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func start() async {
        mastery = Date() < segment.end.addingTimeInterval(-2 * 3600) && Date() < segment.end
        // Early if more than ~20% of the window remains? Plan: far ahead of schedule.
        let window = segment.end.timeIntervalSince(segment.start)
        let remaining = segment.end.timeIntervalSince(Date())
        mastery = window > 0 && remaining > window * 0.5 && Date() < segment.end

        loading = true
        defer { loading = false }
        do {
            let service = try makeService()
            let materials = materialsText()
            questions = try await service.generate(
                milestoneTitle: session.milestoneTitle,
                scope: segment.milestoneSubset.isEmpty ? session.milestoneTitle : segment.milestoneSubset,
                materials: materials,
                mastery: mastery
            )
            index = 0
            resetAnswer()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func submitOrAdvance(_ question: QuizQuestion) async {
        if lastPassed != nil {
            if lastPassed == true {
                passedCount += 1
                if passedCount >= 2 {
                    finishSuccess()
                    return
                }
                if index + 1 < questions.count {
                    index += 1
                } else {
                    await loadMore()
                    index = min(index + 1, max(0, questions.count - 1))
                }
            } else {
                await loadMore(replacingCurrent: true)
            }
            lastPassed = nil
            lastSolution = nil
            resetAnswer()
            return
        }

        loading = true
        defer { loading = false }
        let submitted: String
        switch question.kind {
        case .multipleChoice:
            guard let selectedChoice else { error = "Pick an answer."; return }
            submitted = String(selectedChoice)
        case .trueFalse:
            guard let trueFalse else { error = "Pick true or false."; return }
            submitted = trueFalse ? "true" : "false"
        case .shortAnswer, .longAnswer:
            submitted = answer
            if submitted.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                error = "Enter a final answer."
                return
            }
        }
        do {
            let service = try makeService()
            let result = try await service.grade(question: question, answer: submitted)
            lastPassed = result.passed
            lastSolution = result.feedback
            let attempt = ValidationAttempt()
            attempt.sessionID = session.id
            attempt.segmentID = segment.id
            attempt.passed = result.passed
            attempt.mastery = mastery
            attempt.questionKind = question.kind.rawValue
            context.insert(attempt)
            try? context.save()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func loadMore(replacingCurrent: Bool = false) async {
        loading = true
        defer { loading = false }
        do {
            let service = try makeService()
            let extra = try await service.generate(
                milestoneTitle: session.milestoneTitle,
                scope: segment.milestoneSubset.isEmpty ? session.milestoneTitle : segment.milestoneSubset,
                materials: materialsText(),
                mastery: mastery || replacingCurrent,
                count: 2
            )
            if replacingCurrent, index < questions.count {
                questions[index] = extra.first ?? questions[index]
            } else {
                questions.append(contentsOf: extra)
                if index >= questions.count - 1 { index = questions.count - extra.count }
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func finishSuccess() {
        lockState.markValidated(sessionID: session.id, segmentID: segment.id, context: context)
        showContinuePrompt = true
    }

    private func resetAnswer() {
        answer = ""
        selectedChoice = nil
        trueFalse = nil
        error = ""
    }

    private func makeService() throws -> ValidationService {
        let provider = LLMProvider(rawValue: settingsList.first?.llmProviderRaw ?? "anthropic") ?? .anthropic
        let key = KeychainStore.get(KeychainStore.Key.llmAPIKey) ?? ""
        guard !key.isEmpty else { throw ValidationServiceError.missingAPIKey }
        return ValidationService(provider: provider, apiKey: key)
    }

    private func materialsText() -> String {
        let sessions = (try? context.fetch(FetchDescriptor<StudySession>())) ?? []
        guard let model = sessions.first(where: { $0.id == session.id }),
              let zone = model.zone else { return "" }
        var parts = [
            zone.textbookResources,
            zone.practiceQuizzes,
            model.milestone?.scope ?? ""
        ]
        parts.append(contentsOf: zone.customMaterials.map { "\($0.name): \($0.content)" })
        return parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

extension Collection {
    subscript(safe index: Index) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
