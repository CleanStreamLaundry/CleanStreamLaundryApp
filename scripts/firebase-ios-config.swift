import Foundation

// Xcode build phase AFTER Copy Bundle Resources. Never copy into Runner sources.
let environment = ProcessInfo.processInfo.environment
let defines = (environment["DART_DEFINES"] ?? "").split(separator: ",").reduce(into: [String: String]()) { result, encoded in
    guard let data = Data(base64Encoded: String(encoded)),
          let text = String(data: data, encoding: .utf8) else { return }
    let pair = text.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
    if pair.count == 2 { result[String(pair[0])] = String(pair[1]) }
}
guard let source = environment["SRCROOT"], let products = environment["BUILT_PRODUCTS_DIR"],
      let contents = environment["CONTENTS_FOLDER_PATH"] else {
    fputs("error: Run from an Xcode build phase with build output paths\n", stderr)
    exit(1)
}
let output = URL(fileURLWithPath: products).appendingPathComponent(contents).appendingPathComponent("GoogleService-Info.plist")
let files = FileManager.default
// A build without an explicit selection must not retain a prior production file.
if files.fileExists(atPath: output.path) { try files.removeItem(at: output) }
if let selected = defines["FIREBASE_ENV"], ["dev", "prod"].contains(selected),
   let key = defines["FIREBASE_IOS_API_KEY"], !key.isEmpty {
    let input = URL(fileURLWithPath: source).appendingPathComponent("../config/firebase/\(selected)/GoogleService-Info.plist")
    if files.fileExists(atPath: input.path) {
        let data = try Data(contentsOf: input)
        let config = try PropertyListSerialization.propertyList(from: data, format: nil) as! [String: Any]
        let dev = selected == "dev"
        guard config["PROJECT_ID"] as? String == (dev ? "clean-stream-dev" : "clean-stream-production"),
              config["GOOGLE_APP_ID"] as? String == (dev ? "1:83380736317:ios:3fe930785b224eb30af554" : "1:863183154828:ios:1f263e0ea3df94bde615a9"),
              config["BUNDLE_ID"] as? String == "com.cleanstreamlaundrysolutions.clenaStreamLaundryApp",
              config["API_KEY"] as? String == key else {
            fputs("error: Firebase native/Dart environment mismatch\n", stderr)
            exit(1)
        }
        try files.copyItem(at: input, to: output)
    } else {
        print("warning: Firebase native config missing for explicitly selected environment")
    }
} else {
    print("warning: Optional Firebase disabled: provide explicit FIREBASE_ENV and FIREBASE_IOS_API_KEY")
}
