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
        let candidateOriginal = Array(candidate)

        let qLen = queryChars.count
        let cLen = candidateChars.count

        guard qLen <= cLen else { return 0 }

        // DP approach: dp[q][c] = best score for matching queryChars[0..<q]
        // ending with the q-th query char matched at candidateChars[c-1].
        // We also track the consecutive count for proper bonus calculation.
        //
        // For each query char q, we try all candidate positions c where
        // candidateChars[c] == queryChars[q], and take the best score from
        // any valid previous position.

        // For each (q, c) store the best score and consecutive count
        // Use Int.min as sentinel for "not reachable"
        let sentinel = Int.min

        // bestEndingAt[c] = (score, consecutive) for current query index,
        // where the match ends at candidate position c.
        // We process query chars one at a time, keeping only the current
        // and previous rows.
        var prevRow: [(score: Int, consecutive: Int)] = Array(repeating: (sentinel, 0), count: cLen)
        var currRow: [(score: Int, consecutive: Int)] = Array(repeating: (sentinel, 0), count: cLen)

        // Fill first query char (q = 0)
        for c in 0..<cLen {
            guard candidateChars[c] == queryChars[0] else { continue }

            var matchScore = Bonus.base

            // Prefix bonus
            if c == 0 {
                matchScore += Bonus.prefix
            }

            // Word boundary bonus
            if isWordBoundary(candidateOriginal: candidateOriginal, index: c) {
                matchScore += Bonus.wordBoundary
            }

            // No gap penalty for first char position choices — we just pick where to start
            // But penalize distance from start for non-prefix matches
            if c > 0 {
                matchScore -= Penalty.gap * min(c, Penalty.maxGap)
            }

            prevRow[c] = (matchScore, 1)
        }

        // Fill remaining query chars
        for q in 1..<qLen {
            // Reset current row
            for c in 0..<cLen {
                currRow[c] = (sentinel, 0)
            }

            // Track the best (score, index) from prevRow up to each position
            // so we don't need an inner loop over all previous positions.
            var bestPrevScore = sentinel
            var bestPrevIndex = -1

            for c in q..<cLen {
                // Update best previous: prevRow[c-1] could be a valid predecessor
                if prevRow[c - 1].score > bestPrevScore {
                    bestPrevScore = prevRow[c - 1].score
                    bestPrevIndex = c - 1
                }

                guard candidateChars[c] == queryChars[q] else { continue }
                guard bestPrevScore != sentinel else { continue }

                // Option A: non-consecutive match (from bestPrevIndex)
                var scoreA = sentinel
                if bestPrevScore != sentinel {
                    let gap = c - bestPrevIndex - 1
                    var s = bestPrevScore + Bonus.base
                    if isWordBoundary(candidateOriginal: candidateOriginal, index: c) {
                        s += Bonus.wordBoundary
                    }
                    if gap > 0 {
                        s -= Penalty.gap * min(gap, Penalty.maxGap)
                    }
                    scoreA = s
                }

                // Option B: consecutive match (from prevRow[c-1] directly, if it exists)
                var scoreB = sentinel
                if prevRow[c - 1].score != sentinel {
                    let prevConsecutive = prevRow[c - 1].consecutive
                    let newConsecutive = prevConsecutive + 1
                    let cappedConsecutive = min(newConsecutive, Bonus.maxConsecutive)
                    var s = prevRow[c - 1].score + Bonus.base + Bonus.consecutive * cappedConsecutive
                    if isWordBoundary(candidateOriginal: candidateOriginal, index: c) {
                        s += Bonus.wordBoundary
                    }
                    scoreB = s
                }

                // Pick the best option
                if scoreB >= scoreA && scoreB != sentinel {
                    let newConsecutive = prevRow[c - 1].consecutive + 1
                    currRow[c] = (scoreB, newConsecutive)
                } else if scoreA != sentinel {
                    currRow[c] = (scoreA, 1)
                }
            }

            // Swap rows
            let temp = prevRow
            prevRow = currRow
            currRow = temp
        }

        // Find the best score across all ending positions for the last query char
        var best = sentinel
        for c in 0..<cLen {
            if prevRow[c].score > best {
                best = prevRow[c].score
            }
        }

        // Clamp: 0 means no match
        return best == sentinel ? 0 : max(best, 1)
    }

    // MARK: - Private

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
        static let maxConsecutive = 5
    }

    private enum Penalty {
        static let gap = 3
        static let maxGap = 5
    }
}
