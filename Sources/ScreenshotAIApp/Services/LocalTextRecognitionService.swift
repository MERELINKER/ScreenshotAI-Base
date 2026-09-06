import Foundation
import CoreML
import Vision

struct LocalRecognizedSegment: Sendable {
    let text: String
    let confidence: Float
}

struct LocalRecognizedText: Sendable {
    let text: String
    let confidence: Float
    let alternatives: [String]
    let segments: [LocalRecognizedSegment]

    func confidence(for value: String) -> Float {
        let uppercaseValue = value.uppercased()
        let tokens = uppercaseValue.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init).filter { $0.count >= 4 }
        guard !tokens.isEmpty else { return confidence }
        let related = segments.filter { segment in
            let line = segment.text.uppercased()
            return tokens.filter { line.contains($0) }.count >= min(2, tokens.count)
                || uppercaseValue.replacingOccurrences(of: "\\s", with: "", options: .regularExpression)
                    .contains(line.replacingOccurrences(of: "\\s", with: "", options: .regularExpression))
        }
        guard !related.isEmpty else { return confidence }
        return related.map(\.confidence).reduce(0, +) / Float(related.count)
    }
}

struct LocalTextRecognitionService: Sendable {
    func recognize(_ imageData: Data) async throws -> LocalRecognizedText {
        try await Task.detached(priority: .userInitiated) {
            let request = VNRecognizeTextRequest()
            // Fast recognition is responsive enough for an interactive screenshot tool
            // and avoids depending on a network OCR service.
            request.recognitionLevel = .fast
            request.usesLanguageCorrection = true
            request.automaticallyDetectsLanguage = true
            // Vision's fast recognizer supports Latin-script languages, not Chinese.
            request.recognitionLanguages = ["en-US"]
            if let stages = try? request.supportedComputeStageDevices {
                for (stage, devices) in stages {
                    if let cpu = devices.first(where: { device in
                        if case .cpu = device { return true }
                        return false
                    }) {
                        request.setComputeDevice(cpu, for: stage)
                    }
                }
            }
            try VNImageRequestHandler(data: imageData).perform([request])
            let observations = request.results ?? []
            let lines = observations.compactMap { $0.topCandidates(1).first }
            let primaryLines = lines.map(\.string)
            var alternatives: [String] = []
            for (index, observation) in observations.enumerated() where primaryLines.indices.contains(index) {
                for candidate in observation.topCandidates(3).dropFirst() {
                    var variant = primaryLines
                    variant[index] = candidate.string
                    let text = variant.joined(separator: "\n")
                    if !alternatives.contains(text) { alternatives.append(text) }
                }
            }
            return LocalRecognizedText(
                text: primaryLines.joined(separator: "\n"),
                confidence: lines.map(\.confidence).max() ?? 0,
                alternatives: alternatives,
                segments: lines.map { .init(text: $0.string, confidence: $0.confidence) }
            )
        }.value
    }
}
