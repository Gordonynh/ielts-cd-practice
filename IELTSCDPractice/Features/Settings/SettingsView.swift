import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @AppStorage(PreferenceKey.timerKind) private var timerKind = ExamTimerKind.countdown.rawValue
    @AppStorage(PreferenceKey.practiceMinutes) private var practiceMinutes = 20
    @AppStorage(PreferenceKey.fullTestMinutes) private var fullTestMinutes = 60
    @AppStorage(PreferenceKey.contrast) private var contrast = ExamContrast.standard.rawValue
    @AppStorage(PreferenceKey.textSize) private var textSize = ExamTextSize.regular.rawValue
    @AppStorage(PreferenceKey.hideTimer) private var hideTimer = false
    @AppStorage(PreferenceKey.dailyNewWords) private var dailyNewWords = 10
    @Query private var records: [PracticeRecord]
    @Query private var words: [VocabEntry]

    @State private var audio = AudioStore.shared
    @State private var confirmDeleteAudio = false
    @State private var exportDocument: BackupDocument?
    @State private var showingExporter = false
    @State private var showingImporter = false
    @State private var confirmReset = false
    @State private var message: String?

    var body: some View {
        Form {
            Section {
                Picker("计时方式", selection: $timerKind) {
                    ForEach(ExamTimerKind.allCases) { Text($0.title).tag($0.rawValue) }
                }
                if timerKind == ExamTimerKind.countdown.rawValue {
                    Stepper(value: $practiceMinutes, in: 5...60, step: 5) {
                        LabeledContent("单篇练习时长", value: "\(practiceMinutes) 分钟")
                    }
                }
                Stepper(value: $fullTestMinutes, in: 20...90, step: 5) {
                    LabeledContent("整套阅读时长", value: "\(fullTestMinutes) 分钟")
                }
                Toggle("隐藏剩余时间", isOn: $hideTimer)
            } header: {
                Text("练习计时")
            } footer: {
                Text("用于阅读与写作练习（写作 Task 1 为 20 分钟、Task 2 为 40 分钟）。完整模考始终按官方时长计时且不能暂停；练习时点按计时器可暂停。")
            }

            Section {
                Picker("对比度", selection: $contrast) {
                    ForEach(ExamContrast.allCases) { Text($0.title).tag($0.rawValue) }
                }
                Picker("字号", selection: $textSize) {
                    ForEach(ExamTextSize.allCases) { Text($0.title).tag($0.rawValue) }
                }
            } header: {
                Text("机考界面")
            } footer: {
                Text("与官方机考的 Options 菜单一致，也可以在考试中通过右上角菜单调整。")
            }

            Section("生词本") {
                Stepper(value: $dailyNewWords, in: 5...50, step: 5) {
                    LabeledContent("每次添加新词", value: "\(dailyNewWords) 个")
                }
            }

            Section {
                Button {
                    do {
                        exportDocument = BackupDocument(archive: try BackupService.makeArchive(context: modelContext))
                        showingExporter = true
                    } catch {
                        message = "导出失败：\(error.localizedDescription)"
                    }
                } label: {
                    Label("导出备份", systemImage: "square.and.arrow.up")
                }
                Button {
                    showingImporter = true
                } label: {
                    Label("从备份恢复", systemImage: "square.and.arrow.down")
                }
                Button(role: .destructive) {
                    confirmReset = true
                } label: {
                    Label("清除全部练习记录", systemImage: "trash")
                }
                .disabled(records.isEmpty)
            } header: {
                Text("数据")
            } footer: {
                Text("当前共有 \(records.count) 条练习记录、\(words.count) 个生词。数据只保存在本机，删除 App 前请先导出备份。")
            }

            if !ContentStore.shared.listeningTests.isEmpty {
                Section {
                    LabeledContent("已下载", value: "\(audio.downloadedTestCount) / \(ContentStore.shared.listeningTests.count) 套")
                    LabeledContent("占用空间", value: ByteCountFormatter.string(fromByteCount: audio.totalBytes, countStyle: .file))
                    Button("删除全部已下载音频", role: .destructive) { confirmDeleteAudio = true }
                        .disabled(audio.totalBytes == 0)
                } header: {
                    Text("听力音频")
                } footer: {
                    Text("在“剑桥真题”的试卷页中按套下载。未下载的音频会联网在线播放。")
                }
            }

            Section("关于") {
                LabeledContent("版本", value: Bundle.main.versionDescription)
                let content = ContentStore.shared
                if content.readingSets.isEmpty {
                    LabeledContent("题库", value: "未导入")
                } else {
                    LabeledContent("题库 · 阅读", value: "\(content.readingSets.count) 套 · \(content.exams.count) 篇")
                    LabeledContent("题库 · 听力", value: "\(content.listeningTests.count) 套 · \(content.listeningTests.reduce(0) { $0 + $1.sections.count }) 个 Part")
                    if let generatedAt = content.generatedAt {
                        LabeledContent("题库生成时间", value: generatedAt.formatted(date: .abbreviated, time: .omitted))
                    }
                }
                LabeledContent("离线词典", value: "ECDICT \(content.dictionaryEntryCount) 条")
                NavigationLink("开源许可与使用声明") {
                    AcknowledgementsView()
                }
            }
        }
        .navigationTitle("设置")
        .fileExporter(isPresented: $showingExporter, document: exportDocument, contentType: .json,
                      defaultFilename: "IELTS-CD-Practice-备份-\(Date().formatted(.iso8601.year().month().day()))") { result in
            if case .failure(let error) = result {
                message = "导出失败：\(error.localizedDescription)"
            } else {
                message = "备份已导出"
            }
        }
        .fileImporter(isPresented: $showingImporter, allowedContentTypes: [.json]) { result in
            restore(result)
        }
        .confirmationDialog("删除全部已下载的听力音频？", isPresented: $confirmDeleteAudio, titleVisibility: .visible) {
            Button("删除", role: .destructive) { audio.deleteAll() }
        } message: {
            Text("删除后仍可联网在线播放。")
        }
        .confirmationDialog("清除全部 \(records.count) 条练习记录？", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("清除", role: .destructive) {
                try? modelContext.delete(model: PracticeRecord.self)
                try? modelContext.delete(model: ExamDraft.self)
                try? modelContext.save()
            }
        } message: {
            Text("此操作无法撤销，生词本不受影响。")
        }
        .alert(message ?? "", isPresented: Binding(get: { message != nil }, set: { if !$0 { message = nil } })) {
            Button("好") {}
        }
    }

    private func restore(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let accessing = url.startAccessingSecurityScopedResource()
            defer { if accessing { url.stopAccessingSecurityScopedResource() } }
            let archive = try BackupService.decoder.decode(BackupArchive.self, from: Data(contentsOf: url))
            let summary = try BackupService.restore(archive, into: modelContext)
            message = "已恢复 \(summary.records) 条练习记录、\(summary.words) 个生词、\(summary.favorites) 个收藏"
        } catch {
            message = "恢复失败：\(error.localizedDescription)"
        }
    }
}

private struct AcknowledgementsView: View {
    var body: some View {
        Form {
            Section("使用声明") {
                Text("App 代码以 GPL-3.0 协议开源。题库（题目、文章、音频、图片与解析）的版权归原权利人所有，请按题库附带的授权说明使用。")
            }
            Section("开源组件") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("IELTS CD Practice").font(.headline)
                    Text("GPL-3.0 · github.com/Gordonynh/ielts-cd-practice").font(.subheadline).foregroundStyle(.secondary)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("ECDICT 英汉词典").font(.headline)
                    Text("MIT License · github.com/skywind3000/ECDICT").font(.subheadline).foregroundStyle(.secondary)
                }
            }
            Section {
                Text("机考界面依照 IELTS 官方机考（computer-delivered IELTS）的版式设计。IELTS 是其所有者的注册商标，本 App 与 IELTS 官方无关。")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("开源许可与使用声明")
    }
}

extension Bundle {
    var versionDescription: String {
        let version = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(version)（\(build)）"
    }
}
