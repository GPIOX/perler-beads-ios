import BeadPatternCore
import Combine
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let beadPatternProject = UTType(exportedAs: "com.cwc.beadpattern.project", conformingTo: .package)
}

final class PatternDocument: ReferenceFileDocument, ObservableObject, @unchecked Sendable {
    private static let defaultPreviewData: Data? = Bundle.main.url(
        forResource: "AppIcon",
        withExtension: "png"
    ).flatMap { try? Data(contentsOf: $0) }

    struct Snapshot {
        let project: PatternProject
        let sourceData: Data?
        let sourceFilename: String?
        let previewData: Data?
    }

    static var readableContentTypes: [UTType] { [.beadPatternProject] }
    static var writableContentTypes: [UTType] { [.beadPatternProject] }
    @Published var project: PatternProject
    @Published var sourceData: Data?
    @Published var sourceFilename: String?
    @Published var previewData: Data?

    init(
        project: PatternProject = PatternProject(),
        sourceData: Data? = nil,
        sourceFilename: String? = nil,
        previewData: Data? = nil
    ) {
        self.project = project
        self.sourceData = sourceData
        self.sourceFilename = sourceFilename
        self.previewData = previewData ?? Self.defaultPreviewData
    }

    required init(configuration: ReadConfiguration) throws {
        guard configuration.contentType == .beadPatternProject,
              configuration.file.isDirectory,
              let children = configuration.file.fileWrappers,
              let manifestData = children["manifest.json"]?.regularFileContents
        else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let decoded = try JSONDecoder.projectDecoder.decode(PatternProject.self, from: manifestData)
        guard decoded.schemaVersion <= PatternProject.currentSchemaVersion else {
            throw PatternCoreError.unsupportedSchema(decoded.schemaVersion)
        }
        project = decoded
        sourceFilename = decoded.sourceFilename
        sourceData = decoded.sourceFilename.flatMap { children[$0]?.regularFileContents }
        previewData = children["preview.png"]?.regularFileContents
    }

    func snapshot(contentType: UTType) throws -> Snapshot {
        Snapshot(
            project: project,
            sourceData: sourceData,
            sourceFilename: sourceFilename,
            previewData: previewData
        )
    }

    func fileWrapper(snapshot: Snapshot, configuration: WriteConfiguration) throws -> FileWrapper {
        try Self.makeFileWrapper(snapshot: snapshot)
    }

    static func makeFileWrapper(snapshot: Snapshot) throws -> FileWrapper {
        var project = snapshot.project
        project.sourceFilename = snapshot.sourceFilename
        project.modifiedAt = .now
        let manifest = try JSONEncoder.projectEncoder.encode(project)
        var children: [String: FileWrapper] = [
            "manifest.json": FileWrapper(regularFileWithContents: manifest),
        ]
        if let data = snapshot.sourceData, let filename = snapshot.sourceFilename {
            children[filename] = FileWrapper(regularFileWithContents: data)
        }
        if let previewData = snapshot.previewData {
            children["preview.png"] = FileWrapper(regularFileWithContents: previewData)
        }
        return FileWrapper(directoryWithFileWrappers: children)
    }
}

extension JSONEncoder {
    static var projectEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    static var projectDecoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
