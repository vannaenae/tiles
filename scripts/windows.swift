// Prints every on-screen app window: owner, x, y, width, height. Needs no permission.
import CoreGraphics

let info = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
for w in info where (w[kCGWindowLayer as String] as? Int) == 0 {
    guard let owner = w[kCGWindowOwnerName as String] as? String,
          let b = w[kCGWindowBounds as String] as? [String: Double] else { continue }
    print("\(owner)\tx=\(Int(b["X"] ?? 0)) y=\(Int(b["Y"] ?? 0)) w=\(Int(b["Width"] ?? 0)) h=\(Int(b["Height"] ?? 0))")
}
