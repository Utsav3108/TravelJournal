// Throwaway spike: SwiftUI ImageRenderer -> multi-page A4 PDF (vector text).
// Run (macOS): swiftc -parse-as-library PDFSpike.swift -o /tmp/pdfspike && /tmp/pdfspike out.pdf
// On iOS the same code works; only the colour/image types differ (UIImage vs NSImage).
import SwiftUI

let a4 = CGSize(width: 595, height: 842)

struct Page: View {
    let n: Int
    var body: some View {
        ZStack(alignment: .topLeading) {
            Color(red: 0.87, green: 0.78, blue: 0.62)          // kraft
            VStack(alignment: .leading, spacing: 24) {
                Text("Stop \(n)").font(.system(size: 44, design: .serif))
                Text("Sardar Pav Bhaji - best butter pav of my life.")
                    .font(.system(size: 16, design: .serif))
                    .padding(16).background(Color(red: 0.98, green: 0.95, blue: 0.88))
                    .rotationEffect(.degrees(n % 2 == 0 ? 2 : -2))      // seeded rotation
                Path { p in p.move(to: .init(x: 0, y: 0)); p.addCurve(to: .init(x: 400, y: 200),
                        control1: .init(x: 200, y: 0), control2: .init(x: 100, y: 200)) }
                    .stroke(Color.brown, style: StrokeStyle(lineWidth: 3, dash: [8, 6]))
                    .frame(width: 400, height: 200)
            }.padding(36)
        }
        .frame(width: a4.width, height: a4.height)
        .clipped()
    }
}

@MainActor func export(to url: URL, pages: Int) {
    var box = CGRect(origin: .zero, size: a4)
    guard let ctx = CGContext(url as CFURL, mediaBox: &box, nil) else { return }
    for n in 1...pages {
        let r = ImageRenderer(content: Page(n: n))
        r.proposedSize = .init(a4)
        r.render { size, draw in            // closure runs synchronously on the main actor
            ctx.beginPDFPage(nil)
            draw(ctx)                        // draws into ctx at origin bottom-left? see notes
            ctx.endPDFPage()
        }
    }
    ctx.closePDF()
}

@main struct Main {
    @MainActor static func main() {
        let out = URL(fileURLWithPath: CommandLine.arguments.dropFirst().first ?? "spike.pdf")
        export(to: out, pages: 2)
        print("wrote", out.path, (try? out.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? -1, "bytes")
    }
}
