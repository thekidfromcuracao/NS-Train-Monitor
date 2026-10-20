import AppKit
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 3,
      let image = NSImage(contentsOfFile: CommandLine.arguments[1]),
      let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("Usage: CleanIconBackground input.png output.png")
}

let width = source.width, height = source.height, bytesPerRow = width * 4
var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
let colorSpace = CGColorSpaceCreateDeviceRGB()
let info = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
guard let context = CGContext(data: &pixels, width: width, height: height, bitsPerComponent: 8,
                              bytesPerRow: bytesPerRow, space: colorSpace, bitmapInfo: info.rawValue) else {
    fatalError("Could not create image context")
}
context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))

func isBackground(_ index: Int) -> Bool {
    let offset = index * 4
    let r = Double(pixels[offset]), g = Double(pixels[offset + 1]), b = Double(pixels[offset + 2])
    let maximum = max(r, g, b), minimum = min(r, g, b)
    let saturation = maximum == 0 ? 0 : (maximum - minimum) / maximum
    return maximum > 105 && saturation < 0.22
}

var visited = [Bool](repeating: false, count: width * height)
var queue = [Int](); queue.reserveCapacity(width * height / 3)
for x in 0..<width { queue.append(x); queue.append((height - 1) * width + x) }
for y in 0..<height { queue.append(y * width); queue.append(y * width + width - 1) }
var cursor = 0
while cursor < queue.count {
    let index = queue[cursor]; cursor += 1
    if visited[index] || !isBackground(index) { continue }
    visited[index] = true
    pixels[index * 4 + 3] = 0
    let x = index % width, y = index / width
    if x > 0 { queue.append(index - 1) }
    if x + 1 < width { queue.append(index + 1) }
    if y > 0 { queue.append(index - width) }
    if y + 1 < height { queue.append(index + width) }
}

guard let cleaned = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments[2]) as CFURL,
                                                        UTType.png.identifier as CFString, 1, nil) else {
    fatalError("Could not create PNG")
}
CGImageDestinationAddImage(destination, cleaned, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not save PNG") }
