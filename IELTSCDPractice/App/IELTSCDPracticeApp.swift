import AVFoundation
import SwiftData
import SwiftUI

@main
struct IELTSCDPracticeApp: App {
    let container: ModelContainer

    init() {
        Preferences.register()
        // 听力音频不受静音开关影响
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        do {
            container = try ModelContainer(for: Schema(AppSchema.models))
        } catch {
            fatalError("无法打开数据存储：\(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(container)
    }
}
