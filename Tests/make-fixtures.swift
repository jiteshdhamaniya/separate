// Synthetic fixtures only: no user documents or third-party sample files.
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

guard CommandLine.arguments.count == 2 else { fatalError("Pass an output directory") }
let directory = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
let colorSpace = CGColorSpaceCreateDeviceRGB()
for index in 1...2 {
    let imageURL = directory.appendingPathComponent(index == 1 ? "image-one.png" : "image-two.png")
    let bitmap = CGContext(data: nil, width: 400, height: 240, bitsPerComponent: 8, bytesPerRow: 0,
                           space: colorSpace, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    bitmap.setFillColor(CGColor(red: 0.12, green: 0.15, blue: 0.5, alpha: 1))
    bitmap.fill(CGRect(x: 0, y: 0, width: 400, height: 240))
    bitmap.setFillColor(CGColor(red: 0.3, green: 0.7, blue: 1, alpha: 1))
    bitmap.fillEllipse(in: CGRect(x: index * 50, y: 70, width: 120, height: 120))
    let destination = CGImageDestinationCreateWithURL(imageURL as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, bitmap.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination))

    let pdfURL = directory.appendingPathComponent(index == 1 ? "window-one.pdf" : "window-two.pdf")
    var page = CGRect(x: 0, y: 0, width: 400, height: 500)
    let consumer = CGDataConsumer(url: pdfURL as CFURL)!
    let pdf = CGContext(consumer: consumer, mediaBox: &page, nil)!
    for number in 1...2 {
        pdf.beginPDFPage(nil)
        pdf.setFillColor(CGColor(red: 0.1, green: 0.2, blue: CGFloat(number) * 0.3, alpha: 1))
        pdf.fill(CGRect(x: 40, y: 60, width: 320, height: 380))
        pdf.setFillColor(CGColor(gray: 1, alpha: 1))
        pdf.fill(CGRect(x: 70, y: 100, width: 260, height: 36))
        pdf.endPDFPage()
    }
    pdf.closePDF()
}
try Data("Intentionally invalid PDF fixture".utf8).write(to: directory.appendingPathComponent("invalid.pdf"))
print("Created synthetic PDF and PNG fixtures")
