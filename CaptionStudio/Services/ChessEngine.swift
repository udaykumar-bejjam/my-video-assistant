import Foundation

/// Minimal chess board that can apply SAN moves for walkthrough animation.
struct ChessBoard: Equatable {
    enum Piece: Equatable {
        case king, queen, rook, bishop, knight, pawn
    }

    struct Occupant: Equatable {
        var piece: Piece
        var isWhite: Bool

        var glyph: String {
            switch (piece, isWhite) {
            case (.king, true): return "♔"
            case (.queen, true): return "♕"
            case (.rook, true): return "♖"
            case (.bishop, true): return "♗"
            case (.knight, true): return "♘"
            case (.pawn, true): return "♙"
            case (.king, false): return "♚"
            case (.queen, false): return "♛"
            case (.rook, false): return "♜"
            case (.bishop, false): return "♝"
            case (.knight, false): return "♞"
            case (.pawn, false): return "♟"
            }
        }
    }

    /// 64 squares, index = file + rank * 8 (a1 = 0).
    private(set) var squares: [Occupant?]
    private(set) var whiteToMove: Bool
    private(set) var castling: CastlingRights
    private(set) var enPassantFile: Int?

    struct CastlingRights: Equatable {
        var whiteKing = true
        var whiteQueen = true
        var blackKing = true
        var blackQueen = true
    }

    static func starting() -> ChessBoard {
        var b = ChessBoard(
            squares: Array(repeating: nil, count: 64),
            whiteToMove: true,
            castling: CastlingRights(),
            enPassantFile: nil
        )
        let back: [Piece] = [.rook, .knight, .bishop, .queen, .king, .bishop, .knight, .rook]
        for f in 0..<8 {
            b.squares[f] = Occupant(piece: back[f], isWhite: true)
            b.squares[f + 8] = Occupant(piece: .pawn, isWhite: true)
            b.squares[f + 48] = Occupant(piece: .pawn, isWhite: false)
            b.squares[f + 56] = Occupant(piece: back[f], isWhite: false)
        }
        return b
    }

    func piece(at square: String) -> Occupant? {
        guard let i = Self.index(square) else { return nil }
        return squares[i]
    }

    func piece(atFile file: Int, rank: Int) -> Occupant? {
        guard (0..<8).contains(file), (0..<8).contains(rank) else { return nil }
        return squares[file + rank * 8]
    }

