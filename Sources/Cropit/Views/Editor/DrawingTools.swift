import SwiftUI

enum DrawingTool: String, CaseIterable {
    case arrow, curvedArrow, line, rect, circle, text, blur, highlight, smartHighlight, freehand, stepNumber, mosaic, emoji, ruler, spotlight, magnifierCallout, eraser, eyedropper, crop
}

struct Annotation: Identifiable {
    var id = UUID()
    var type: AnnotationType
    var color: Color
    var fillColor: Color?
    var lineWidth: CGFloat

    func contains(point: CGPoint) -> Bool {
        let hitInset: CGFloat = 12
        switch type {
        case .arrow(let start, let end):
            return distancePointToSegment(point, start, end) < hitInset + lineWidth
        case .line(let start, let end):
            return distancePointToSegment(point, start, end) < hitInset + lineWidth
        case .curvedArrow(let start, let control, let end):
            if distancePointToSegment(point, start, control) < hitInset + lineWidth { return true }
            if distancePointToSegment(point, control, end) < hitInset + lineWidth { return true }
            return false
        case .rect(let origin, let size):
            return CGRect(origin: origin, size: size).standardized.expand(hitInset).contains(point)
        case .circle(let origin, let size):
            return CGRect(origin: origin, size: size).standardized.expand(hitInset).contains(point)
        case .text(let pos, let text, let fontSize, _):
            let approx = CGSize(width: CGFloat(text.count) * fontSize * 0.6, height: fontSize * 1.4)
            return CGRect(origin: pos, size: approx).expand(hitInset).contains(point)
        case .blur(let origin, let size):
            return CGRect(origin: origin, size: size).standardized.expand(hitInset).contains(point)
        case .highlight(let origin, let size):
            return CGRect(origin: origin, size: size).standardized.expand(hitInset).contains(point)
        case .smartHighlight(let origin, let size):
            return CGRect(origin: origin, size: size).standardized.expand(hitInset).contains(point)
        case .freehand(let points):
            for p in points {
                if hypot(p.x - point.x, p.y - point.y) < hitInset + lineWidth { return true }
            }
            return false
        case .stepNumber(let center, _):
            return hypot(center.x - point.x, center.y - point.y) < 24
        case .mosaic(let origin, let size):
            return CGRect(origin: origin, size: size).standardized.expand(hitInset).contains(point)
        case .emoji(let pos, _, let fontSize):
            let approx = CGSize(width: fontSize * 1.2, height: fontSize * 1.2)
            return CGRect(origin: pos, size: approx).expand(hitInset).contains(point)
        case .ruler(let start, let end):
            return distancePointToSegment(point, start, end) < hitInset + lineWidth
        case .spotlight(let origin, let size):
            return CGRect(origin: origin, size: size).standardized.expand(hitInset).contains(point)
        case .magnifierCallout(let center, let calloutPoint, let radius, _):
            let magRect = CGRect(origin: CGPoint(x: center.x - radius, y: center.y - radius), size: CGSize(width: radius * 2, height: radius * 2))
            if magRect.expand(hitInset).contains(point) { return true }
            if distancePointToSegment(point, center, calloutPoint) < hitInset + lineWidth { return true }
            let bubbleSize = CGSize(width: 120, height: 60)
            let bubbleOrigin = CGPoint(x: calloutPoint.x - bubbleSize.width / 2, y: calloutPoint.y - bubbleSize.height / 2)
            if CGRect(origin: bubbleOrigin, size: bubbleSize).expand(hitInset).contains(point) { return true }
            return false
        case .freehandErase: return false
        }
    }

