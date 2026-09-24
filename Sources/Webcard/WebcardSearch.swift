import Foundation

struct WebcardSearchField {
    enum Kind {
        case filename
        case title
        case siteName
        case urlHost
        case urlPath
        case summary
        case folder
        case metadata

        var weight: Int {
            switch self {
            case .filename: 500
            case .title: 450
            case .siteName: 300
            case .urlHost: 280
            case .urlPath: 180
            case .summary: 160
            case .folder: 140
            case .metadata: 100
            }
        }
    }

    let kind: Kind
    let value: String
}

enum WebcardSearch {
    static func score(query: String, for item: WebcardFolderItem) -> Int? {
        var fields = [
            WebcardSearchField(
                kind: .filename,
                value: item.fileURL.deletingPathExtension().lastPathComponent
            ),
            WebcardSearchField(
                kind: .folder,
                value: item.fileURL.deletingLastPathComponent().path
            )
        ]
        if let capture = item.capture {
            let url = capture.canonicalURL
            fields.append(contentsOf: [
                WebcardSearchField(kind: .title, value: capture.title),
                WebcardSearchField(kind: .siteName, value: capture.siteName),
                WebcardSearchField(kind: .urlHost, value: url.host ?? ""),
                WebcardSearchField(kind: .urlPath, value: url.path),
                WebcardSearchField(kind: .summary, value: capture.summary)
            ])
            fields.append(
                contentsOf: capture.socialMetadata.searchableValues.map {
                    WebcardSearchField(kind: .metadata, value: $0)
                }
            )
        } else if let url = item.sourceURL {
            fields.append(contentsOf: [
                WebcardSearchField(kind: .title, value: "Web Location"),
                WebcardSearchField(kind: .urlHost, value: url.host ?? ""),
                WebcardSearchField(kind: .urlPath, value: url.path)
            ])
        }
        return score(query: query, in: fields)
    }

    static func score(query: String, in values: [String]) -> Int? {
        score(
            query: query,
            in: values.map { WebcardSearchField(kind: .metadata, value: $0) }
        )
    }

    static func isEmpty(_ query: String) -> Bool {
        terms(in: query).isEmpty
    }

    private static func score(
        query: String,
        in fields: [WebcardSearchField]
    ) -> Int? {
        let queryTerms = terms(in: query)
        guard !queryTerms.isEmpty else {
            return 0
        }

        let candidates = fields.map {
            (
                field: $0,
                normalized: normalize($0.value)
            )
        }
        var total = 0
        var matchedFieldIndexes: [Int] = []

        for term in queryTerms {
            let matches = candidates.enumerated().compactMap { index, candidate -> (Int, Int)? in
                guard let relevance = score(term: term, in: candidate.normalized) else {
                    return nil
                }
                return (relevance + candidate.field.kind.weight, index)
            }
            guard let best = matches.max(by: { $0.0 < $1.0 }) else {
                return nil
            }
            total += best.0
            matchedFieldIndexes.append(best.1)
        }

        if Set(matchedFieldIndexes).count == 1, queryTerms.count > 1 {
            total += 250
        }

        let normalizedQuery = normalize(query.replacingOccurrences(of: "\"", with: ""))
        if !normalizedQuery.isEmpty,
           candidates.contains(where: { $0.normalized == normalizedQuery }) {
            total += 800
        }
        return total
    }

    private static func score(term: String, in candidate: String) -> Int? {
        guard !candidate.isEmpty else {
            return nil
        }
        if candidate == term {
            return 1_500
        }
        if candidate.hasPrefix(term) {
            return 1_350 - min(candidate.count - term.count, 100)
        }
        if let range = candidate.range(of: term) {
            let position = candidate.distance(
                from: candidate.startIndex,
                to: range.lowerBound
            )
            return 1_200 - min(position, 200)
        }

        let candidateTokens = candidate.split(separator: " ").map(String.init)
        if candidateTokens.contains(term) {
            return 1_100
        }
        if let prefix = candidateTokens
            .filter({ $0.hasPrefix(term) })
            .min(by: { $0.count < $1.count }) {
            return 950 - min(prefix.count - term.count, 100)
        }
        if let substring = candidateTokens
            .filter({ $0.contains(term) })
            .min(by: { $0.count < $1.count }) {
            return 800 - min(substring.count - term.count, 100)
        }

        if let typoScore = typoScore(term: term, candidateTokens: candidateTokens) {
            return typoScore
        }
        return subsequenceScore(term: term, candidateTokens: candidateTokens)
    }