    mutating func applySAN(_ raw: String) throws -> (from: String, to: String, capture: Bool, check: Bool, castle: Bool) {
        var san = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip annotation glyphs / check / mate markers for parsing core move.
        let givesCheck = san.contains("+") || san.contains("#")
        san = san
            .replacingOccurrences(of: "!!", with: "")
            .replacingOccurrences(of: "??", with: "")
            .replacingOccurrences(of: "!?", with: "")
            .replacingOccurrences(of: "?!", with: "")
            .replacingOccurrences(of: "!", with: "")
            .replacingOccurrences(of: "?", with: "")
            .replacingOccurrences(of: "+", with: "")
            .replacingOccurrences(of: "#", with: "")
            .replacingOccurrences(of: "x", with: "")

        if san == "O-O" || san == "0-0" {
            return try castle(kingSide: true, check: givesCheck)
        }
        if san == "O-O-O" || san == "0-0-0" {
            return try castle(kingSide: false, check: givesCheck)
        }

        guard let toSq = Self.trailingSquare(san) else {
            throw ChessParseError.badMove(raw)
        }
        let to = try Self.requireIndex(toSq)
        let isWhite = whiteToMove
        let promo: Piece? = {
            if let eq = san.firstIndex(of: "="), eq < san.endIndex {
                let ch = san[san.index(after: eq)]
                return Self.pieceLetter(ch)
            }
            // Some SAN ends with Q/R/B/N without '='
            if let last = san.last, "QRBN".contains(last), san.count >= 3 {
                let maybe = Self.pieceLetter(last)
                if maybe != nil, ChessSquare.parse(String(san.dropLast()).suffix(2).description) != nil {
                    return maybe
                }
            }
            return nil
        }()

        let movingPiece: Piece
        var disambigFile: Int?
        var disambigRank: Int?

        if let first = san.first, "KQRBN".contains(first) {
            movingPiece = Self.pieceLetter(first) ?? .pawn
            let body = String(san.dropFirst())
            let dest = toSq
            let prefix = body.replacingOccurrences(of: dest, with: "")
                .replacingOccurrences(of: "=", with: "")
                .filter { $0.isLetter || $0.isNumber }
            for ch in prefix {
                if let v = ch.asciiValue, (97...104).contains(v) { disambigFile = Int(v - 97) }
                if let n = Int(String(ch)), (1...8).contains(n) { disambigRank = n - 1 }
            }
        } else {
            movingPiece = .pawn
            // Pawn captures: "ed5" / "exd5" style after x stripped → "ed5"
            if san.count >= 3, let f = san.first, let v = f.asciiValue, (97...104).contains(v) {
                disambigFile = Int(v - 97)
            }
        }

        let candidates = findOrigins(
            piece: movingPiece,
            isWhite: isWhite,
            to: to,
            disambigFile: disambigFile,
            disambigRank: disambigRank
        )
        guard let fromIdx = candidates.first else { throw ChessParseError.badMove(raw) }
        let fromName = Self.name(fromIdx)
        let toName = toSq
        let capture = squares[to] != nil || (movingPiece == .pawn && enPassantFile == to % 8 && to / 8 == (isWhite ? 5 : 2) && squares[to] == nil)

        // En passant capture remove.
        if movingPiece == .pawn, squares[to] == nil, abs((fromIdx % 8) - (to % 8)) == 1 {
            let capIdx = to + (isWhite ? -8 : 8)
            if (0..<64).contains(capIdx) { squares[capIdx] = nil }
        }

        squares[to] = Occupant(piece: promo ?? movingPiece, isWhite: isWhite)
        squares[fromIdx] = nil

        // Castling rights updates.
        if movingPiece == .king {
            if isWhite { castling.whiteKing = false; castling.whiteQueen = false }
            else { castling.blackKing = false; castling.blackQueen = false }
        }
        if movingPiece == .rook {
            if fromIdx == 0 { castling.whiteQueen = false }
            if fromIdx == 7 { castling.whiteKing = false }
            if fromIdx == 56 { castling.blackQueen = false }
            if fromIdx == 63 { castling.blackKing = false }
        }
        if to == 0 { castling.whiteQueen = false }
        if to == 7 { castling.whiteKing = false }
        if to == 56 { castling.blackQueen = false }
        if to == 63 { castling.blackKing = false }

        // En passant target.
        if movingPiece == .pawn, abs((to / 8) - (fromIdx / 8)) == 2 {
            enPassantFile = fromIdx % 8
        } else {
            enPassantFile = nil
        }

        whiteToMove.toggle()
        return (fromName, toName, capture, givesCheck, false)
    }

    private mutating func castle(kingSide: Bool, check: Bool) throws -> (from: String, to: String, capture: Bool, check: Bool, castle: Bool) {
        let isWhite = whiteToMove
        let rank = isWhite ? 0 : 7
        let kingFrom = 4 + rank * 8
        let kingTo = (kingSide ? 6 : 2) + rank * 8
        let rookFrom = (kingSide ? 7 : 0) + rank * 8
        let rookTo = (kingSide ? 5 : 3) + rank * 8
        guard squares[kingFrom]?.piece == .king else { throw ChessParseError.badMove(kingSide ? "O-O" : "O-O-O") }
        squares[kingTo] = squares[kingFrom]
        squares[kingFrom] = nil
        squares[rookTo] = squares[rookFrom]
        squares[rookFrom] = nil
        if isWhite { castling.whiteKing = false; castling.whiteQueen = false }
        else { castling.blackKing = false; castling.blackQueen = false }
        enPassantFile = nil
        whiteToMove.toggle()
        return (Self.name(kingFrom), Self.name(kingTo), false, check, true)
    }

    private func findOrigins(
        piece: Piece,
        isWhite: Bool,
        to: Int,
        disambigFile: Int?,
        disambigRank: Int?
    ) -> [Int] {
        var out: [Int] = []
        for i in 0..<64 {
            guard let occ = squares[i], occ.piece == piece, occ.isWhite == isWhite else { continue }
            let f = i % 8, r = i / 8
            if let df = disambigFile, f != df { continue }
            if let dr = disambigRank, r != dr { continue }
            if canMove(from: i, to: to, piece: piece, isWhite: isWhite) {
                out.append(i)
            }
        }
        return out
    }

