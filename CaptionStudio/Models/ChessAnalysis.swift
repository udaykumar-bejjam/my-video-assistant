import Foundation
import SwiftUI
import CoreGraphics

/// Chess move quality used for color / SFX / overlay styling.
enum ChessMoveCategory: String, CaseIterable, Identifiable, Codable {
    case brilliant
    case great
    case good
    case book
    case interesting
    case inaccuracy
    case mistake
    case blunder
    case critical
    case normal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .brilliant: return "Brilliant"
        case .great: return "Great"
        case .good: return "Good"
        case .book: return "Book"
        case .interesting: return "Interesting"
        case .inaccuracy: return "Inaccuracy"
        case .mistake: return "Mistake"
        case .blunder: return "Blunder"
        case .critical: return "Critical"
        case .normal: return "Move"
        }
    }

    /// User-facing palette: green / blue / yellow / orange / red.
    var color: CodableColor {
        switch self {
        case .brilliant:
            return CodableColor(r: 0.15, g: 0.92, b: 0.55, a: 1) // green
        case .great, .good:
            return CodableColor(r: 0.25, g: 0.82, b: 0.45, a: 1) // green
        case .book:
            return CodableColor(r: 0.25, g: 0.55, b: 0.98, a: 1) // blue
        case .interesting:
            return CodableColor(r: 1.0, g: 0.88, b: 0.25, a: 1) // yellow
        case .inaccuracy:
            return CodableColor(r: 1.0, g: 0.78, b: 0.2, a: 1) // yellow
        case .mistake:
            return CodableColor(r: 1.0, g: 0.55, b: 0.15, a: 1) // orange
        case .blunder:
            return CodableColor(r: 1.0, g: 0.22, b: 0.22, a: 1) // red
        case .critical:
            return CodableColor(r: 1.0, g: 0.35, b: 0.15, a: 1) // orange-red
        case .normal:
            return CodableColor(r: 0.85, g: 0.88, b: 0.92, a: 1)
        }
    }

    var effectId: String {
        switch self {
        case .brilliant: return "neon-pulse"
        case .great, .good: return "punch"
        case .book: return "rise"
        case .interesting, .inaccuracy: return "color-pulse"
        case .mistake: return "shake"
        case .blunder: return "slam"
        case .critical: return "fire-pulse"
        case .normal: return "flash"
        }
    }

    var sfxId: String {
        switch self {
        case .brilliant: return "cheer-hit"
        case .great, .good: return "ding"
        case .book: return "click"
        case .interesting, .inaccuracy: return "whoosh"
        case .mistake: return "whoosh"
        case .blunder: return "bass-hit"
        case .critical: return "riser"
        case .normal: return "click"
        }
    }

    var isHighlightWorthy: Bool {
        self != .normal
    }

    static func fromNAG(_ nag: Int) -> ChessMoveCategory? {
        switch nag {
        case 3: return .brilliant      // !!
        case 1: return .good           // !
        case 5: return .interesting    // !?
        case 6: return .inaccuracy     // ?!
        case 2: return .mistake        // ?
        case 4: return .blunder        // ??
        case 18, 19, 20, 22: return .critical
        case 14, 15, 16: return .book
        default: return nil
        }
    }

    static func fromSuffix(_ san: String) -> ChessMoveCategory? {
        if san.contains("!!") { return .brilliant }
        if san.contains("??") { return .blunder }
        if san.contains("!?") { return .interesting }
        if san.contains("?!") { return .inaccuracy }
        if san.contains("!") { return .good }
        if san.contains("?") { return .mistake }
        return nil
    }
}

/// One annotated ply ready for overlay planning.
struct ChessAnnotatedMove: Identifiable, Equatable, Codable {
    var id: UUID = UUID()
    var plyIndex: Int
    var moveNumber: Int
    var isWhite: Bool
    var san: String
    var from: String
    var to: String
    var category: ChessMoveCategory
    var givesCheck: Bool
    var isCapture: Bool
    var isCastle: Bool
    var comment: String?
    /// Extra squares to box (checks, hanging pieces, etc.).
    var criticalSquares: [String]
    /// Extra arrows as (from,to) beyond the played move.
    var ideaArrows: [(from: String, to: String)]

    enum CodingKeys: String, CodingKey {
        case id, plyIndex, moveNumber, isWhite, san, from, to, category
        case givesCheck, isCapture, isCastle, comment, criticalSquares
        case ideaArrowFrom, ideaArrowTo
    }

