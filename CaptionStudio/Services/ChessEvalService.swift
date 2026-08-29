import Foundation

/// Engines that classify chess moves when PGN annotations are missing.
protocol ChessMoveEvaluating {
    var name: String { get }
    /// Enrich moves that are still `.normal` using position eval.
    func enrich(_ result: ChessAnalysisResult) async -> ChessAnalysisResult
}

enum ChessEvalService {
    /// Prefer Stockfish when a UCI binary is available; otherwise heuristic.
    static func preferred() -> ChessMoveEvaluating {
        if let stockfish = StockfishChessEval.makeIfAvailable() {
            return stockfish
        }
        return HeuristicChessEval()
    }

    static func enrich(_ result: ChessAnalysisResult) async -> ChessAnalysisResult {
        await preferred().enrich(result)
    }
}

// MARK: - Material / heuristic

enum HeuristicChessEvalHelpers {
    static func materialCentipawns(_ board: ChessBoard) -> Int {
        var score = 0
        for i in 0..<64 {
            guard let occ = board.piece(atFile: i % 8, rank: i / 8) else { continue }
            let v: Int
            switch occ.piece {
            case .pawn: v = 100
            case .knight: v = 320
            case .bishop: v = 330
            case .rook: v = 500
            case .queen: v = 900
            case .king: v = 0
            }
            score += occ.isWhite ? v : -v
        }
        return score
    }

    /// Approx hanging penalty: pieces attacked by lower/equal value with no defender (crude).
    static func hangingPenalty(_ board: ChessBoard, forWhite: Bool) -> Int {
        var penalty = 0
        for i in 0..<64 {
            guard let occ = board.piece(atFile: i % 8, rank: i / 8), occ.isWhite == forWhite else { continue }
            let value = pieceValue(occ.piece)
            if value == 0 { continue }
            if isAttacked(board, square: i, byWhite: !forWhite) && !isAttacked(board, square: i, byWhite: forWhite) {
                penalty += value
            }
        }
        return penalty
    }

    static func pieceValue(_ piece: ChessBoard.Piece) -> Int {
        switch piece {
        case .pawn: return 100
        case .knight: return 320
        case .bishop: return 330
        case .rook: return 500
        case .queen: return 900
        case .king: return 0
        }
    }

    static func isAttacked(_ board: ChessBoard, square: Int, byWhite: Bool) -> Bool {
        for i in 0..<64 {
            guard let occ = board.piece(atFile: i % 8, rank: i / 8), occ.isWhite == byWhite else { continue }
            if board.canAttack(from: i, to: square, piece: occ.piece, isWhite: byWhite) {
                return true
            }
        }
        return false
    }

    static func categoryFromDeltaCp(
        _ deltaCp: Int,
        gaveCheck: Bool,
        isCapture: Bool
    ) -> ChessMoveCategory {
        if deltaCp <= -500 { return .blunder }
        if deltaCp <= -200 { return .mistake }
        if deltaCp <= -80 { return .inaccuracy }
        if deltaCp >= 500 && !isCapture { return .brilliant }
        if deltaCp >= 300 { return .great }
        if deltaCp >= 120 { return .good }
        if gaveCheck { return .critical }
        if deltaCp >= 40 { return .interesting }
        return .normal
    }
}

struct HeuristicChessEval: ChessMoveEvaluating {
    var name: String { "heuristic" }

