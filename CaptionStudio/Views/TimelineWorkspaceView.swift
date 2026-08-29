import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

/// Timeline lanes that can host clips.
enum TimelineLaneID: String, CaseIterable, Identifiable, Hashable {
    case captions
    case wordHits
    case stickers
    case text
    case audio
    case sfx
    case trim

    var id: String { rawValue }

    var title: String {
        switch self {
        case .captions: return "Caps"
        case .wordHits: return "Hits"
        case .stickers: return "Stick"
        case .text: return "Text"
        case .audio: return "Audio"
        case .sfx: return "SFX"
        case .trim: return "Trim"
        }
    }

    var color: Color {
        switch self {
        case .captions: return TimelineLaneStyle.captions
        case .wordHits: return TimelineLaneStyle.wordHit
        case .stickers: return TimelineLaneStyle.sticker
        case .text: return TimelineLaneStyle.text
        case .audio: return TimelineLaneStyle.audio
        case .sfx: return TimelineLaneStyle.sfx
        case .trim: return TimelineLaneStyle.trim
        }
    }

    /// Lanes that accept dropped overlay / caption clips.
    var acceptsClips: Bool {
        switch self {
        case .captions, .wordHits, .stickers, .text, .sfx: return true
        case .audio, .trim: return false
        }
    }
}

enum TimelineClipRef: Hashable {
    case caption(UUID)
    case overlay(UUID)
    case sfx(UUID)
    case trim(UUID)
    case audio
}

struct TimelineClip: Identifiable, Hashable {
    var id: String
    var ref: TimelineClipRef
    var lane: TimelineLaneID
    var start: TimeInterval
    var end: TimeInterval
    var selected: Bool
    var isDraggable: Bool
}

/// Zoomable multi-lane timeline: drag clips across lanes (kind/order) and time.
/// Scale bar goes from fitting (media + 1h) down to ~5mm per video frame.
struct TimelineWorkspaceView: View {
    @EnvironmentObject private var editor: EditorViewModel

    /// 0 = zoomed out (media + 1 hour fits), 1 = ~5mm per frame.
    @State private var zoom: Double = 0.2
    @State private var drag: DragSession?
    @State private var snapGuide: TimeInterval?
    @State private var viewportWidth: CGFloat = 480
    @State private var playheadScrollToken: Int = 0

    private let labelWidth: CGFloat = 34
    private let laneHeight: CGFloat = 22
    private let laneSpacing: CGFloat = 4
    /// ~5mm at 72dpi.
    private let frameGapPoints: CGFloat = 14.17
    private let frameDuration: TimeInterval = 1.0 / 30.0
    private let padBeyondMedia: TimeInterval = 3600

    private var mediaDuration: TimeInterval { max(editor.project.duration, 0.1) }
    private var timelineSpan: TimeInterval { mediaDuration + padBeyondMedia }

    private var pixelsPerSecond: CGFloat {
        let minPPS = max(0.04, viewportWidth / CGFloat(timelineSpan))
        let maxPPS = frameGapPoints / CGFloat(frameDuration)
        let t = CGFloat(min(1, max(0, zoom)))
        return minPPS * pow(maxPPS / minPPS, t)
    }

    private var contentWidth: CGFloat {
        max(viewportWidth, CGFloat(timelineSpan) * pixelsPerSecond)
    }

    private var visibleLanes: [TimelineLaneID] {
        var lanes: [TimelineLaneID] = [.captions, .wordHits, .stickers, .text, .audio, .sfx]
        if !editor.trimSuggestions.isEmpty { lanes.append(.trim) }
        return lanes
    }

    private var multiSelectCount: Int {
        max(
            editor.selectedCaptionIDs.count,
            editor.selectedOverlayIDs.count,
            editor.selectedSoundEffectIDs.count,
            editor.selectedTrimIDs.count
        )
    }

