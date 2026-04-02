import Foundation

/// Fuzzy matching utility for command palette search.
/// Supports non-contiguous character matching with graduated scoring.
/// Case-insensitive throughout.
public enum FuzzyMatcher {

    /// Returns a score for how well `query` matches `candidate`.
    /// 0 means no match; higher is better.
    ///
    /// - Empty query returns maximum score (matches everything).
    /// - Scoring rewards: prefix matches, word boundary matches, consecutive matches.
    /// - Scoring penalizes: gaps between matched characters.
    public static func score(query: String, candidate: String) -> Int {
        guard !query.isEmpty else { return 1000 }
        guard !candidate.isEmpty else { return 0 }

        let queryChars = Array(query.lowercased())
        let candidateChars = Array(candidate.lowercased())

        guard let bestScore = bestMatch(
            queryChars: queryChars,
            candidateChars: candidateChars,
            candidateOriginal: Array(candidate)
        ) else {
            return 0
        }

        return bestScore
    }

    // MARK: - Private

    /// Recursively find the best scoring alignment of query characters in candidate.
    /// Returns nil if no match is possible.
    private static func bestMatch(
        queryChars: [Character],
        candidateChars: [Character],
        candidateOriginal: [Character]
    ) -> Int? {
        let qLen = queryChars.count
        let cLen = candidateChars.count

        guard qLen <= cLen else { return nil }

        // Use iterative DP-like approach: try all possible positions for each query char
        // and track the best score. We use a recursive approach with memoization-like pruning.
        var best: Int?
        findBest(
            queryChars: queryChars,
            candidateChars: candidateChars,
            candidateOriginal: candidateOriginal,
            qIdx: 0,
            cIdx: 0,
            currentScore: 0,
            consecutive: 0,
            best: &best
        )
        return best
    }

    private static func findBest(
        queryChars: [Character],
        candidateChars: [Character],
        candidateOriginal: [Character],
        qIdx: Int,
        cIdx: Int,
        currentScore: Int,
        consecutive: Int,
        best: inout Int?
    ) {
        // All query chars matched
        if qIdx == queryChars.count {
            if best == nil || currentScore > best! {
                best = currentScore
            }
            return
        }

        // Not enough candidate chars left
        let remaining = queryChars.count - qIdx
        if cIdx + remaining > candidateChars.count {
            return
        }

        // Pruning: even if all remaining chars get max bonus, can we beat best?
        if let currentBest = best {
            let maxPossibleRemaining = remaining * (Bonus.prefix + Bonus.wordBoundary + Bonus.consecutive + Bonus.base)
            if currentScore + maxPossibleRemaining <= currentBest {
                return
            }
        }

        let queryChar = queryChars[qIdx]

        for i in cIdx..<candidateChars.count {
            // Not enough room for remaining query chars
            if candidateChars.count - i < remaining {
                break
            }

            guard candidateChars[i] == queryChar else { continue }

            var matchScore = Bonus.base
            let isConsecutive = (consecutive > 0 && i == cIdx)

            // Prefix bonus: first query char matches first candidate char
            if qIdx == 0 && i == 0 {
                matchScore += Bonus.prefix
            }

            // Word boundary bonus
            if isWordBoundary(candidateOriginal: candidateOriginal, index: i) {
                matchScore += Bonus.wordBoundary
            }

            // Consecutive bonus
            let newConsecutive = isConsecutive ? consecutive + 1 : 1
            if isConsecutive {
                matchScore += Bonus.consecutive * newConsecutive
            }

            // Gap penalty
            let gap = i - cIdx
            if gap > 0 {
                matchScore -= Penalty.gap * min(gap, Penalty.maxGap)
            }

            findBest(
                queryChars: queryChars,
                candidateChars: candidateChars,
                candidateOriginal: candidateOriginal,
                qIdx: qIdx + 1,
                cIdx: i + 1,
                currentScore: currentScore + matchScore,
                consecutive: newConsecutive,
                best: &best
            )
        }
    }

    /// Check if the character at `index` is at a word boundary.
    /// Word boundaries: start of string, after space/hyphen/underscore/slash/dot,
    /// or camelCase transition (lowercase → uppercase).
    private static func isWordBoundary(candidateOriginal: [Character], index: Int) -> Bool {
        if index == 0 { return true }
        let prev = candidateOriginal[index - 1]
        if prev == " " || prev == "-" || prev == "_" || prev == "/" || prev == "." {
            return true
        }
        // camelCase: previous is lowercase, current is uppercase
        if prev.isLowercase && candidateOriginal[index].isUppercase {
            return true
        }
        return false
    }

    // MARK: - Scoring Constants

    private enum Bonus {
        static let base = 10
        static let prefix = 20
        static let wordBoundary = 12
        static let consecutive = 8
    }

    private enum Penalty {
        static let gap = 3
        static let maxGap = 5
    }
}