    func enrich(_ result: ChessAnalysisResult) async -> ChessAnalysisResult {
        var board = ChessBoard.starting()
        var moves = result.moves
        for i in moves.indices {
            let before = board
            let beforeMat = HeuristicChessEvalHelpers.materialCentipawns(before)
            let beforeHang = HeuristicChessEvalHelpers.hangingPenalty(before, forWhite: moves[i].isWhite)
            do {
                _ = try board.applySAN(moves[i].san)
            } catch {
                continue
            }
            let afterMat = HeuristicChessEvalHelpers.materialCentipawns(board)
            let afterHang = HeuristicChessEvalHelpers.hangingPenalty(board, forWhite: moves[i].isWhite)
            let sign = moves[i].isWhite ? 1 : -1
            let materialDelta = (afterMat - beforeMat) * sign
            let hangDelta = (beforeHang - afterHang) // positive if we fixed hangings / opponent hangs more for us
            // Opponent hangings after our move improve our score.
            let oppHang = HeuristicChessEvalHelpers.hangingPenalty(board, forWhite: !moves[i].isWhite)
            let delta = materialDelta + hangDelta + oppHang / 2

            if moves[i].category == .normal {
                moves[i].category = HeuristicChessEvalHelpers.categoryFromDeltaCp(
                    delta,
                    gaveCheck: moves[i].givesCheck,
                    isCapture: moves[i].isCapture
                )
                moves[i].evalSource = name
                moves[i].evalDeltaCp = delta
            } else {
                moves[i].evalSource = moves[i].evalSource ?? "annotation"
            }
            _ = before
        }
        let highlights = moves.filter(\.category.isHighlightWorthy).count
        var summary = result.summary
        if !summary.contains("eval") {
            summary += " · \(name) eval · \(highlights) highlights"
        }
        return ChessAnalysisResult(headers: result.headers, moves: moves, summary: summary)
    }
}

// MARK: - Stockfish (optional UCI binary)

struct StockfishChessEval: ChessMoveEvaluating {
    var name: String { "stockfish" }
    let executableURL: URL
    var depth: Int = 10

    static func makeIfAvailable() -> StockfishChessEval? {
        let candidates: [URL] = {
            var urls: [URL] = []
            if let bundled = Bundle.main.url(forResource: "stockfish", withExtension: nil) {
                urls.append(bundled)
            }
            urls.append(contentsOf: [
                URL(fileURLWithPath: "/opt/homebrew/bin/stockfish"),
                URL(fileURLWithPath: "/usr/local/bin/stockfish"),
                URL(fileURLWithPath: "/usr/bin/stockfish"),
            ])
            return urls
        }()
        for url in candidates where FileManager.default.isExecutableFile(atPath: url.path) {
            return StockfishChessEval(executableURL: url)
        }
        return nil
    }

    func enrich(_ result: ChessAnalysisResult) async -> ChessAnalysisResult {
        // Fall back to heuristic if UCI session fails mid-game.
        do {
            return try await Task.detached(priority: .userInitiated) { [executableURL, depth] in
                try StockfishChessEval(executableURL: executableURL, depth: depth).enrichWithUCI(result)
            }.value
        } catch {
            return await HeuristicChessEval().enrich(result)
        }
    }