    private var additiveModifierDown: Bool {
        #if os(macOS)
        NSEvent.modifierFlags.contains(.shift) || NSEvent.modifierFlags.contains(.command)
        #else
        false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            zoomBar
            playheadSlider

            GeometryReader { geo in
                let trackWidth = max(1, geo.size.width - labelWidth - 6)
                Color.clear
                    .onAppear { viewportWidth = trackWidth }
                    .onChange(of: geo.size.width) { _, w in
                        viewportWidth = max(1, w - labelWidth - 6)
                    }

                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: laneSpacing) {
                            timeRuler
                            ForEach(Array(visibleLanes.enumerated()), id: \.element.id) { index, lane in
                                laneRow(lane: lane, laneIndex: index)
                                    .id("lane-\(lane.rawValue)")
                            }
                        }
                        .frame(width: contentWidth + labelWidth + 6, alignment: .leading)
                        .overlay(alignment: .topLeading) {
                            if let guide = snapGuide ?? drag?.snapGuide {
                                Rectangle()
                                    .fill(Color.cyan.opacity(0.85))
                                    .frame(width: 1.5, height: CGFloat(visibleLanes.count) * (laneHeight + laneSpacing) + 18)
                                    .offset(x: labelWidth + 6 + xPosition(for: guide))
                                    .allowsHitTesting(false)
                            }
                        }
                        .overlay(alignment: .topLeading) {
                            Color.clear
                                .frame(width: 1, height: 1)
                                .offset(x: labelWidth + 6 + xPosition(for: editor.currentTime))
                                .id("playhead-anchor")
                        }
                        .padding(.bottom, 4)
                    }
                    .onChange(of: playheadScrollToken) { _, _ in
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo("playhead-anchor", anchor: .center)
                        }
                    }
                }
            }
            .frame(height: CGFloat(visibleLanes.count) * (laneHeight + laneSpacing) + 28)
        }
    }

    // MARK: - Chrome

    private var zoomBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "minus.magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            Slider(value: $zoom, in: 0...1)
                .tint(TimelineLaneStyle.captions)
            Image(systemName: "plus.magnifyingglass")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            Text(zoomLabel)
                .font(.custom("AvenirNext-Medium", size: 10))
                .foregroundStyle(.white.opacity(0.45))
                .frame(minWidth: 72, alignment: .trailing)
            Button {
                editor.timelineMultiSelectMode.toggle()
            } label: {
                Text(editor.timelineMultiSelectMode ? "Multi ✓" : "Multi")
                    .font(.custom("AvenirNext-Medium", size: 10))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(
                            editor.timelineMultiSelectMode
                                ? Color.cyan.opacity(0.35)
                                : Color.white.opacity(0.08)
                        )
                    )
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.75))
            .help("Toggle additive multi-select (or hold Shift/⌘ on Mac)")
            if multiSelectCount > 1 {
                Text("\(multiSelectCount) sel")
                    .font(.custom("AvenirNext-Medium", size: 10))
                    .foregroundStyle(Color.cyan.opacity(0.9))
            }
            Button {
                playheadScrollToken += 1
            } label: {
                Image(systemName: "viewfinder")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.55))
            .help("Scroll playhead into view")
        }
    }

    private var zoomLabel: String {
        let pps = pixelsPerSecond
        let secPerScreen = Double(viewportWidth / max(pps, 0.001))
        if secPerScreen >= 3600 {
            return String(format: "%.1fh span", secPerScreen / 3600)
        }
        if secPerScreen >= 60 {
            return String(format: "%.0fm span", secPerScreen / 60)
        }
        if pps >= frameGapPoints / CGFloat(frameDuration) * 0.85 {
            return "≈1 frame / 5mm"
        }
        return String(format: "%.1fs span", secPerScreen)
    }

    private var playheadSlider: some View {
        Slider(
            value: Binding(
                get: { editor.currentTime },
                set: { editor.seek(to: $0) }
            ),
            in: 0...mediaDuration
        )
        .tint(TimelineLaneStyle.captions)
    }

    private var timeRuler: some View {
        HStack(spacing: 6) {
            Text("Time")
                .font(.custom("AvenirNext-Medium", size: 9))
                .foregroundStyle(.white.opacity(0.35))
                .frame(width: labelWidth, alignment: .leading)
            ZStack(alignment: .leading) {
                Rectangle()
                    .fill(Color.white.opacity(0.04))
                    .frame(height: 16)
                // Media end marker
                Rectangle()
                    .fill(Color.orange.opacity(0.7))
                    .frame(width: 1.5, height: 16)
                    .offset(x: xPosition(for: mediaDuration))
                ForEach(rulerTicks, id: \.self) { tick in
                    VStack(spacing: 1) {
                        Rectangle()
                            .fill(Color.white.opacity(tick.isMajor ? 0.35 : 0.15))
                            .frame(width: 1, height: tick.isMajor ? 10 : 6)
                        if tick.isMajor {
                            Text(formatTick(tick.time))
                                .font(.system(size: 8, weight: .medium, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    .offset(x: xPosition(for: tick.time))
                }
                playheadLine(height: 16)
            }
            .frame(width: contentWidth, height: 18, alignment: .leading)
            .clipped()
        }
    }

    // MARK: - Lanes

    private func laneRow(lane: TimelineLaneID, laneIndex: Int) -> some View {
        HStack(spacing: 6) {
            Text(lane.title)
                .font(.custom("AvenirNext-Medium", size: 9))
                .foregroundStyle(lane.color.opacity(0.85))
                .frame(width: labelWidth, alignment: .leading)

            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(Color.white.opacity(drag?.hoverLane == lane ? 0.12 : 0.06))
                    .frame(width: contentWidth, height: laneHeight)

                // Dim region past media end
                Rectangle()
                    .fill(Color.black.opacity(0.25))
                    .frame(width: max(0, contentWidth - xPosition(for: mediaDuration)), height: laneHeight)
                    .offset(x: xPosition(for: mediaDuration))

                ForEach(clips(for: lane)) { clip in
                    clipView(clip, laneIndex: laneIndex)
                }

                playheadLine(height: laneHeight)
            }
            .frame(width: contentWidth, height: laneHeight, alignment: .leading)
            .clipped()
            .contentShape(Rectangle())
            .onTapGesture { location in
                let t = time(atX: location.x)
                editor.seek(to: min(mediaDuration, max(0, t)))
                if lane == .audio {
                    editor.selectAudioLayer()
                } else if !additiveSelectActive {
                    editor.clearTimelineMultiSelection()
                }
            }
        }
        .frame(height: laneHeight)
    }

    private func clipView(_ clip: TimelineClip, laneIndex: Int) -> some View {
        let isDragging = drag?.clipID == clip.id || (drag?.groupRefs.contains(clip.ref) ?? false)
        let live = livePlacement(for: clip)
        let x = xPosition(for: live.start)
        // While dragging primary clip alone, vertical follow; multi-drag stays in lane.
        let yLift: CGFloat = {
            guard drag?.clipID == clip.id, let d = drag, d.groupRefs.count <= 1 else { return 0 }
            return d.translation.height
        }()
        let width = max(6, CGFloat(max(0.05, live.end - live.start)) * pixelsPerSecond)

        return Capsule()
            .fill(clip.lane.color.opacity(clip.selected || isDragging ? 0.95 : 0.55))
            .overlay(
                Capsule()
                    .strokeBorder(Color.white.opacity(clip.selected || isDragging ? 0.7 : 0), lineWidth: 1)
            )
            .frame(width: width, height: laneHeight - 6)
            .offset(x: x, y: yLift)
            .zIndex(isDragging ? 50 : (clip.selected ? 5 : 1))
            .contentShape(Capsule())
            .gesture(clip.isDraggable ? dragGesture(for: clip, laneIndex: laneIndex) : nil)
            .onTapGesture { select(clip) }
            .help(clipHelp(clip))
    }

    private func playheadLine(height: CGFloat) -> some View {
        Rectangle()
            .fill(Color.white.opacity(0.9))
            .frame(width: 1.5, height: height)
            .offset(x: xPosition(for: editor.currentTime))
            .allowsHitTesting(false)
    }

    // MARK: - Drag

    private struct DragSession {
        var clipID: String
        var ref: TimelineClipRef
        var sourceLane: TimelineLaneID
        var originStart: TimeInterval
        var originEnd: TimeInterval
        var sourceLaneIndex: Int
        var translation: CGSize = .zero
        var hoverLane: TimelineLaneID
        var groupRefs: [TimelineClipRef] = []
        var snapGuide: TimeInterval?
        var snappedStart: TimeInterval?
        var snappedEnd: TimeInterval?
    }

    private var additiveSelectActive: Bool {
        editor.timelineMultiSelectMode || additiveModifierDown
    }

    private func dragGesture(for clip: TimelineClip, laneIndex: Int) -> some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                if drag == nil {
                    let group = editor.timelineMultiDragGroup(for: clip.ref)
                    drag = DragSession(
                        clipID: clip.id,
                        ref: clip.ref,
                        sourceLane: clip.lane,
                        originStart: clip.start,
                        originEnd: clip.end,
                        sourceLaneIndex: laneIndex,
                        hoverLane: clip.lane,
                        groupRefs: group
                    )
                    if !editor.isTimelineClipSelected(clip.ref) {
                        editor.selectTimelineClip(ref: clip.ref, additive: false, seekTo: clip.start)
                    }
                }
                guard var session = drag, session.clipID == clip.id else { return }
                session.translation = value.translation

                let multi = session.groupRefs.count > 1
                // Multi-drag is retime-only (stay on source lane).
                session.hoverLane = multi
                    ? session.sourceLane
                    : (laneAt(
                        sourceIndex: session.sourceLaneIndex,
                        verticalOffset: value.translation.height
                    ) ?? session.sourceLane)

                let dt = TimeInterval(value.translation.width / max(pixelsPerSecond, 0.001))
                var newStart = session.originStart + dt
                var newEnd = session.originEnd + dt
                let len = max(0.05, session.originEnd - session.originStart)
                newStart = min(max(0, newStart), mediaDuration - 0.05)
                newEnd = min(mediaDuration, max(newStart + 0.05, newStart + len))

                let exclude = Set(session.groupRefs.map(clipIdString(for:)))
                let anchors = TimelineSnap.collectAnchors(
                    clips: allSnapClips(),
                    excluding: exclude,
                    playhead: editor.currentTime,
                    mediaDuration: mediaDuration
                )
                let snapped = TimelineSnap.snapInterval(
                    start: newStart,
                    end: newEnd,
                    anchors: anchors,
                    threshold: TimelineSnap.threshold(pixelsPerSecond: Double(pixelsPerSecond))
                )
                session.snappedStart = snapped.start
                session.snappedEnd = snapped.end
                session.snapGuide = snapped.guide
                snapGuide = snapped.guide
                drag = session
            }
            .onEnded { value in
                guard let session = drag, session.clipID == clip.id else {
                    drag = nil
                    snapGuide = nil
                    return
                }

                let multi = session.groupRefs.count > 1
                let rawDt = TimeInterval(value.translation.width / max(pixelsPerSecond, 0.001))
                let snappedStart = session.snappedStart ?? (session.originStart + rawDt)
                let delta = snappedStart - session.originStart

                if multi {
                    editor.applyTimelineMultiRetime(refs: session.groupRefs, delta: delta)
                } else {
                    let len = max(0.05, session.originEnd - session.originStart)
                    var newStart = snappedStart
                    var newEnd = session.snappedEnd ?? (newStart + len)
                    newStart = min(max(0, newStart), mediaDuration - 0.05)
                    newEnd = min(mediaDuration, max(newStart + 0.05, newStart + len))
                    let target = laneAt(
                        sourceIndex: session.sourceLaneIndex,
                        verticalOffset: value.translation.height
                    ) ?? session.sourceLane
                    editor.applyTimelineDrag(
                        ref: session.ref,
                        fromLane: session.sourceLane,
                        toLane: target,
                        start: newStart,
                        end: newEnd
                    )
                }
                drag = nil
                snapGuide = nil
            }
    }

    private func clipIdString(for ref: TimelineClipRef) -> String {
        switch ref {
        case .caption(let id): return "cap-\(id.uuidString)"
        case .overlay(let id): return "ov-\(id.uuidString)"
        case .sfx(let id): return "sfx-\(id.uuidString)"
        case .trim(let id): return "trim-\(id.uuidString)"
        case .audio: return "audio"
        }
    }

    private func allSnapClips() -> [(id: String, start: TimeInterval, end: TimeInterval)] {
        var out: [(id: String, start: TimeInterval, end: TimeInterval)] = []
        for c in editor.project.captions {
            out.append(("cap-\(c.id.uuidString)", c.startTime, c.endTime))
        }
        for o in editor.project.overlays {
            out.append(("ov-\(o.id.uuidString)", o.startTime, o.endTime))
        }
        for s in editor.project.soundEffects {
            let len = editor.sfxDuration(for: s)
            out.append(("sfx-\(s.id.uuidString)", s.startTime, s.startTime + len))
        }
        return out
    }

    private func laneAt(sourceIndex: Int, verticalOffset: CGFloat) -> TimelineLaneID? {
        let stride = laneHeight + laneSpacing
        let index = Int((CGFloat(sourceIndex) * stride + verticalOffset + laneHeight * 0.5) / stride)
        let lanes = visibleLanes
        guard index >= 0, index < lanes.count else { return nil }
        return lanes[index]
    }

    private func livePlacement(for clip: TimelineClip) -> (start: TimeInterval, end: TimeInterval) {
        guard let d = drag else { return (clip.start, clip.end) }
        let inGroup = d.groupRefs.contains(clip.ref) || d.clipID == clip.id
        guard inGroup else { return (clip.start, clip.end) }
        if d.clipID == clip.id, let s = d.snappedStart, let e = d.snappedEnd {
            return (s, e)
        }
        let dt = (d.snappedStart ?? (d.originStart + TimeInterval(d.translation.width / max(pixelsPerSecond, 0.001)))) - d.originStart
        let len = max(0.05, clip.end - clip.start)
        let start = min(max(0, clip.start + dt), mediaDuration - 0.05)
        let end = min(mediaDuration, max(start + 0.05, start + len))
        return (start, end)
    }

    // MARK: - Data

    private func clips(for lane: TimelineLaneID) -> [TimelineClip] {
        switch lane {
        case .captions:
            return editor.project.captions.map {
                TimelineClip(
                    id: "cap-\($0.id.uuidString)",
                    ref: .caption($0.id),
                    lane: .captions,
                    start: $0.startTime,
                    end: $0.endTime,
                    selected: editor.isTimelineClipSelected(.caption($0.id)),
                    isDraggable: true
                )
            }
        case .wordHits:
            return editor.project.overlays.filter { $0.kind == .wordHit }.map(overlayClip)
        case .stickers:
            return editor.project.overlays.filter { $0.kind == .gif || $0.kind == .png }.map(overlayClip)
        case .text:
            return editor.project.overlays.filter {
                $0.kind == .text || $0.kind == .emoji || $0.kind == .watermark || $0.kind == .shape
            }.map(overlayClip)
        case .audio:
            return [
                TimelineClip(
                    id: "audio-dialogue",
                    ref: .audio,
                    lane: .audio,
                    start: 0,
                    end: mediaDuration,
                    selected: editor.isAudioLayerSelected,
                    isDraggable: false
                )
            ]
        case .sfx:
            return editor.timelineSoundEffects.map { cue in
                let len = editor.sfxDuration(for: cue)
                return TimelineClip(
                    id: "sfx-\(cue.id.uuidString)",
                    ref: .sfx(cue.id),
                    lane: .sfx,
                    start: cue.startTime,
                    end: min(mediaDuration, cue.startTime + len),
                    selected: editor.isTimelineClipSelected(.sfx(cue.id)),
                    isDraggable: true
                )
            }
        case .trim:
            return editor.trimSuggestions.map {
                TimelineClip(
                    id: "trim-\($0.id.uuidString)",
                    ref: .trim($0.id),
                    lane: .trim,
                    start: $0.startTime,
                    end: $0.endTime,
                    selected: editor.selectedTrimIDs.contains($0.id),
                    isDraggable: true
                )
            }
        }
    }

    private func overlayClip(_ item: OverlayItem) -> TimelineClip {
        let lane: TimelineLaneID
        switch item.kind {
        case .wordHit: lane = .wordHits
        case .gif, .png: lane = .stickers
        default: lane = .text
        }
        return TimelineClip(
            id: "ov-\(item.id.uuidString)",
            ref: .overlay(item.id),
            lane: lane,
            start: item.startTime,
            end: item.endTime,
            selected: editor.isTimelineClipSelected(.overlay(item.id)),
            isDraggable: true
        )
    }

    private func select(_ clip: TimelineClip) {
        editor.selectTimelineClip(
            ref: clip.ref,
            additive: additiveSelectActive,
            seekTo: clip.start
        )
    }

    private func clipHelp(_ clip: TimelineClip) -> String {
        if !clip.isDraggable { return "Audio bed (not movable)" }
        if multiSelectCount > 1, editor.isTimelineClipSelected(clip.ref) {
            return String(
                format: "%.2fs–%.2fs · multi-drag retimes selection · edges snap to guides",
                clip.start,
                clip.end
            )
        }
        return String(
            format: "%.2fs–%.2fs · drag to retime (snaps) · up/down to change lane",
            clip.start,
            clip.end
        )
    }

    // MARK: - Math / ruler

    private func xPosition(for time: TimeInterval) -> CGFloat {
        CGFloat(time) * pixelsPerSecond
    }

    private func time(atX x: CGFloat) -> TimeInterval {
        TimeInterval(x / max(pixelsPerSecond, 0.001))
    }

    private struct RulerTick: Hashable {
        var time: TimeInterval
        var isMajor: Bool
    }

    private var rulerTicks: [RulerTick] {
        let pps = Double(pixelsPerSecond)
        // Aim for ~80pt between major ticks.
        let majorStep: TimeInterval
        if pps > 200 { majorStep = 0.5 }
        else if pps > 80 { majorStep = 1 }
        else if pps > 20 { majorStep = 5 }
        else if pps > 5 { majorStep = 15 }
        else if pps > 1 { majorStep = 60 }
        else { majorStep = 300 }

        var ticks: [RulerTick] = []
        var t: TimeInterval = 0
        while t <= timelineSpan + 0.001 {
            ticks.append(RulerTick(time: t, isMajor: true))
            t += majorStep
        }
        return ticks
    }

    private func formatTick(_ t: TimeInterval) -> String {
        let total = Int(t.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return String(format: "%d:%02d:%02d", h, m, s) }
        return String(format: "%d:%02d", m, s)
    }
}