    private func canMove(from: Int, to: Int, piece: Piece, isWhite: Bool) -> Bool {
        let ff = from % 8, fr = from / 8
        let tf = to % 8, tr = to / 8
        let df = tf - ff, dr = tr - fr
        if let target = squares[to], target.isWhite == isWhite { return false }

        switch piece {
        case .knight:
            return abs(df) == 1 && abs(dr) == 2 || abs(df) == 2 && abs(dr) == 1
        case .king:
            return max(abs(df), abs(dr)) == 1
        case .pawn:
            let dir = isWhite ? 1 : -1
            let start = isWhite ? 1 : 6
            if df == 0, dr == dir, squares[to] == nil { return true }
            if df == 0, fr == start, dr == 2 * dir, squares[to] == nil,
               squares[ff + (fr + dir) * 8] == nil { return true }
            if abs(df) == 1, dr == dir {
                if let t = squares[to], t.isWhite != isWhite { return true }
                // en passant
                if squares[to] == nil, enPassantFile == tf, tr == (isWhite ? 5 : 2) { return true }
            }
            return false
        case .rook:
            return (df == 0 || dr == 0) && clearPath(from: from, to: to)
        case .bishop:
            return abs(df) == abs(dr) && df != 0 && clearPath(from: from, to: to)
        case .queen:
            return ((df == 0 || dr == 0) || abs(df) == abs(dr)) && clearPath(from: from, to: to)
        }
    }

    private func clearPath(from: Int, to: Int) -> Bool {
        let ff = from % 8, fr = from / 8
        let tf = to % 8, tr = to / 8
        let stepF = (tf - ff).signum()
        let stepR = (tr - fr).signum()
        var f = ff + stepF, r = fr + stepR
        while f != tf || r != tr {
            if squares[f + r * 8] != nil { return false }
            f += stepF
            r += stepR
        }
        return true
    }

    func kingSquare(isWhite: Bool) -> String? {
        for i in 0..<64 {
            guard let occ = squares[i], occ.piece == .king, occ.isWhite == isWhite else { continue }
            return Self.name(i)
        }
        return nil
    }

    static func index(_ name: String) -> Int? {
        guard let sq = ChessSquare.parse(name) else { return nil }
        return sq.file + sq.rank * 8
    }

    static func name(_ index: Int) -> String {
        let f = index % 8, r = index / 8
        return ChessSquare(file: f, rank: r).name
    }

    private static func requireIndex(_ name: String) throws -> Int {
        guard let i = index(name) else { throw ChessParseError.badMove(name) }
        return i
    }

    private static func trailingSquare(_ san: String) -> String? {
        // Find last file+rank pair.
        let chars = Array(san.lowercased())
        guard chars.count >= 2 else { return nil }
        for i in stride(from: chars.count - 2, through: 0, by: -1) {
            let a = chars[i], b = chars[i + 1]
            if (97...104).contains(a.asciiValue ?? 0), (49...56).contains(b.asciiValue ?? 0) {
                return String([a, b])
            }
        }
        return nil
    }

    private static func pieceLetter(_ ch: Character) -> Piece? {
        switch ch {
        case "K": return .king
        case "Q": return .queen
        case "R": return .rook
        case "B": return .bishop
        case "N": return .knight
        default: return nil
        }
    }
}

enum ChessParseError: LocalizedError {
    case empty
    case badMove(String)
    case noMoves

    var errorDescription: String? {
        switch self {
        case .empty: return "Paste a PGN or move list to start the walkthrough."
        case .badMove(let m): return "Could not play move “\(m)”."
        case .noMoves: return "No moves found in the notation."
        }
    }
}

enum ChessPGNParser {
    struct Token {
        var san: String
        var nags: [Int]
        var comment: String?
    }

    static func parse(_ text: String) throws -> ChessAnalysisResult {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ChessParseError.empty }

