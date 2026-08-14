import Foundation

public enum OpenSessionRetry {
    public static func shouldRetry(domain: String, code: Int, description: String) -> Bool {
        domain == "com.apple.ImageCaptureCore"
            && code == -9943
            && (description as NSString).range(of: "unlock", options: .caseInsensitive).location != NSNotFound
    }
}
