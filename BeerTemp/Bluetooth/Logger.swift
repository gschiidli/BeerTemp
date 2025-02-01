import Foundation

class CsvLogger {
    let logFileURL: URL
    var fileHandle: FileHandle?

    init(fileName: String) {
        let fileManager = FileManager.default
        let directory = fileManager.temporaryDirectory
        logFileURL = directory.appendingPathComponent(fileName)

        // Ensure file exists
        if !fileManager.fileExists(atPath: logFileURL.path) {
            fileManager.createFile(atPath: logFileURL.path, contents: nil, attributes: nil)
        }

        // Open file for writing
        do {
            fileHandle = try FileHandle(forWritingTo: logFileURL)
            fileHandle?.seekToEndOfFile() // Move pointer to end for appending
        } catch {
            print("Failed to open log file: \(error)")
        }
    }

    func log(_ value: Double?) {
        let timestamp = Date().formatted(.iso8601)
        let logMessage = "\(timestamp), \(value ?? .nan)\n"

        if let data = logMessage.data(using: .utf8) {
            fileHandle?.write(data)
        }
    }

    deinit {
        fileHandle?.closeFile()
    }
}
