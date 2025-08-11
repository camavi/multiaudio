import Foundation
import Capacitor
import AVFoundation
import MediaPlayer
import UIKit

@objc(MultiAudioPlugin)
public class MultiAudioPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "MultiAudioPlugin"
    public let jsName = "MultiAudio"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "echo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "loadTracks", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "play", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "pause", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "seekTo", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "setVolume", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "getPosition", returnType: CAPPluginReturnPromise)
    ]
    private let implementation = MultiAudio()

    @objc func echo(_ call: CAPPluginCall) {
        let value = call.getString("value") ?? ""
        call.resolve([
            "value": implementation.echo(value)
        ])
    }

    // Audio engine state
    var engine = AVAudioEngine()
    var playerNodes: [String: AVAudioPlayerNode] = [:]
    var audioFiles: [String: AVAudioFile] = [:]
    var gains: [String: AVAudioMixerNode] = [:]
    var masterId: String?
    var isPlaying = false
    var startTime: AVAudioTime?
    var positionTimer: Timer?
    private var masterStartTime: Double?

    // Avoid adding targets multiple times
    private var remoteCommandsAdded = false

    // Called when plugin is loaded - register remote controls early
    public override func load() {
        super.load()
        setupRemoteTransportControls()
    }

    @objc func loadTracks(_ call: CAPPluginCall) {
        guard let tracks = call.getArray("tracks", JSObject.self) else {
            call.reject("Missing tracks array")
            return
        }
        print("[MultiAudio] ✅ loadTracks start iOS. Total tracks: \(tracks.count)")

        do {
            // Reset previous state
            engine.stop()
            playerNodes.removeAll()
            audioFiles.removeAll()
            gains.removeAll()
            masterId = nil

            for trackDict in tracks {
                guard let urlStr = trackDict["url"] as? String, let remoteURL = URL(string: urlStr) else {
                    continue
                }
                let semaphore = DispatchSemaphore(value: 0)
                var localFileURL: URL?
                var downloadError: Error?

                guard let id = trackDict["id"] as? String,
                      let url = URL(string: urlStr),
                      let volume = trackDict["volume"] as? Double else {
                    print("[MultiAudio] ⚠️ Skipping track: missing id/url/volume")
                    continue
                }

                print("[MultiAudio] 🎵 Loading track \(id) from \(urlStr)")

                func downloadFile(from url: URL, completion: @escaping (URL?, Error?) -> Void) {
                    let session = URLSession.shared
                    let task = session.downloadTask(with: url) { localURL, response, error in
                        guard let localURL = localURL, error == nil else {
                            completion(nil, error)
                            return
                        }
                        completion(localURL, nil)
                    }
                    task.resume()
                }

                downloadFile(from: remoteURL) { url, error in
                    localFileURL = url
                    downloadError = error
                    semaphore.signal()
                }

                semaphore.wait()

                if let error = downloadError {
                    print("[MultiAudio] ❌ Error downloading track \(id): \(error.localizedDescription)")
                    continue
                }

                guard let localURL = localFileURL else {
                    print("[MultiAudio] ❌ No local file URL for track \(id)")
                    continue
                }

                let file = try AVAudioFile(forReading: localURL)
                audioFiles[id] = file

                let player = AVAudioPlayerNode()
                playerNodes[id] = player

                let gainNode = AVAudioMixerNode()
                gains[id] = gainNode

                engine.attach(player)
                engine.attach(gainNode)

                engine.connect(player, to: gainNode, format: file.processingFormat)
                engine.connect(gainNode, to: engine.mainMixerNode, format: file.processingFormat)
                gainNode.volume = Float(volume)

                if let isMaster = trackDict["isMaster"] as? Bool, isMaster {
                    print("[MultiAudio] 🎯 \(id) set as master track")
                    masterId = id
                }
            }

            try engine.start()
            print("[MultiAudio] ✅ loadTracks completed iOS")
            call.resolve([
                "success": true
            ])
        } catch {
            print("[MultiAudio] ❌ Error loading tracks: \(error.localizedDescription)")
            call.reject("Error loading tracks: \(error.localizedDescription)")
        }
    }

    @objc func play(_ call: CAPPluginCall) {
        guard !isPlaying else {
            print("[MultiAudio] ⏯ Already playing")
            call.resolve()
            return
        }
        guard let masterId = masterId,
              let masterFile = audioFiles[masterId] else {
            print("[MultiAudio] ❌ Master track not loaded")
            call.reject("Master track not loaded")
            return
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.allowBluetooth, .allowAirPlay])
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[MultiAudio] ❌ Errore AVAudioSession: \(error)")
        }

        // schedule from start
        let startSampleTime = AVAudioFramePosition(0)
        let startTime = AVAudioTime(sampleTime: startSampleTime, atRate: masterFile.processingFormat.sampleRate)

        for (id, player) in playerNodes {
            guard let file = audioFiles[id] else { continue }
            player.stop()
            player.scheduleFile(file, at: startTime, completionHandler: nil)
            player.play(at: startTime)
            print("[MultiAudio] ▶️ Playing track \(id) from start")
        }

        if let node = playerNodes[masterId ?? ""],
            let lastRender = node.lastRenderTime,
            let playerTime = node.playerTime(forNodeTime: lastRender) {
            
                // Salva il tempo assoluto al momento dell'avvio
                masterStartTime = Double(playerTime.sampleTime) / playerTime.sampleRate
                print("🎬 [DEBUG] Avvio playback - startTime: \(masterStartTime!) sec")
            } else {
                masterStartTime = 0
            }

        self.startTime = startTime
        isPlaying = true
        setupNowPlayingInfo()
        startPositionTimer()
        call.resolve()
    }

    @objc func pause(_ call: CAPPluginCall) {
        guard isPlaying else {
            print("[MultiAudio] ⏸ Already paused")
            call.resolve()
            return
        }
        for player in playerNodes.values {
            player.pause()
        }
        isPlaying = false
        print("[MultiAudio] ⏸ Paused all tracks")
        positionTimer?.invalidate()
        setupNowPlayingInfo(currentTime: getMasterCurrentTime())
        call.resolve()
    }

    @objc func seekTo(_ call: CAPPluginCall) {
        guard let seconds = call.getDouble("seconds") else {
            call.reject("Missing seconds parameter")
            return
        }
        guard let masterId = masterId,
              let masterFile = audioFiles[masterId] else {
            call.reject("Master track not loaded")
            return
        }

        // preserve current play state
        let currentlyPlaying = isPlaying

        for player in playerNodes.values {
            player.stop()
        }

        let sampleRate = masterFile.processingFormat.sampleRate
        let framePosition = AVAudioFramePosition(seconds * sampleRate)
        let startTime = AVAudioTime(sampleTime: framePosition, atRate: sampleRate)

        for (id, player) in playerNodes {
            guard let file = audioFiles[id] else { continue }
            player.scheduleSegment(file, startingFrame: framePosition,
                                   frameCount: AVAudioFrameCount(file.length - framePosition),
                                   at: startTime, completionHandler: nil)
            if currentlyPlaying {
                player.play(at: startTime)
            }
            print("[MultiAudio] ⏩ Seeking track \(id) to \(seconds) sec (via JS call)")
        }

        self.startTime = startTime
        isPlaying = currentlyPlaying
        setupNowPlayingInfo(currentTime: seconds)
        call.resolve()
    }

    @objc func setVolume(_ call: CAPPluginCall) {
        guard let id = call.getString("id"),
              let volume = call.getDouble("volume"),
              let gainNode = gains[id] else {
            call.reject("Invalid id or volume")
            return
        }
        gainNode.volume = Float(volume)
        print("[MultiAudio] 🔊 Volume for \(id) set to \(volume)")
        call.resolve()
    }

    @objc func getPosition(_ call: CAPPluginCall) {
        if let node = playerNodes[masterId ?? ""],
           let lastRender = node.lastRenderTime,
           let playerTime = node.playerTime(forNodeTime: lastRender),
           let file = audioFiles[masterId ?? ""] {
            let currentTime = Double(playerTime.sampleTime) / playerTime.sampleRate
            let duration = Double(file.length) / file.processingFormat.sampleRate
            print("[MultiAudio] ⏱ Position: \(currentTime) / \(duration)")
            call.resolve([
                "currentTime": currentTime,
                "duration": duration
            ])
        } else {
            call.resolve([
                "currentTime": 0,
                "duration": 0
            ])
        }
    }

    // MARK: - Now Playing Info

    func setupNowPlayingInfo(currentTime: Double = 0) {
        guard let masterId = masterId,
              let file = audioFiles[masterId] else {
            print("[MultiAudio] ❗ setupNowPlayingInfo skipped: no master file")
            return
        }

        let duration = Double(file.length) / file.processingFormat.sampleRate

        var nowPlayingInfo: [String: Any] = [
            MPMediaItemPropertyTitle: "Journey Sound",
            MPMediaItemPropertyArtist: "Prova audioLibro",
            MPMediaItemPropertyPlaybackDuration: duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: currentTime,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0
        ]

        if let image = UIImage(named: "cover") {
            let artwork = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
            nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork
        }

        MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo

        // register commands (only once)
        setupRemoteTransportControls()

        // debug print
        if let info = MPNowPlayingInfoCenter.default().nowPlayingInfo {
            print("[MultiAudio] NowPlayingInfo set: duration=\(duration) elapsed=\(currentTime) rate=\(isPlaying ? 1.0 : 0.0) keys=\(info.keys)")
        }
    }

    func setupRemoteTransportControls() {
        let commandCenter = MPRemoteCommandCenter.shared()

        // avoid double registration
        if remoteCommandsAdded {
            // Debug: show status
            print("[MultiAudio] Remote commands already added.")
            print("[MultiAudio] playCommand enabled? \(commandCenter.playCommand.isEnabled)")
            print("[MultiAudio] pauseCommand enabled? \(commandCenter.pauseCommand.isEnabled)")
            print("[MultiAudio] changePlaybackPositionCommand enabled? \(commandCenter.changePlaybackPositionCommand.isEnabled)")
            return
        }

        // Play
        commandCenter.playCommand.isEnabled = true
        commandCenter.playCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.playFromRemote()
            return .success
        }

        // Pause
        commandCenter.pauseCommand.isEnabled = true
        commandCenter.pauseCommand.addTarget { [weak self] _ in
            guard let self = self else { return .commandFailed }
            self.pauseFromRemote()
            return .success
        }

        // Seek / Scrubbing (Control Center / Lock Screen timeline)
        commandCenter.changePlaybackPositionCommand.isEnabled = true
        commandCenter.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let self = self,
                  let positionEvent = event as? MPChangePlaybackPositionCommandEvent else {
                return .commandFailed
            }
            let newPosition = positionEvent.positionTime
            print("[MultiAudio] Remote request: seek to \(newPosition)")
            self.seekToPosition(newPosition)
            return .success
        }

        remoteCommandsAdded = true

        // Debug print
        print("[MultiAudio] Remote commands added. changePlaybackPositionCommand.isEnabled = \(commandCenter.changePlaybackPositionCommand.isEnabled)")
    }

    private func playFromRemote() {
        // Resume playback (call play without scheduling if already scheduled)
        for (id, player) in playerNodes {
            guard let _ = audioFiles[id] else { continue }
            // if node is already scheduled but paused, a plain play() resumes.
            player.play()
        }
        isPlaying = true
        setupNowPlayingInfo(currentTime: getMasterCurrentTime())
        startPositionTimer()
    }

    private func pauseFromRemote() {
        for player in playerNodes.values {
            player.pause()
        }
        isPlaying = false
        positionTimer?.invalidate()
        setupNowPlayingInfo(currentTime: getMasterCurrentTime())
    }

    private func getMasterCurrentTime() -> Double {
        if let node = playerNodes[masterId ?? ""],
        let lastRender = node.lastRenderTime,
        let playerTime = node.playerTime(forNodeTime: lastRender) {
            
            let absoluteTime = Double(playerTime.sampleTime) / playerTime.sampleRate
            
            // Calcola il tempo relativo
            if let startTime = masterStartTime {
                let relative = absoluteTime - startTime
                return max(0, relative) // Evita valori negativi
            } else {
                return 0
            }
        }
        return 0
    }

    func startPositionTimer() {
        positionTimer?.invalidate()
        // Use main run loop to ensure MPNowPlayingInfo updates occur on main thread
        DispatchQueue.main.async {
            self.positionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
                guard let self = self else { return }
                let currentTime = self.getMasterCurrentTime()
                
                var nowPlayingInfo = MPNowPlayingInfoCenter.default().nowPlayingInfo ?? [:]
                nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
                nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = self.isPlaying ? 1.0 : 0.0
                MPNowPlayingInfoCenter.default().nowPlayingInfo = nowPlayingInfo
            }
            RunLoop.main.add(self.positionTimer!, forMode: .common)
        }
    }

    func seekToPosition(_ seconds: Double) {
        guard let masterId = masterId,
              let masterFile = audioFiles[masterId] else {
            print("[MultiAudio] ❌ seekToPosition: master missing")
            return
        }

        // preserve play state
        let currentlyPlaying = isPlaying

        for player in playerNodes.values {
            player.stop()
        }

        let sampleRate = masterFile.processingFormat.sampleRate
        let framePosition = AVAudioFramePosition(seconds * sampleRate)
        let startTime = AVAudioTime(sampleTime: framePosition, atRate: sampleRate)

        for (id, player) in playerNodes {
            guard let file = audioFiles[id] else { continue }
            player.scheduleSegment(file, startingFrame: framePosition,
                                   frameCount: AVAudioFrameCount(file.length - framePosition),
                                   at: startTime, completionHandler: nil)
            if currentlyPlaying {
                player.play(at: startTime)
            }
            print("[MultiAudio] ⏩ seekToPosition scheduled \(id) -> \(seconds)s")
        }

        self.startTime = startTime
        self.isPlaying = currentlyPlaying
        setupNowPlayingInfo(currentTime: seconds)
    }
}
