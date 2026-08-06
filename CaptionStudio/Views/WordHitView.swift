import SwiftUI

/// Significant word with punchy colour / motion effects (not just bold).
struct WordHitView: View {
    let item: OverlayItem
    let time: TimeInterval

    var body: some View {
        let local = max(0, time - item.startTime)
        let effect = WordHitEffect(rawValue: item.effectId ?? "punch") ?? .punch
        let fill = animatedColor(effect, local: local, base: item.color.color)
        let glow = fill.opacity(0.85)

        ZStack {
            // Shockwave / punch ring
            if showsShockwave(effect) {
                Circle()
                    .stroke(fill.opacity(shockOpacity(local)), lineWidth: 3)
                    .frame(width: shockSize(local), height: shockSize(local))
                    .blur(radius: 0.5)
            }

            // Soft glow bloom behind the word
            Text(item.text)
                .font(.custom(resolvedFontName, size: item.fontSize * item.scale * 0.72))
                .foregroundStyle(glow)
                .blur(radius: glowRadius(effect, local: local))
                .scaleEffect(scale(effect, local: local) * 1.04)
                .opacity(0.7)

            // RGB / glitch ghost layers
            if effect == .glitch {
                Text(item.text)
                    .font(.custom(resolvedFontName, size: item.fontSize * item.scale * 0.72))
                    .foregroundStyle(Color.red.opacity(0.7))
                    .offset(x: -3 + shakeX(effect, local: local), y: 1)
                    .blendMode(.screen)
                Text(item.text)
                    .font(.custom(resolvedFontName, size: item.fontSize * item.scale * 0.72))
                    .foregroundStyle(Color.cyan.opacity(0.7))
                    .offset(x: 3 - shakeX(effect, local: local), y: -1)
                    .blendMode(.screen)
            }

            // Heavy outline for punch readability
            Text(item.text)
                .font(.custom(resolvedFontName, size: item.fontSize * item.scale * 0.72))
                .foregroundStyle(.black.opacity(0.9))
                .offset(x: 2, y: 2)

            // Main fill
            Text(item.text)
                .font(.custom(resolvedFontName, size: item.fontSize * item.scale * 0.72))
                .foregroundStyle(fill)
                .shadow(color: fill.opacity(0.9), radius: glowRadius(effect, local: local), y: 0)
                .shadow(color: .black.opacity(0.55), radius: 4, y: 3)
        }
        .rotationEffect(.degrees(item.rotation + spinExtra(effect, local: local)))
        .scaleEffect(scale(effect, local: local))
        .offset(x: shakeX(effect, local: local), y: offsetY(effect, local: local))
        .opacity(opacity(effect, local: local))
        .blur(radius: effect == .glitch && Int(local * 24) % 4 == 0 ? 1.4 : 0)
    }

    private var resolvedFontName: String {
        item.fontName ?? "AvenirNext-Heavy"
    }

    // MARK: - Color

    private func animatedColor(_ effect: WordHitEffect, local: TimeInterval, base: Color) -> Color {
        let palette = effect.palette
        guard palette.count >= 2 else { return base }

        switch effect {
        case .colorPulse, .pulse, .neonPulse:
            // Smooth ping-pong yellow ↔ red (or neon pair)
            let t = 0.5 + 0.5 * sin(local * 8)
            return mix(palette[0], palette[1], t: t)
        case .firePulse:
            let phase = (sin(local * 10) + 1) / 2
            if palette.count >= 3 {
                return phase < 0.5
                    ? mix(palette[0], palette[1], t: phase * 2)
                    : mix(palette[1], palette[2], t: (phase - 0.5) * 2)
            }
            return mix(palette[0], palette[1], t: phase)
        case .punch, .stomp, .slam:
            // Flash secondary on impact, settle to primary
            if local < 0.1 { return palette[1] }
            if local < 0.22 { return mix(palette[1], palette[0], t: (local - 0.1) / 0.12) }
            return palette[0]
        case .shake, .flash:
            return Int(local * 12) % 2 == 0 ? palette[0] : palette[1]
        case .glitch:
            let idx = Int(local * 15) % palette.count
            return palette[idx]
        default:
            if local < 0.15 { return palette[0] }
            return mix(palette[0], palette.count > 1 ? palette[1] : palette[0], t: min(1, local / 0.4))
        }
    }

