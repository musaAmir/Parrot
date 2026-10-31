import Foundation

enum PanelShape: String, CaseIterable {
    case squared, rounded
    var title: String { self == .squared ? "Squared" : "Rounded" }
    var cornerRadius: CGFloat { self == .squared ? 12 : 26 }
}

enum PanelPlacement {
    enum Anchor { case top, bottom }
    static func frame(size: CGSize, screen: CGRect, anchor: Anchor, savedCenter: CGPoint? = nil) -> CGRect {
        let validCenter = savedCenter.flatMap { $0.x.isFinite && $0.y.isFinite ? $0 : nil }
        let center = validCenter ?? CGPoint(x: screen.midX, y: anchor == .top
            ? screen.maxY - 72 - size.height / 2 : screen.minY + 32 + size.height / 2)
        return clamped(size: size, center: center, screen: screen)
    }
    static func resized(_ frame: CGRect, to size: CGSize, screen: CGRect) -> CGRect {
        clamped(size: size, center: CGPoint(x: frame.midX, y: frame.midY), screen: screen)
    }
    private static func clamped(size: CGSize, center: CGPoint, screen: CGRect) -> CGRect {
        CGRect(x: max(screen.minX, min(center.x - size.width / 2, screen.maxX - size.width)),
               y: max(screen.minY, min(center.y - size.height / 2, screen.maxY - size.height)),
               width: size.width, height: size.height)
    }
}