    fileprivate func enrichWithUCI(_ result: ChessAnalysisResult) throws -> ChessAnalysisResult {
        let process = Process()
        process.executableURL = executableURL
        process.arguments = []
        let stdin = Pipe()
        let stdout = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()

        func write(_ line: String) {
            let data = (line + "\n").data(using: .utf8)!
            stdin.fileHandleForWriting.write(data)
        }

        func readUntil(_ predicate: (String) -> Bool, timeoutSeconds: Double = 8) throws -> [String] {
            var lines: [String] = []
            let handle = stdout.fileHandleForReading
            let deadline = Date().addingTimeInterval(timeoutSeconds)
            var buffer = Data()
            while Date() < deadline {
                let chunk = handle.availableData
                if chunk.isEmpty {
                    Thread.sleep(forTimeInterval: 0.02)
                    continue
                }
                buffer.append(chunk)
                while let range = buffer.range(of: Data([0x0A])) {
                    let lineData = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
                    buffer.removeSubrange(buffer.startIndex...range.lowerBound)
                    if let line = String(data: lineData, encoding: .utf8) {
                        lines.append(line)
                        if predicate(line) { return lines }
                    }
                }
            }
            throw ChessParseError.badMove("stockfish timeout")
        }

        write("uci")
        _ = try readUntil { $0 == "uciok" }
        write("isready")
        _ = try readUntil { $0 == "readyok" }

        var board = ChessBoard.starting()
        var uciMoves: [String] = []
        var moves = result.moves
        var prevScoreCp = 0

        for i in moves.indices {
            let before = board
            let played = try board.applySAN(moves[i].san)
            var uci = played.from + played.to
            if let promo = promotionLetter(from: moves[i].san) {
                uci += promo
            }
            uciMoves.append(uci.lowercased())

            write("position startpos moves \(uciMoves.joined(separator: " "))")
            write("go depth \(depth)")
            let lines = try readUntil { $0.hasPrefix("bestmove") }
            var scoreCp = 0
            for line in lines where line.hasPrefix("info") && line.contains(" score ") {
                if let mateRange = line.range(of: "score mate ") {
                    let rest = line[mateRange.upperBound...]
                    let mate = Int(rest.split(separator: " ").first ?? "0") ?? 0
                    scoreCp = mate > 0 ? 10_000 - mate * 10 : -10_000 - mate * 10
                } else if let cpRange = line.range(of: "score cp ") {
                    let rest = line[cpRange.upperBound...]
                    scoreCp = Int(rest.split(separator: " ").first ?? "0") ?? 0
                }
            }
            // Score is from side-to-move after the move; flip to mover's perspective.
            let moverScore = board.whiteToMove ? -scoreCp : scoreCp
            let delta = moverScore - prevScoreCp
            prevScoreCp = moverScore

            if moves[i].category == .normal {
                moves[i].category = HeuristicChessEvalHelpers.categoryFromDeltaCp(
                    delta,
                    gaveCheck: moves[i].givesCheck,
                    isCapture: moves[i].isCapture
                )
                moves[i].evalSource = name
                moves[i].evalDeltaCp = delta
            } else {
                moves[i].evalSource = moves[i].evalSource ?? "annotation"
                moves[i].evalDeltaCp = delta
            }
            _ = before
        }

        write("quit")
        process.terminate()

        let highlights = moves.filter(\.category.isHighlightWorthy).count
        let summary = result.summary + " · stockfish d\(depth) · \(highlights) highlights"
        return ChessAnalysisResult(headers: result.headers, moves: moves, summary: summary)
    }

    private func promotionLetter(from san: String) -> String? {
        if let eq = san.firstIndex(of: "=") {
            let ch = san[san.index(after: eq)].lowercased()
            if "qrbn".contains(ch) { return ch }
        }
        return nil
    }
}

// MARK: - Board attack helper (package-visible via extension in same module)

extension ChessBoard {
    /// Expose attack test for eval hanging-piece heuristics.
    func canAttack(from: Int, to: Int, piece: Piece, isWhite: Bool) -> Bool {
        // Mirror private canMove geometry without mutating — knights/kings/sliders/pawns (captures only for pawns).
        let ff = from % 8, fr = from / 8
        let tf = to % 8, tr = to / 8
        let df = tf - ff, dr = tr - fr
        // `piece` param shadows `piece(atFile:rank:)` — call via self.
        if let target = self.piece(atFile: tf, rank: tr), target.isWhite == isWhite { return false }

        switch piece {
        case .knight:
            return (abs(df) == 1 && abs(dr) == 2) || (abs(df) == 2 && abs(dr) == 1)
        case .king:
            return max(abs(df), abs(dr)) == 1
        case .pawn:
            let dir = isWhite ? 1 : -1
            return abs(df) == 1 && dr == dir
        case .rook:
            return (df == 0 || dr == 0) && clearPathPublic(from: from, to: to)
        case .bishop:
            return abs(df) == abs(dr) && df != 0 && clearPathPublic(from: from, to: to)
        case .queen:
            return ((df == 0 || dr == 0) || abs(df) == abs(dr)) && clearPathPublic(from: from, to: to)
        }
    }

    fileprivate func clearPathPublic(from: Int, to: Int) -> Bool {
        let ff = from % 8, fr = from / 8
        let tf = to % 8, tr = to / 8
        let stepF = (tf - ff).signum()
        let stepR = (tr - fr).signum()
        var f = ff + stepF, r = fr + stepR
        while f != tf || r != tr {
            if piece(atFile: f, rank: r) != nil { return false }
            f += stepF
            r += stepR
        }
        return true
    }
}
