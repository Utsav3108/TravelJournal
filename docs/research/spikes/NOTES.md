# PDFSpike notes

Run: `swiftc -parse-as-library PDFSpike.swift -o /tmp/pdfspike && /tmp/pdfspike out.pdf`

Result (macOS 27, Swift 6.4): wrote 13.9 KB, 2-page A4 PDF (MediaBox 595x842), vector text with subsetted fonts, dashed stroke and rotation preserved, upright orientation (no manual flip needed). Not tested: iOS, custom fonts, photos, MapKit, blend modes.