    private static func typoScore(
        term: String,
        candidateTokens: [String]
    ) -> Int? {
        let maximumDistance: Int
        switch term.count {
        case 0...3:
            return nil
        case 4...7:
            maximumDistance = 1
        default:
            maximumDistance = 2
        }

        return candidateTokens.compactMap { token in
            guard abs(token.count - term.count) <= maximumDistance else {
                return nil
            }
            let distance = damerauLevenshteinDistance(
                term,
                token,
                limit: maximumDistance
            )
            guard distance <= maximumDistance else {
                return nil
            }
            return 700 - distance * 80 - abs(token.count - term.count) * 10
        }.max()
    }

    private static func subsequenceScore(
        term: String,
        candidateTokens: [String]
    ) -> Int? {
        guard term.count >= 3 else {
            return nil
        }

        return candidateTokens.compactMap { token in
            var searchIndex = token.startIndex
            var firstMatch: String.Index?
            var previousMatch: String.Index?
            var gaps = 0

            for character in term {
                guard searchIndex < token.endIndex,
                      let match = token[searchIndex...].firstIndex(of: character) else {
                    return nil
                }
                firstMatch = firstMatch ?? match
                if let previousMatch {
                    gaps += max(0, token.distance(from: previousMatch, to: match) - 1)
                }
                previousMatch = match
                searchIndex = token.index(after: match)
            }

            let start = firstMatch.map {
                token.distance(from: token.startIndex, to: $0)
            } ?? 0
            guard gaps <= max(4, term.count * 2) else {
                return nil
            }
            return 450 - gaps * 12 - start * 4
        }.max()
    }

    private static func terms(in query: String) -> [String] {
        var terms: [String] = []
        var current = ""
        var isQuoted = false

        func appendCurrent() {
            let normalized = normalize(current)
            if !normalized.isEmpty {
                terms.append(normalized)
            }
            current = ""
        }

        for character in query {
            if character == "\"" {
                appendCurrent()
                isQuoted.toggle()
            } else if character.isWhitespace && !isQuoted {
                appendCurrent()
            } else {
                current.append(character)
            }
        }
        appendCurrent()
        return terms
    }

    private static func normalize(_ value: String) -> String {
        let folded = value
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            .lowercased()
        var normalized = ""
        var previousWasSpace = true

        for character in folded {
            if character.isLetter || character.isNumber {
                normalized.append(character)
                previousWasSpace = false
            } else if !previousWasSpace {
                normalized.append(" ")
                previousWasSpace = true
            }
        }
        return normalized.trimmingCharacters(in: .whitespaces)
    }

    private static func damerauLevenshteinDistance(
        _ source: String,
        _ target: String,
        limit: Int
    ) -> Int {
        let source = Array(source)
        let target = Array(target)
        guard abs(source.count - target.count) <= limit else {
            return limit + 1
        }

        var previousPrevious = Array(0...target.count)
        var previous = previousPrevious

        for sourceIndex in source.indices {
            var current = Array(repeating: 0, count: target.count + 1)
            current[0] = sourceIndex + 1
            var rowMinimum = current[0]

            for targetIndex in target.indices {
                let substitutionCost = source[sourceIndex] == target[targetIndex] ? 0 : 1
                current[targetIndex + 1] = min(
                    previous[targetIndex + 1] + 1,
                    current[targetIndex] + 1,
                    previous[targetIndex] + substitutionCost
                )
                if sourceIndex > 0,
                   targetIndex > 0,
                   source[sourceIndex] == target[targetIndex - 1],
                   source[sourceIndex - 1] == target[targetIndex] {
                    current[targetIndex + 1] = min(
                        current[targetIndex + 1],
                        previousPrevious[targetIndex - 1] + 1
                    )
                }
                rowMinimum = min(rowMinimum, current[targetIndex + 1])
            }

            if rowMinimum > limit {
                return limit + 1
            }
            previousPrevious = previous
            previous = current
        }
        return previous[target.count]
    }
}
