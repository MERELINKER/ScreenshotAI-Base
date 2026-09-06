import Foundation

public struct GeneratedResultCleaner: Sendable {
    public init() {}

    public func clean(_ rawText: String) -> String {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        if let ticketSummary = firstTitleSummaryBlock(in: trimmed) {
            return ticketSummary
        }

        return collapseRepeatedOpeningTail(in: collapseRepeatedAnswerSections(in: trimmed))
    }

    private func firstTitleSummaryBlock(in text: String) -> String? {
        guard let titleRange = text.range(of: "标题："),
              let summaryRange = text.range(of: "摘要：", range: titleRange.upperBound..<text.endIndex)
        else {
            return nil
        }

        let nextTitleRange = text.range(of: "标题：", range: summaryRange.upperBound..<text.endIndex)
        let title = text[titleRange.upperBound..<summaryRange.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let summaryEnd = nextTitleRange?.lowerBound ?? text.endIndex
        let summary = text[summaryRange.upperBound..<summaryEnd]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !title.isEmpty, !summary.isEmpty else { return nil }
        return "标题：\(title)\n摘要：\(summary)"
    }

    private func collapseRepeatedAnswerSections(in text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        guard lines.count > 3 else { return text }

        for anchor in repeatedAnchors(in: lines) {
            let starts = lines.indices.filter {
                normalizedComparisonText(lines[$0]) == anchor
            }
            guard starts.count > 1,
                  let collapsed = collapseSegments(lines: lines, starts: starts),
                  collapsed != text
            else {
                continue
            }
            return collapsed
        }

        return text
    }

    private func repeatedAnchors(in lines: [String]) -> [String] {
        var firstSeenIndex: [String: Int] = [:]
        var repeated: [(index: Int, anchor: String)] = []
        var emitted = Set<String>()

        for (index, line) in lines.enumerated() {
            let normalized = normalizedComparisonText(line)
            guard normalized.count >= 8 else { continue }

            if firstSeenIndex[normalized] != nil {
                if !emitted.contains(normalized) {
                    repeated.append((firstSeenIndex[normalized] ?? index, normalized))
                    emitted.insert(normalized)
                }
            } else {
                firstSeenIndex[normalized] = index
            }
        }

        return repeated
            .sorted { lhs, rhs in lhs.index < rhs.index }
            .map(\.anchor)
    }

    private func collapseSegments(lines: [String], starts: [Int]) -> String? {
        guard let firstStart = starts.first else { return nil }
        let firstEnd = starts.dropFirst().first ?? lines.count
        let baselineFingerprint = Set(fingerprint(lines[firstStart..<firstEnd]))
        guard baselineFingerprint.count >= 3 else { return nil }

        var collapsedLines = Array(lines[..<firstStart])

        for (offset, start) in starts.enumerated() {
            let end = offset + 1 < starts.count ? starts[offset + 1] : lines.count
            let segment = lines[start..<end]

            if offset == 0 {
                collapsedLines.append(contentsOf: segment)
                continue
            }

            let segmentFingerprint = Set(fingerprint(segment))
            if similarity(between: baselineFingerprint, and: segmentFingerprint) < 0.5 {
                collapsedLines.append(contentsOf: segment)
            }
        }

        return collapsedLines
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func fingerprint(_ lines: ArraySlice<String>) -> [String] {
        lines
            .map(normalizedComparisonText)
            .filter { $0.count >= 4 }
    }

    private func normalizedComparisonText(_ text: String) -> String {
        text
            .lowercased()
            .filter { character in
                !character.isWhitespace
                    && character != "*"
                    && character != "`"
            }
    }

    private func similarity(between lhs: Set<String>, and rhs: Set<String>) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        let intersectionCount = lhs.intersection(rhs).count
        let unionCount = lhs.union(rhs).count
        guard unionCount > 0 else { return 0 }
        return Double(intersectionCount) / Double(unionCount)
    }

    private func collapseRepeatedOpeningTail(in text: String) -> String {
        let normalized = normalizedTokens(in: text)
        let minimumRepeatedTokenCount = 36
        guard normalized.count >= minimumRepeatedTokenCount * 2 else { return text }

        for start in 1..<(normalized.count - minimumRepeatedTokenCount + 1) {
            guard normalized[start].value == normalized[0].value else { continue }

            var offset = 0
            while start + offset < normalized.count,
                  normalized[offset].value == normalized[start + offset].value {
                offset += 1
            }

            guard start + offset == normalized.count,
                  offset >= minimumRepeatedTokenCount
            else {
                continue
            }

            let originalStart = normalized[start].originalIndex
            let collapsed = text[..<originalStart]
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return collapsed.isEmpty ? text : collapsed
        }

        return text
    }

    private func normalizedTokens(in text: String) -> [NormalizedToken] {
        var tokens: [NormalizedToken] = []
        var index = text.startIndex

        while index < text.endIndex {
            let character = text[index]
            if !character.isWhitespace,
               character != "*",
               character != "`" {
                tokens.append(
                    NormalizedToken(
                        value: String(character).lowercased(),
                        originalIndex: index
                    )
                )
            }
            index = text.index(after: index)
        }

        return tokens
    }

    private struct NormalizedToken {
        var value: String
        var originalIndex: String.Index
    }
}