    func offsetBy(_ delta: CGSize) -> Annotation {
        var copy = self
        switch copy.type {
        case .arrow(let start, let end):
            copy.type = .arrow(start: start + delta, end: end + delta)
        case .line(let start, let end):
            copy.type = .line(start: start + delta, end: end + delta)
        case .curvedArrow(let start, let control, let end):
            copy.type = .curvedArrow(start: start + delta, control: control + delta, end: end + delta)
        case .rect(let origin, let size):
            copy.type = .rect(origin: origin + delta, size: size)
        case .circle(let origin, let size):
            copy.type = .circle(origin: origin + delta, size: size)
        case .text(let pos, let text, let fontSize, let style):
            copy.type = .text(position: pos + delta, text: text, fontSize: fontSize, style: style)
        case .blur(let origin, let size):
            copy.type = .blur(origin: origin + delta, size: size)
        case .highlight(let origin, let size):
            copy.type = .highlight(origin: origin + delta, size: size)
        case .smartHighlight(let origin, let size):
            copy.type = .smartHighlight(origin: origin + delta, size: size)
        case .freehand(let points):
            copy.type = .freehand(points: points.map { $0 + delta })
        case .stepNumber(let center, let number):
            copy.type = .stepNumber(center: center + delta, number: number)
        case .mosaic(let origin, let size):
            copy.type = .mosaic(origin: origin + delta, size: size)
        case .emoji(let pos, let text, let fontSize):
            copy.type = .emoji(position: pos + delta, text: text, fontSize: fontSize)
        case .ruler(let start, let end):
            copy.type = .ruler(start: start + delta, end: end + delta)
        case .spotlight(let origin, let size):
            copy.type = .spotlight(origin: origin + delta, size: size)
        case .magnifierCallout(let center, let calloutPoint, let radius, let scale):
            copy.type = .magnifierCallout(center: center + delta, calloutPoint: calloutPoint + delta, radius: radius, scale: scale)
        case .freehandErase: break
        }
        return copy
    }
}

enum TextStyle: Equatable {
    case regular, bold, italic, boldItalic

    var weight: Font.Weight {
        switch self {
        case .bold, .boldItalic: return .semibold
        default: return .regular
        }
    }

    var design: Font.Design? {
        switch self {
        case .italic, .boldItalic: return .default  // SwiftUI doesn't support italic directly, use NSFont
        default: return nil
        }
    }
}

enum AnnotationType {
    case arrow(start: CGPoint, end: CGPoint)
    case curvedArrow(start: CGPoint, control: CGPoint, end: CGPoint)
    case line(start: CGPoint, end: CGPoint)
    case rect(origin: CGPoint, size: CGSize)
    case circle(origin: CGPoint, size: CGSize)
    case text(position: CGPoint, text: String, fontSize: CGFloat, style: TextStyle = .regular)
    case blur(origin: CGPoint, size: CGSize)
    case highlight(origin: CGPoint, size: CGSize)
    case smartHighlight(origin: CGPoint, size: CGSize)
    case freehand(points: [CGPoint])
    case stepNumber(center: CGPoint, number: Int)
    case mosaic(origin: CGPoint, size: CGSize)
    case emoji(position: CGPoint, text: String, fontSize: CGFloat)
    case ruler(start: CGPoint, end: CGPoint)
    case spotlight(origin: CGPoint, size: CGSize)
    case magnifierCallout(center: CGPoint, calloutPoint: CGPoint, radius: CGFloat, scale: CGFloat)
    case freehandErase
}

struct CanvasState: Equatable {
    var annotations: [Annotation]
    var currentTool: DrawingTool
    var selectedAnnotationId: UUID?
    var rotation: CGFloat

    static func == (lhs: CanvasState, rhs: CanvasState) -> Bool {
        lhs.annotations.map(\.id) == rhs.annotations.map(\.id)
    }
}

let editorColors: [Color] = [
    .red, .orange, .yellow, .green, .blue, .purple, .black, .white
]

let commonEmojis: [String] = [
    "😀", "😂", "❤️", "🔥", "👍", "🎉", "💡", "📌", "⚠️", "✅",
    "❌", "⭐", "🔴", "🟢", "🔵", "🟡", "💬", "👋", "🙏", "🎯",
    "🚀", "👀", "💪", "🔔", "🎈", "💯", "❗", "❓", "➕", "➖",
    "🖐️", "✏️", "🔗", "📎", "🏷️", "💾", "🗑️", "🔍", "🔒", "🔓"
]

extension CGRect {
    func expand(_ d: CGFloat) -> CGRect { insetBy(dx: -d, dy: -d) }
}

private func distancePointToSegment(_ p: CGPoint, _ a: CGPoint, _ b: CGPoint) -> CGFloat {
    let dx = b.x - a.x
    let dy = b.y - a.y
    let lenSq = dx*dx + dy*dy
    guard lenSq > 0 else { return hypot(p.x - a.x, p.y - a.y) }
    var t = ((p.x - a.x)*dx + (p.y - a.y)*dy) / lenSq
    t = max(0, min(1, t))
    let nx = a.x + t*dx
    let ny = a.y + t*dy
    return hypot(p.x - nx, p.y - ny)
}

private func +(lhs: CGPoint, rhs: CGSize) -> CGPoint {
    CGPoint(x: lhs.x + rhs.width, y: lhs.y + rhs.height)
}