    init(
        plyIndex: Int,
        moveNumber: Int,
        isWhite: Bool,
        san: String,
        from: String,
        to: String,
        category: ChessMoveCategory,
        givesCheck: Bool,
        isCapture: Bool,
        isCastle: Bool,
        comment: String?,
        criticalSquares: [String],
        ideaArrows: [(from: String, to: String)]
    ) {
        self.plyIndex = plyIndex
        self.moveNumber = moveNumber
        self.isWhite = isWhite
        self.san = san
        self.from = from
        self.to = to
        self.category = category
        self.givesCheck = givesCheck
        self.isCapture = isCapture
        self.isCastle = isCastle
        self.comment = comment
        self.criticalSquares = criticalSquares
        self.ideaArrows = ideaArrows
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        plyIndex = try c.decode(Int.self, forKey: .plyIndex)
        moveNumber = try c.decode(Int.self, forKey: .moveNumber)
        isWhite = try c.decode(Bool.self, forKey: .isWhite)
        san = try c.decode(String.self, forKey: .san)
        from = try c.decode(String.self, forKey: .from)
        to = try c.decode(String.self, forKey: .to)
        category = try c.decode(ChessMoveCategory.self, forKey: .category)
        givesCheck = try c.decode(Bool.self, forKey: .givesCheck)
        isCapture = try c.decode(Bool.self, forKey: .isCapture)
        isCastle = try c.decode(Bool.self, forKey: .isCastle)
        comment = try c.decodeIfPresent(String.self, forKey: .comment)
        criticalSquares = try c.decodeIfPresent([String].self, forKey: .criticalSquares) ?? []
        let af = try c.decodeIfPresent([String].self, forKey: .ideaArrowFrom) ?? []
        let at = try c.decodeIfPresent([String].self, forKey: .ideaArrowTo) ?? []
        ideaArrows = zip(af, at).map { (from: $0, to: $1) }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(plyIndex, forKey: .plyIndex)
        try c.encode(moveNumber, forKey: .moveNumber)
        try c.encode(isWhite, forKey: .isWhite)
        try c.encode(san, forKey: .san)
        try c.encode(from, forKey: .from)
        try c.encode(to, forKey: .to)
        try c.encode(category, forKey: .category)
        try c.encode(givesCheck, forKey: .givesCheck)
        try c.encode(isCapture, forKey: .isCapture)
        try c.encode(isCastle, forKey: .isCastle)
        try c.encodeIfPresent(comment, forKey: .comment)
        try c.encode(criticalSquares, forKey: .criticalSquares)
        try c.encode(ideaArrows.map(\.from), forKey: .ideaArrowFrom)
        try c.encode(ideaArrows.map(\.to), forKey: .ideaArrowTo)
    }
}

/// Where the chessboard sits in the video (normalized 0…1).
struct ChessBoardLayout: Equatable, Codable {
    /// Left edge of a-file (white at bottom).
    var originX: CGFloat = 0.14
    /// Top edge of rank 8.
    var originY: CGFloat = 0.16
    /// Board side length in normalized width units.
    var size: CGFloat = 0.72
    var whiteAtBottom: Bool = true

    func center(of square: String) -> CGPoint? {
        guard let coords = ChessSquare.parse(square) else { return nil }
        let file = whiteAtBottom ? coords.file : 7 - coords.file
        let rank = whiteAtBottom ? 7 - coords.rank : coords.rank
        let x = originX + (CGFloat(file) + 0.5) / 8 * size
        let y = originY + (CGFloat(rank) + 0.5) / 8 * size
        return CGPoint(x: x, y: y)
    }

    func squareSize() -> CGFloat { size / 8 }
}

struct ChessSquare {
    var file: Int // 0=a … 7=h
    var rank: Int // 0=1 … 7=8

    var name: String {
        let f = Character(UnicodeScalar(97 + file)!)
        return "\(f)\(rank + 1)"
    }

    static func parse(_ name: String) -> ChessSquare? {
        let s = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard s.count == 2,
              let f = s.first, let r = s.last,
              let fi = f.asciiValue, fi >= 97, fi <= 104,
              let ri = Int(String(r)), ri >= 1, ri <= 8
        else { return nil }
        return ChessSquare(file: Int(fi - 97), rank: ri - 1)
    }
}

struct ChessAnalysisResult: Equatable {
    var headers: [String: String]
    var moves: [ChessAnnotatedMove]
    var summary: String
}
