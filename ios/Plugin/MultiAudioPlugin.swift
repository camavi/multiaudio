import Foundation
import Capacitor
import AVFoundation
import MediaPlayer

@objc(MultiAudioPlugin)
public class MultiAudioPlugin: CAPPlugin {
    
    var engine = AVAudioEngine()
    var playerNodes: [String: AVAudioPlayerNode] = [:]
    var audioFiles: [String: AVAudioFile] = [:]
    var gains: [String: AVAudioMixerNode] = [:]
    var masterId: String?
    var isPlaying = false
    var startTime: AVAudioTime?

    @objc func loadTracks(_ call: CAPPluginCall) {
        guard let tracks = call.getArray("tracks", [Dictionary<String, Any>].self) else {
            call.reject("Missing tracks array")
            return
        }
        
        do {
            // Reset previous
            engine.stop()
            playerNodes.removeAll()
            audioFiles.removeAll()
            gains.removeAll()
            masterId = nil
            
            for trackDict in tracks {
                guard let id = trackDict["id"] as? String,
                      let urlStr = trackDict["url"] as? String,
                      let url = URL(string: urlStr),
                      let volume = trackDict["volume"] as? Double else {
                    continue
                }
                
                let file = try AVAudioFile(forReading: url)
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
                    masterId = id
                }
            }
            
            try engine.start()
            call.resolve()
        } catch {
            call.reject("Error loading tracks: \(error.localizedDescription)")
        }
    }

    @objc func play(_ call: CAPPluginCall) {
        guard !isPlaying else {
            call.resolve()
            return
        }
        guard let masterId = masterId,
              let masterPlayer = playerNodes[masterId],
              let masterFile = audioFiles[masterId] else {
            call.reject("Master track not loaded")
            return
        }
        
        // Schedule all player nodes from start frame 0 with sync
        let startSampleTime = AVAudioFramePosition(0)
        let startTime = AVAudioTime(sampleTime: startSampleTime, atRate: masterFile.processingFormat.sampleRate)
        
        for (id, player) in playerNodes {
            guard let file = audioFiles[id] else { continue }
            player.scheduleFile(file, at: startTime, completionHandler: nil)
            player.play(at: startTime)
        }
        
        self.startTime = startTime
        isPlaying = true
        setupNowPlayingInfo()
        call.resolve()
    }

    @objc func pause(_ call: CAPPluginCall) {
        guard isPlaying else {
            call.resolve()
            return
        }
        for player in playerNodes.values {
            player.pause()
        }
        isPlaying = false
        call.resolve()
    }
    
    @objc func seekTo(_ call: CAPPluginCall) {
        guard let seconds = call.getDouble("seconds") else {
            call.reject("Missing seconds parameter")
            return
        }
        guard let masterId = masterId,
              let masterPlayer = playerNodes[masterId],
              let masterFile = audioFiles[masterId] else {
            call.reject("Master track not loaded")
            return
        }
        
        // Stop players
        for player in playerNodes.values {
            player.stop()
        }
        
        let sampleRate = masterFile.processingFormat.sampleRate
        let framePosition = AVAudioFramePosition(seconds * sampleRate)
        let startTime = AVAudioTime(sampleTime: framePosition, atRate: sampleRate)
        
        // Schedule from seek position
        for (id, player) in playerNodes {
            guard let file = audioFiles[id] else { continue }
            player.scheduleSegment(file, startingFrame: framePosition, frameCount: AVAudioFrameCount(file.length - framePosition), at: startTime, completionHandler: nil)
            player.play(at: startTime)
        }
        
        self.startTime = startTime
        isPlaying = true
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
        call.resolve()
    }

    @objc func getPosition(_ call: CAPPluginCall) {
        // TODO: migliorare calcolo posizione precisa
        if let node = playerNodes[masterId ?? ""],
           let lastRender = node.lastRenderTime,
           let playerTime = node.playerTime(forNodeTime: lastRender),
           let file = audioFiles[masterId ?? ""] {
            let currentTime = Double(playerTime.sampleTime) / playerTime.sampleRate
            let duration = Double(file.length) / file.processingFormat.sampleRate
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
    
    func setupNowPlayingInfo(currentTime: Double = 0) {
        guard let masterId = masterId,
              let file = audioFiles[masterId] else { return }
        
        let infoCenter = MPNowPlayingInfoCenter.default()
        var nowPlayingInfo = [String: Any]()
        
        nowPlayingInfo[MPMediaItemPropertyTitle] = "Traccia Master"
        nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = Double(file.length) / file.processingFormat.sampleRate
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = currentTime
        
        // TODO: impostare immagine/artwork
        
        infoCenter.nowPlayingInfo = nowPlayingInfo
        
        // Abilita comandi remoti (play, pause, seek)
        let commandCenter = MPRemoteCommandCenter.shared()
        commandCenter.playCommand.isEnabled = true
        commandCenter.pauseCommand.isEnabled = true
        // Implementa i callback play/pause se vuoi
    }
}