        var headers: [String: String] = [:]
        var body = trimmed
        // Headers
        let headerRegex = try! NSRegularExpression(pattern: #"\[(\w+)\s+\"([^\"]*)\"\]"#)
        let ns = trimmed as NSString
        for match in headerRegex.matches(in: trimmed, range: NSRange(location: 0, length: ns.length)) {
            let key = ns.substring(with: match.range(at: 1))
            let val = ns.substring(with: match.range(at: 2))
            headers[key] = val
        }
        body = headerRegex.stringByReplacingMatches(in: body, range: NSRange(location: 0, length: (body as NSString).length), withTemplate: " ")

        // Drop variations (parentheses) and results.
        body = stripBalanced(body, open: "(", close: ")")
        body = body
            .replacingOccurrences(of: "1-0", with: " ")
            .replacingOccurrences(of: "0-1", with: " ")
            .replacingOccurrences(of: "1/2-1/2", with: " ")
            .replacingOccurrences(of: "*", with: " ")

        let tokens = tokenizeMoves(body)
        guard !tokens.isEmpty else { throw ChessParseError.noMoves }

        var board = ChessBoard.starting()
        var annotated: [ChessAnnotatedMove] = []

        for (ply, token) in tokens.enumerated() {
            let before = board
            let played = try board.applySAN(token.san)
            var category = ChessMoveCategory.fromSuffix(token.san)
                ?? token.nags.compactMap(ChessMoveCategory.fromNAG).first
                ?? .normal
            if category == .normal, played.check {
                category = .critical
            }

            var critical: [String] = [played.to]
            var ideas: [ChessArrowIdea] = []
            if played.check, let kingSq = board.kingSquare(isWhite: board.whiteToMove) {
                // After move, side to move is the checked side.
                critical.append(kingSq)
                ideas.append(ChessArrowIdea(from: played.to, to: kingSq))
            }
            if played.capture {
                critical.append(played.to)
            }

            // Heuristic: long-range piece moves that give check = critical highlight.
            if played.check { category = category == .normal ? .critical : category }

            annotated.append(
                ChessAnnotatedMove(
                    plyIndex: ply,
                    moveNumber: ply / 2 + 1,
                    isWhite: before.whiteToMove,
                    san: token.san,
                    from: played.from,
                    to: played.to,
                    category: category,
                    givesCheck: played.check,
                    isCapture: played.capture,
                    isCastle: played.castle,
                    comment: token.comment,
                    criticalSquares: Array(Set(critical)),
                    ideaArrows: ideas
                )
            )
        }

        let white = headers["White"] ?? "White"
        let black = headers["Black"] ?? "Black"
        let event = headers["Event"] ?? "Chess walkthrough"
        let highlights = annotated.filter(\.category.isHighlightWorthy).count
        return ChessAnalysisResult(
            headers: headers,
            moves: annotated,
            summary: "\(event): \(white) vs \(black) · \(annotated.count) moves · \(highlights) annotated"
        )
    }

    private static func tokenizeMoves(_ body: String) -> [Token] {
        // Replace brace comments with markers.
        var text = body
        var comments: [String] = []
        while let start = text.firstIndex(of: "{"), let end = text[start...].firstIndex(of: "}") {
            let c = String(text[text.index(after: start)..<end])
            comments.append(c.trimmingCharacters(in: .whitespacesAndNewlines))
            text.replaceSubrange(start...end, with: " __CMT\(comments.count - 1)__ ")
        }

        let parts = text
            .replacingOccurrences(of: "\n", with: " ")
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }

        var tokens: [Token] = []
        var pendingComment: String?
        var pendingNAGs: [Int] = []

        for part in parts {
            if part.hasPrefix("__CMT"), part.hasSuffix("__"),
               let n = Int(part.dropFirst(5).dropLast(2)), comments.indices.contains(n) {
                pendingComment = comments[n]
                continue
            }
            if part.hasPrefix("$"), let nag = Int(part.dropFirst()) {
                pendingNAGs.append(nag)
                continue
            }
            // Skip move numbers "1." "12..."
            if part.last == ".", part.dropLast().allSatisfy(\.isNumber) { continue }
            if part.allSatisfy({ $0 == "." }) { continue }

            var san = part
            // Inline NAGs like e4!! already handled via suffix.
            tokens.append(Token(san: san, nags: pendingNAGs, comment: pendingComment))
            pendingNAGs = []
            pendingComment = nil
            _ = san
        }
        return tokens
    }

    private static func stripBalanced(_ input: String, open: Character, close: Character) -> String {
        var out = ""
        var depth = 0
        for ch in input {
            if ch == open { depth += 1; continue }
            if ch == close { depth = max(0, depth - 1); continue }
            if depth == 0 { out.append(ch) }
        }
        return out
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        guard indices.contains(index) else { return nil }
        return self[index]
    }
}
