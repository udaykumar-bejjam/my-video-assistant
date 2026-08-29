import Foundation

/// Resolves Lichess / chess.com / .pgn URLs and downloads PGN text (P1.9).
/// Algorithm mirrors `enhancer-server/src/chessPgnImport.js`.
enum ChessPGNImportService {
    enum Kind: String {
        case lichess, chesscom, pgnUrl, unknown
    }

    struct Resolved: Equatable {
        var kind: Kind
        var input: String
        var gameId: String?
        var format: String? // live | daily
        var exportURL: URL?
        var callbackURL: URL?
        var errorMessage: String?
    }

    struct Imported {
        var pgn: String
        var source: String
    }

    private static let userAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Safari/605.1.15 CaptionStudio/1.0"

    static func normalize(_ raw: String) -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "<>"))
    }

    static func resolve(_ raw: String) -> Resolved {
        let input = normalize(raw)
        guard !input.isEmpty else {
            return Resolved(kind: .unknown, input: input, errorMessage: "Paste a Lichess, chess.com, or .pgn URL.")
        }
        let withScheme = input.contains("://") ? input : "https://\(input)"
        guard let url = URL(string: withScheme), let hostRaw = url.host else {
            return Resolved(kind: .unknown, input: input, errorMessage: "That doesn’t look like a valid URL.")
        }
        let host = hostRaw.lowercased().replacingOccurrences(of: "www.", with: "")
        let path = url.path

        if host == "lichess.org" || host.hasSuffix(".lichess.org") {
            let exportRx = try! NSRegularExpression(pattern: #"/game/export/([a-zA-Z0-9]{8})"#)
            let bareRx = try! NSRegularExpression(pattern: #"^/([a-zA-Z0-9]{8})(?:/|$)"#)
            let ns = path as NSString
            var gameId: String?
            if let m = exportRx.firstMatch(in: path, range: NSRange(location: 0, length: ns.length)) {
                gameId = ns.substring(with: m.range(at: 1))
            } else if let m = bareRx.firstMatch(in: path, range: NSRange(location: 0, length: ns.length)) {
                gameId = ns.substring(with: m.range(at: 1))
            }
            guard let gameId else {
                return Resolved(kind: .lichess, input: input, errorMessage: "Couldn’t find a Lichess game id in that URL.")
            }
            let export = URL(string: "https://lichess.org/game/export/\(gameId)?clocks=false&evals=false&literate=1")
            return Resolved(kind: .lichess, input: input, gameId: gameId, exportURL: export)
        }

        if host == "chess.com" || host.hasSuffix(".chess.com") {
            let rx = try! NSRegularExpression(pattern: #"/game/(live|daily)/(\d+)"#, options: .caseInsensitive)
            let ns = path as NSString
            guard let m = rx.firstMatch(in: path, range: NSRange(location: 0, length: ns.length)) else {
                return Resolved(
                    kind: .chesscom,
                    input: input,
                    errorMessage: "Use a chess.com game URL like /game/live/123… or /game/daily/123…"
                )
            }
            let format = ns.substring(with: m.range(at: 1)).lowercased()
            let gameId = ns.substring(with: m.range(at: 2))
            let callback = URL(string: "https://www.chess.com/callback/\(format)/game/\(gameId)")
            return Resolved(kind: .chesscom, input: input, gameId: gameId, format: format, callbackURL: callback)
        }

        if path.lowercased().hasSuffix(".pgn") || url.query?.contains("pgn") == true {
            return Resolved(kind: .pgnUrl, input: input, exportURL: url)
        }

        return Resolved(
            kind: .unknown,
            input: input,
            errorMessage: "Supported: lichess.org/…, chess.com/game/live|daily/…, or a direct .pgn URL."
        )
    }

    static func loadFile(url: URL) throws -> String {
        let data = try Data(contentsOf: url)
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else {
            throw ImportError.notPGN
        }
        return text
    }

    static func fetch(from rawURL: String) async throws -> Imported {
        let resolved = resolve(rawURL)
        if let err = resolved.errorMessage { throw ImportError.message(err) }

        switch resolved.kind {
        case .lichess, .pgnUrl:
            guard let exportURL = resolved.exportURL else { throw ImportError.message("Missing export URL.") }
            let text = try await downloadText(from: exportURL, accept: "application/x-chess-pgn, text/plain, */*")
            guard looksLikePGN(text) else { throw ImportError.notPGN }
            return Imported(pgn: text, source: resolved.kind.rawValue)

        case .chesscom:
            guard let callbackURL = resolved.callbackURL, let gameId = resolved.gameId else {
                throw ImportError.message("Missing chess.com game id.")
            }
            let data = try await downloadData(from: callbackURL, accept: "application/json")
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] ?? [:]
            if let message = json["message"] as? String, json["game"] == nil {
                throw ImportError.message(message)
            }
            let game = json["game"] as? [String: Any] ?? [:]
            if let pgn = game["pgn"] as? String, !pgn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return Imported(pgn: pgn.trimmingCharacters(in: .whitespacesAndNewlines), source: "chesscom-callback-pgn")
            }
            let headers = game["pgnHeaders"] as? [String: Any] ?? [:]
            guard let archiveURL = archiveURL(from: headers) else {
                throw ImportError.message(
                    "chess.com didn’t return PGN headers — paste the PGN or use Share → Download."
                )
            }
            let archiveData = try await downloadData(from: archiveURL, accept: "application/json")
            let archive = try JSONSerialization.jsonObject(with: archiveData) as? [String: Any] ?? [:]
            let games = archive["games"] as? [[String: Any]] ?? []
            for g in games {
                let url = g["url"] as? String ?? ""
                if url.contains(gameId), let pgn = g["pgn"] as? String,
                   !pgn.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    return Imported(
                        pgn: pgn.trimmingCharacters(in: .whitespacesAndNewlines),
                        source: "chesscom-archive"
                    )
                }
            }
            throw ImportError.message(
                "Couldn’t find that game in the monthly archive — paste PGN from chess.com Share → Download."
            )

        case .unknown:
            throw ImportError.message(resolved.errorMessage ?? "Unsupported import source.")
        }
    }

    // MARK: - Internals

    enum ImportError: LocalizedError {
        case message(String)
        case notPGN
        case http(Int)

        var errorDescription: String? {
            switch self {
            case .message(let m): return m
            case .notPGN: return "Downloaded text doesn’t look like PGN."
            case .http(let c): return "Download failed (HTTP \(c))."
            }
        }
    }

    private static func looksLikePGN(_ text: String) -> Bool {
        text.contains("[") || text.range(of: #"\d+\."#, options: .regularExpression) != nil
    }

    private static func archiveURL(from headers: [String: Any]) -> URL? {
        func stringValue(_ key: String) -> String {
            if let s = headers[key] as? String { return s }
            if let n = headers[key] as? NSNumber { return n.stringValue }
            return ""
        }
        let white = stringValue("White").trimmingCharacters(in: .whitespacesAndNewlines)
        let date = stringValue("Date").isEmpty ? stringValue("UTCDate") : stringValue("Date")
        let trimmedDate = date.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !white.isEmpty,
              let regex = try? NSRegularExpression(pattern: #"^(\d{4})[.\-/](\d{2})"#),
              let match = regex.firstMatch(
                in: trimmedDate,
                range: NSRange(trimmedDate.startIndex..., in: trimmedDate)
              ),
              let yRange = Range(match.range(at: 1), in: trimmedDate),
              let mRange = Range(match.range(at: 2), in: trimmedDate)
        else { return nil }
        let year = String(trimmedDate[yRange])
        let month = String(trimmedDate[mRange])
        let user = white.lowercased().replacingOccurrences(of: " ", with: "")
        return URL(string: "https://api.chess.com/pub/player/\(user)/games/\(year)/\(month)")
    }

    private static func downloadText(from url: URL, accept: String) async throws -> String {
        let data = try await downloadData(from: url, accept: accept)
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty
        else { throw ImportError.notPGN }
        return text
    }

    private static func downloadData(from url: URL, accept: String) async throws -> Data {
        var request = URLRequest(url: url)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 45
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ImportError.http(http.statusCode)
        }
        return data
    }
}
