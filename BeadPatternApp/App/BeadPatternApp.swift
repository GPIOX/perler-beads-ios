import SwiftUI

@main
struct BeadPatternApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: { PatternDocument() }) { context in
            WorkspaceView(document: context.document)
        }
        DocumentGroup(viewing: ImportSourceDocument.self) { context in
            ImportSourceView(source: context.document)
        }
    }
}
