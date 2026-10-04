import AVFoundation
import Combine
import SwiftUI

/// 口语话题行：话题名、类别、题目数与考频。
struct SpeakingTopicRow: View {
    let topic: SpeakingBank.Topic

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(topic.name).font(.headline)
                HStack(spacing: 6) {
                    if !topic.category.isEmpty { TagLabel(text: topic.category) }
                    if !topic.questions.isEmpty {
                        Text("\(topic.questions.count) 题").font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(topic.recentExamCount.formatted())
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                Text("考频").font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

struct SpeakingTopicView: View {
    let topic: SpeakingBank.Topic
    @State private var player = SpeakingAudio.shared

    private var cueCards: [SpeakingBank.Question] { topic.questions.filter(\.isCueCard) }
    private var others: [SpeakingBank.Question] { topic.questions.filter { !$0.isCueCard } }

    var body: some View {
        List {
            Section {
                HStack {
                    Text("考官口音")
                    Spacer()
                    Picker("口音", selection: $player.accent) {
                        ForEach(["英音", "美音", "印度音"], id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 260)
                }
            } footer: {
                Text("点 ▶︎ 听考官提问，再点麦克风录下自己的回答，可以和参考回答对比。")
            }
            ForEach(cueCards) { card in
                Section("Part 2 题卡") {
                    CueCardView(question: card, player: player)
                }
            }
            if !others.isEmpty {
                ForEach(Array(others.enumerated()), id: \.element.id) { index, question in
                    Section(sectionTitle(question, index: index)) {
                        SpeakingQuestionRow(question: question, player: player)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(topic.name)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { player.stopAll() }
    }

    private func sectionTitle(_ question: SpeakingBank.Question, index: Int) -> String {
        let partNumber = question.part ?? topic.part
        let sameParts = others.prefix(index + 1).filter { ($0.part ?? topic.part) == partNumber }.count
        return "Part \(partNumber) · Question \(sameParts)"
    }
}

/// Part 2 题卡：1 分钟准备 + 2 分钟陈述，可录音。
private struct CueCardView: View {
    let question: SpeakingBank.Question
    let player: SpeakingAudio
    @State private var phase: Phase = .idle
    @State private var remaining: Double = 60
    @State private var showSample = false
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    enum Phase { case idle, preparing, speaking, done }

    private var lines: [String] {
        question.text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                if let first = lines.first {
                    Text(first).font(.title3.weight(.semibold))
                }
                ForEach(Array(lines.dropFirst().enumerated()), id: \.offset) { _, line in
                    Text(line.hasSuffix(":") || line.lowercased().hasPrefix("and ") ? line : (line.lowercased().hasPrefix("you should") ? line : "•  " + line))
                        .foregroundStyle(line.lowercased().hasPrefix("you should") ? .secondary : .primary)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color(.separator)))

            HStack(spacing: 12) {
                switch phase {
                case .idle, .done:
                    Button {
                        phase = .preparing
                        remaining = 60
                    } label: {
                        Label(phase == .done ? "再练一次" : "开始：准备 1 分钟", systemImage: "timer")
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                case .preparing:
                    Label("准备中 \(remaining.clockString)", systemImage: "pencil.and.list.clipboard")
                        .font(.headline.monospacedDigit())
                    Button("开始陈述") { startSpeaking() }
                        .buttonStyle(.borderedProminent)
                        .tint(.accentColor)
                case .speaking:
                    Label("陈述中 \(remaining.clockString)", systemImage: "mic.fill")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(.red)
                    Button("结束") { finish() }
                        .buttonStyle(.bordered)
                }
                if player.hasRecording(question.id) && phase != .speaking {
                    Button {
                        player.playRecording(question.id)
                    } label: {
                        Label(player.playingID == "rec-\(question.id)" ? "停止" : "听我的回答", systemImage: "waveform")
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                if !question.sample.isEmpty {
                    Button(showSample ? "收起参考回答" : "参考回答") {
                        withAnimation { showSample.toggle() }
                    }
                    .buttonStyle(.borderless)
                }
            }
            if showSample {
                VStack(alignment: .leading, spacing: 4) {
                    Text(question.sample)
                    Text("参考回答节选").font(.caption).foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(.vertical, 6)
        .onReceive(ticker) { _ in
            guard phase == .preparing || phase == .speaking else { return }
            remaining -= 1
            if remaining <= 0 {
                if phase == .preparing { startSpeaking() } else { finish() }
            }
        }
    }

    private func startSpeaking() {
        phase = .speaking
        remaining = 120
        if player.recordingID != question.id { player.toggleRecording(question.id) }
    }

    private func finish() {
        phase = .done
        if player.recordingID == question.id { player.toggleRecording(question.id) }
    }
}

private struct SpeakingQuestionRow: View {
    let question: SpeakingBank.Question
    let player: SpeakingAudio
    @State private var showSample = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                if !question.audio.isEmpty {
                    Button {
                        player.playQuestion(question)
                    } label: {
                        Image(systemName: player.playingID == question.id ? "stop.circle.fill" : "play.circle.fill")
                            .font(.system(size: 30))
                    }
                    .buttonStyle(.borderless)
                    .accessibilityLabel("播放考官提问")
                }
                Text(question.text)
                    .font(.title3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 12) {
                Button {
                    player.toggleRecording(question.id)
                } label: {
                    Label(player.recordingID == question.id ? "停止录音 \(player.recordingTime.clockString)" : "录音回答",
                          systemImage: player.recordingID == question.id ? "stop.fill" : "mic.fill")
                }
                .buttonStyle(.borderedProminent)
                .tint(player.recordingID == question.id ? .red : .accentColor)
                if player.hasRecording(question.id) {
                    Button {
                        player.playRecording(question.id)
                    } label: {
                        Label(player.playingID == "rec-\(question.id)" ? "停止" : "听我的回答",
                              systemImage: player.playingID == "rec-\(question.id)" ? "stop.fill" : "waveform")
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
                if !question.sample.isEmpty {
                    Button(showSample ? "收起参考回答" : "参考回答") {
                        withAnimation { showSample.toggle() }
                    }
                    .buttonStyle(.borderless)
                }
            }
            if showSample {
                VStack(alignment: .leading, spacing: 4) {
                    Text(question.sample)
                    Text("参考回答节选").font(.caption).foregroundStyle(.secondary)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(.vertical, 6)
    }
}

struct ExaminerScriptView: View {
    let lines: [SpeakingBank.ExaminerLine]
    @State private var player = SpeakingAudio.shared

    var body: some View {
        List(Array(lines.enumerated()), id: \.offset) { index, line in
            HStack(alignment: .top, spacing: 12) {
                Button {
                    player.play(url: line.audio, id: "examiner-\(index)")
                } label: {
                    Image(systemName: player.playingID == "examiner-\(index)" ? "stop.circle.fill" : "play.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                Text(line.text)
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("考官用语")
        .onDisappear { player.stopAll() }
    }
}

/// 口语音频：在线播放考官提问，录制与回放自己的回答。
@MainActor
@Observable
final class SpeakingAudio: NSObject, AVAudioRecorderDelegate {
    static let shared = SpeakingAudio()

    var accent = "英音"
    private(set) var playingID: String?
    private(set) var recordingID: String?
    private(set) var recordingTime: Double = 0
    private(set) var revision = 0

    private var player: AVPlayer?
    private var endObserver: NSObjectProtocol?
    private var recorder: AVAudioRecorder?
    private var timer: Timer?

    nonisolated static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("SpeakingRecordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func recordingURL(_ id: String) -> URL {
        Self.directory.appendingPathComponent("\(id).m4a")
    }

    /// 已录音的题目数量
    nonisolated static func recordedCount() -> Int {
        ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).filter { $0.hasSuffix(".m4a") }.count
    }

    func hasRecording(_ id: String) -> Bool {
        _ = revision
        return FileManager.default.fileExists(atPath: recordingURL(id).path)
    }

    func playQuestion(_ question: SpeakingBank.Question) {
        let audio = question.audio.first { $0.accent == accent } ?? question.audio.first
        guard let audio else { return }
        play(url: audio.url, id: question.id)
    }

    func play(url: String, id: String) {
        if playingID == id {
            stopPlayback()
            return
        }
        guard let target = URL(string: url) else { return }
        play(target, id: id)
    }

    func playRecording(_ id: String) {
        let key = "rec-\(id)"
        if playingID == key {
            stopPlayback()
            return
        }
        play(recordingURL(id), id: key)
    }

    private func play(_ url: URL, id: String) {
        stopRecording()
        stopPlayback()
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
        let item = AVPlayerItem(url: url)
        player = AVPlayer(playerItem: item)
        playingID = id
        endObserver = NotificationCenter.default.addObserver(forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopPlayback() }
        }
        player?.play()
    }

    private func stopPlayback() {
        player?.pause()
        player = nil
        playingID = nil
        if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
        endObserver = nil
    }

    func toggleRecording(_ id: String) {
        if recordingID == id {
            stopRecording()
            return
        }
        stopPlayback()
        stopRecording()
        AVAudioApplication.requestRecordPermission { granted in
            Task { @MainActor in
                guard granted else { return }
                self.startRecording(id)
            }
        }
    }

    private func startRecording(_ id: String) {
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
        try? session.setActive(true)
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue,
        ]
        guard let recorder = try? AVAudioRecorder(url: recordingURL(id), settings: settings) else { return }
        recorder.delegate = self
        recorder.record()
        self.recorder = recorder
        recordingID = id
        recordingTime = 0
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let recorder = self.recorder else { return }
                self.recordingTime = recorder.currentTime
            }
        }
    }

    private func stopRecording() {
        guard recorder != nil else { return }
        recorder?.stop()
        recorder = nil
        recordingID = nil
        timer?.invalidate()
        timer = nil
        revision += 1
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio)
    }

    func stopAll() {
        stopPlayback()
        stopRecording()
    }
}