    private func mix(_ a: Color, _ b: Color, t: Double) -> Color {
        let t = max(0, min(1, t))
        #if canImport(UIKit)
        let ua = UIColor(a), ub = UIColor(b)
        var ar: CGFloat = 0, ag: CGFloat = 0, ab: CGFloat = 0, aa: CGFloat = 0
        var br: CGFloat = 0, bg: CGFloat = 0, bb: CGFloat = 0, ba: CGFloat = 0
        ua.getRed(&ar, green: &ag, blue: &ab, alpha: &aa)
        ub.getRed(&br, green: &bg, blue: &bb, alpha: &ba)
        return Color(
            red: Double(ar + (br - ar) * t),
            green: Double(ag + (bg - ag) * t),
            blue: Double(ab + (bb - ab) * t),
            opacity: Double(aa + (ba - aa) * t)
        )
        #else
        // Approximate using sRGB via CodableColor path
        let ca = CodableColor(a), cb = CodableColor(b)
        return Color(
            red: ca.r + (cb.r - ca.r) * t,
            green: ca.g + (cb.g - ca.g) * t,
            blue: ca.b + (cb.b - ca.b) * t,
            opacity: ca.a + (cb.a - ca.a) * t
        )
        #endif
    }

    // MARK: - Motion

    private func scale(_ effect: WordHitEffect, local: TimeInterval) -> CGFloat {
        switch effect {
        case .punch:
            if local < 0.08 { return 0.35 + CGFloat(local / 0.08) * 1.4 }
            if local < 0.18 { return 1.75 - CGFloat((local - 0.08) / 0.1) * 0.45 }
            return 1.2 + CGFloat(sin(local * 6)) * 0.04
        case .stomp:
            if local < 0.12 { return 1.8 - CGFloat(local / 0.12) * 0.55 }
            return 1.18 + (local < 0.2 ? CGFloat(sin((local - 0.12) * 40)) * 0.06 : 0)
        case .slam:
            return local < 0.12 ? 1.7 - CGFloat(local / 0.12) * 0.45 : 1.2
        case .bounce:
            let t = min(1, local / 0.4)
            return 0.55 + CGFloat(sin(t * .pi)) * 0.7
        case .zoom:
            return 0.25 + min(1, CGFloat(local / 0.3)) * 1.0
        case .colorPulse, .pulse, .firePulse, .neonPulse:
            return 1.1 + CGFloat(sin(local * 9)) * 0.18
        case .flash:
            return local < 0.08 ? 1.55 : 1.15
        case .shake:
            return 1.2 + CGFloat(sin(local * 30)) * 0.05
        default:
            return 1.2
        }
    }

    private func opacity(_ effect: WordHitEffect, local: TimeInterval) -> Double {
        switch effect {
        case .flash:
            return local < 0.05 ? 0.2 : 1
        case .typepop:
            return min(1, local / 0.1)
        case .punch:
            return local < 0.03 ? 0.4 : 1
        default:
            return 1
        }
    }

    private func offsetY(_ effect: WordHitEffect, local: TimeInterval) -> CGFloat {
        switch effect {
        case .rise:
            return 36 - min(36, CGFloat(local / 0.35) * 36)
        case .stomp:
            if local < 0.12 { return -90 + CGFloat(local / 0.12) * 90 }
            return local < 0.22 ? CGFloat(sin((local - 0.12) * 50)) * 4 : 0
        case .bounce:
            return -abs(sin(local * 14)) * 12
        case .punch:
            return local < 0.15 ? CGFloat(sin(local * 50)) * 3 : 0
        default:
            return 0
        }
    }

    private func shakeX(_ effect: WordHitEffect, local: TimeInterval) -> CGFloat {
        switch effect {
        case .shake, .glitch:
            return CGFloat(sin(local * 48)) * 8
        case .punch, .stomp:
            return local < 0.2 ? CGFloat(sin(local * 60)) * 5 : 0
        default:
            return 0
        }
    }

    private func spinExtra(_ effect: WordHitEffect, local: TimeInterval) -> Double {
        guard effect == .spin else { return 0 }
        return min(1, local / 0.35) * 360
    }

    private func glowRadius(_ effect: WordHitEffect, local: TimeInterval) -> CGFloat {
        switch effect {
        case .colorPulse, .firePulse, .neonPulse, .pulse:
            return 8 + CGFloat(sin(local * 9)) * 6
        case .punch, .slam, .stomp:
            return local < 0.2 ? 14 : 7
        case .flash:
            return local < 0.12 ? 18 : 6
        default:
            return 6
        }
    }

    private func showsShockwave(_ effect: WordHitEffect) -> Bool {
        [.punch, .slam, .stomp, .flash].contains(effect)
    }

    private func shockSize(_ local: TimeInterval) -> CGFloat {
        40 + min(160, CGFloat(local / 0.35) * 160)
    }

    private func shockOpacity(_ local: TimeInterval) -> Double {
        max(0, 0.85 - local * 2.2)
    }
}

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif
