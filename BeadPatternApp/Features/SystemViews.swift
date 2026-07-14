import SwiftUI
import UIKit

struct CameraPicker: UIViewControllerRepresentable {
    let onImage: (Data) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    final class Coordinator: NSObject, UINavigationControllerDelegate, UIImagePickerControllerDelegate {
        let parent: CameraPicker
        init(parent: CameraPicker) { self.parent = parent }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            if let image = info[.originalImage] as? UIImage, let data = image.jpegData(compressionQuality: 0.95) {
                parent.onImage(data)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct AboutView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Label("拼豆图纸", systemImage: "square.grid.3x3.fill")
                    LabeledContent("版本", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
                }
                Section("隐私") {
                    Text("图片、图纸和编辑数据只在本机处理。App 不建立账号，不收集使用数据，不包含广告或追踪 SDK。")
                }
                Section("开源许可") {
                    Text("本项目基于 Zippland/perler-beads 的 AGPL-3.0 开源代码和色号数据重新实现，不提供任何担保。")
                    Link("查看原项目", destination: URL(string: "https://github.com/Zippland/perler-beads")!)
                    Link("查看本 App 源码", destination: URL(string: "https://github.com/GPIOX/perler-beads-ios")!)
                    Link("查看 GNU AGPL-3.0", destination: URL(string: "https://www.gnu.org/licenses/agpl-3.0.html")!)
                }
            }
            .navigationTitle("关于")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("完成") { dismiss() } }
            }
        }
    }
}
