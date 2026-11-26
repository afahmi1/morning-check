#if os(iOS) || os(macOS)
import Foundation
import ImageIO
import Vision

public enum ScoreOCR {
    public static func read(_ data: Data) async -> Int? {
        guard data.count <= 20 * 1024 * 1024 else { return nil }
        return await Task.detached(priority: .userInitiated) {
            guard let source = CGImageSourceCreateWithData(data as CFData, nil),
                  let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                    kCGImageSourceCreateThumbnailFromImageAlways: true,
                    kCGImageSourceCreateThumbnailWithTransform: true,
                    kCGImageSourceThumbnailMaxPixelSize: 2200
                  ] as CFDictionary) else { return nil }
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.recognitionLanguages = ["en-US"]
            do {
                try VNImageRequestHandler(cgImage: image).perform([request])
                let lines: [Line] = (request.results ?? []).compactMap { observation in
                    guard let text = observation.topCandidates(1).first?.string else { return nil }
                    return Line(text: text.trimmingCharacters(in: .whitespacesAndNewlines), box: observation.boundingBox)
                }
                return findScore(in: lines)
            } catch { return nil }
        }.value
    }

    private struct Line {
        let text: String
        let box: CGRect
    }

    // The main card has a large integer to the left of its band. Avoid treating
    // dates, graph axes, or the component fractions farther down as scores.
    private static func findScore(in lines: [Line]) -> Int? {
        let sorted = lines.sorted { $0.box.midY > $1.box.midY }
        let bands = ["very low", "low", "ok", "high", "very high"]
        let headers = sorted.filter { $0.text.caseInsensitiveCompare("Sleep Score") == .orderedSame }
        var found = Set<Int>()
        for header in headers {
            let below = sorted.filter { header.box.midY - $0.box.midY > 0.01 && header.box.midY - $0.box.midY < 0.36 }
            for line in below {
                if let number = ScoreText.manual(line.text), below.contains(where: {
                    bands.contains($0.text.lowercased()) && $0.box.midX > line.box.midX &&
                    abs($0.box.midY - line.box.midY) < max(0.018, line.box.height * 0.5)
                }) { found.insert(number) }
                if let space = line.text.firstIndex(of: " "), let number = ScoreText.manual(String(line.text[..<space])),
                   bands.contains(line.text[line.text.index(after: space)...].trimmingCharacters(in: .whitespaces).lowercased()) {
                    found.insert(number)
                }
            }
        }
        if let textScore = ScoreText.candidate(sorted.map(\.text).joined(separator: "\n")) { found.insert(textScore) }
        return found.count == 1 ? found.first : nil
    }
}
#endif
