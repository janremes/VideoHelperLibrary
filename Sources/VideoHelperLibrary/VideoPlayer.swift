//
//  VideoPlayer.swift
//  VideoHelperLibrary
//
//  Created by Jan Remes on 02/12/2020.
//  Copyright © 2020 Jan Remes. All rights reserved.
//
// swiftlint:disable force_cast

import AVFoundation
import AVKit
import Combine
import Foundation
import UIKit

private final class VideoPlayerView: UIView {
    var playerLayer: AVPlayerLayer {
        return self.layer as! AVPlayerLayer
    }

    override class var layerClass: AnyClass {
        return AVPlayerLayer.self
    }

    func configureForPlayer(player: AVPlayer) {
        (self.layer as! AVPlayerLayer).player = player
    }
}

/// A VideoPlayer is used to play regular videos.
public final class VideoPlayer: NSObject {
    public enum K {
        public static let TimeUpdateInterval: TimeInterval = 0.1
    }

    // MARK: - Private Properties

    private var player = AVQueuePlayer()
    private var regularPlayerView: VideoPlayerView
    private var playerLayer: AVPlayerLayer {
        return self.regularPlayerView.playerLayer
    }

    private var playerLooper: AVPlayerLooper?

    private var seekTolerance: CMTime?
    private var seekTarget = CMTime.invalid
    private var isSeekInProgress: Bool = false

    private var rateObserver: NSKeyValueObservation?
    private var statusObserver: NSKeyValueObservation?
    private var playbackLikelyToKeepUpObserver: NSKeyValueObservation?
    private var loadedTimeRangesObserver: NSKeyValueObservation?
    private var playerTimeObserver: Any?
    private var isSeeking: Bool = false

    // MARK: Config

    /// Will play video right after it's loaded
    public var isAutoplay = false

    /// Loop video when it ends.
    public var isLooping = false

    // MARK: - Lifecycle

    override public init() {
        self.regularPlayerView = VideoPlayerView(frame: .zero)
        super.init()
    }

    deinit {
        self.removePlayerObservers()
    }

    // MARK: - Public API

    public func set(_ url: URL) {
        let asset = AVURLAsset(url: url)
        self.set(asset)
    }

    /// Sets an AVAsset on the player.
    ///
    /// - Parameter asset: The AVAsset
    public func set(_ asset: AVAsset) {
        let playerItem = AVPlayerItem(asset: asset)
        self.set(playerItem: playerItem)
    }

    public func set(playerItem: AVPlayerItem) {
        self.player = AVQueuePlayer(items: [playerItem])

        self.regularPlayerView.configureForPlayer(player: self.player)
        self.addPlayerObservers()
        self.addPlayerItemObservers(toPlayerItem: playerItem)

        if isLooping {
            playerLooper = AVPlayerLooper(player: player, templateItem: playerItem)
        } else {
            self.player.actionAtItemEnd = .pause
        }
    }

    public var view: UIView {
        return self.regularPlayerView
    }

    // MARK: - Player Publishers

    public let playerStatePublisher = CurrentValueSubject<VideoPlayerState, Never>(.loading)
    public let playerProgressPublisher = CurrentValueSubject<TimeInterval, Never>(0)
    public let playerBufferedTimePublisher = CurrentValueSubject<TimeInterval, Never>(0)
    public let playerRatePublisher = CurrentValueSubject<Float, Never>(0)

    public private(set) var state: VideoPlayerState = .ready {
        didSet {
            playerStatePublisher.send(state)
        }
    }

    public var duration: TimeInterval {
        return self.player.currentItem?.duration.timeInterval ?? 0
    }

    public private(set) var time: TimeInterval = 0 {
        didSet {
            guard !isSeeking else { return }
            if duration > 0 {
                playerProgressPublisher.send(time / duration)
            }
        }
    }

    public private(set) var bufferedTime: TimeInterval = 0 {
        didSet {
            playerBufferedTimePublisher.send(bufferedTime)
        }
    }

    public var isPlaying: Bool {
        return self.player.rate > 0
    }

    public var isMuted: Bool = false {
        didSet {
            self.player.volume = isMuted ? 0.0 : 1.0
        }
    }

    public var isEnded: Bool {
        return abs(duration - time) < 1
    }

    public var error: NSError? {
        return self.player.errorForPlayerOrItem
    }

    public func seek(to time: TimeInterval) {
        let playerTimescale = self.player.currentItem?.asset.duration.timescale ?? Int32(NSEC_PER_SEC)
        let cmTime = CMTime(seconds: time, preferredTimescale: playerTimescale)
        self.smoothSeek(to: cmTime)
    }

    public func skipForward(by interval: TimeInterval) {
        let targetTime = min(time + interval, duration)
        seek(to: targetTime)
    }

    public func skipBackward(by interval: TimeInterval) {
        let targetTime = max(time - interval, 0)
        seek(to: targetTime)
    }

    public func play() {
        self.player.play()
        self.state = .playing
    }

    public func pause() {
        self.player.pause()
        self.state = .paused
    }

    // MARK: - Setup

    public var automaticallyWaitsToMinimizeStalling: Bool {
        get {
            return self.player.automaticallyWaitsToMinimizeStalling
        }
        set {
            self.player.automaticallyWaitsToMinimizeStalling = newValue
        }
    }

    public var supportsAirplay: Bool {
        get {
            return player.usesExternalPlaybackWhileExternalScreenIsActive
        }

        set {
            player.usesExternalPlaybackWhileExternalScreenIsActive = newValue
        }
    }

    // MARK: - Smooth Seeking

    // Note: Smooth seeking follows the guide from Apple Technical Q&A: https://developer.apple.com/library/archive/qa/qa1820/_index.html
    // Update the seek target and begin seeking if there is no seek currently in progress.
    private func smoothSeek(to cmTime: CMTime) {
        self.seekTarget = cmTime

        // guard self.isSeekInProgress == false else { return }
        self.seekToTarget()
    }

    // Unconditionally seek to the current seek target.
    private func seekToTarget() {
        guard self.player.status != .unknown else { return }

        self.isSeekInProgress = true

        assert(CMTIME_IS_VALID(self.seekTarget))
        let inProgressSeekTarget = self.seekTarget
        self.isSeeking = true

        let completion: (Bool) -> Void = { [weak self] _ in
            guard let self = self else { return }

            print("seeking to \(self.seekTarget.seconds) finished")
            self.isSeeking = false
            self.isSeekInProgress = false
        }

        if let tolerance = self.seekTolerance {
            self.player.seek(
                to: inProgressSeekTarget,
                toleranceBefore: tolerance,
                toleranceAfter: tolerance,
                completionHandler: completion
            )
        } else {
            self.player.seek(to: inProgressSeekTarget, completionHandler: completion)
        }
    }

    // MARK: - Observers

    private func addPlayerItemObservers(toPlayerItem playerItem: AVPlayerItem) {
        playbackLikelyToKeepUpObserver = playerItem.observe(\.isPlaybackLikelyToKeepUp, options: [.initial, .new], changeHandler: { [weak self] item, change in
            if let playbackLikelyToKeepUp = change.newValue {
                self?.playerItemPlaybackLikelyToKeepUpDidChange(playbackLikelyToKeepUp: playbackLikelyToKeepUp)
            }
        })

        loadedTimeRangesObserver = playerItem.observe(\.loadedTimeRanges, options: [.initial, .new], changeHandler: { [weak self] item, change in
            if let loadedTimeRanges = change.newValue {
                self?.playerItemLoadedTimeRangesDidChange(loadedTimeRanges: loadedTimeRanges)
            }
        })
    }

    private func addPlayerObservers() {

        statusObserver = player.currentItem?.observe(\.status, options: [.initial, .new], changeHandler: { [weak self] item, change in
            print("Updated video player status \(item.status.printValue)")
            self?.playerStatusDidChange(status: item.status)
        })

        self.rateObserver = player.observe(\AVQueuePlayer.rate, options: [.initial, .new], changeHandler: { [weak self] player, change in
            if let rate = change.newValue {
                self?.playerRateDidChange(rate: rate)
            }
        })

        let interval = CMTimeMakeWithSeconds(K.TimeUpdateInterval, preferredTimescale: Int32(NSEC_PER_SEC))

        self.playerTimeObserver = self.player.addPeriodicTimeObserver(forInterval: interval, queue: DispatchQueue.main, using: { [weak self] cmTime in
            guard let self = self, let time = cmTime.timeInterval else {
                return
            }

            self.time = time
        })
    }

    private func removePlayerObservers() {
        if let playerTimeObserver = self.playerTimeObserver {
            self.player.removeTimeObserver(playerTimeObserver)
            self.playerTimeObserver = nil
        }
    }

    // MARK: Observation Helpers

    private func playerStatusDidChange(status: AVPlayerItem.Status) {
        switch status {
        case .unknown:

            self.state = .loading

        case .readyToPlay:

            self.state = .ready

            // If we tried to seek before the video was ready to play, resume seeking now.
            if self.isEnded {
                break
            } else if self.isSeekInProgress {
                self.seekToTarget()
            } else if isAutoplay {
                self.play()
                self.state = .playing

                if isMuted {
                    self.player.volume = 0.0
                }
            }

        case .failed:

            self.state = .failed

            print("Video player failed: \(String(describing: self.player.currentItem?.error?.localizedDescription))")

        @unknown default:

            self.state = .failed
        }
    }

    private func playerRateDidChange(rate: Float) {
        self.playerRatePublisher.send(rate)
    }

    private func playerItemPlaybackLikelyToKeepUpDidChange(playbackLikelyToKeepUp: Bool) {
        // let state: VideoPlayerState = playbackLikelyToKeepUp ? .ready : .loading
        // self.state = state
    }

    private func playerItemLoadedTimeRangesDidChange(loadedTimeRanges: [NSValue]) {
        guard let bufferedCMTime = loadedTimeRanges.first?.timeRangeValue.end, let bufferedTime = bufferedCMTime.timeInterval else {
            return
        }

        self.bufferedTime = bufferedTime
    }

    private lazy var _pictureInPictureController: AVPictureInPictureController? = {
        AVPictureInPictureController(playerLayer: self.regularPlayerView.playerLayer)
    }()
}

public extension VideoPlayer {
    var isAirPlayEnabled: Bool {
        get {
            return self.player.allowsExternalPlayback
        }
        set {
            return self.player.allowsExternalPlayback = newValue
        }
    }
}

// MARK: PictureInPicture

extension VideoPlayer {
    var pictureInPictureController: AVPictureInPictureController? {
        return self._pictureInPictureController
    }
}

// MARK: Volume

public extension VideoPlayer {
    var volume: Float {
        get {
            return self.player.volume
        }
        set {
            self.player.volume = newValue
        }
    }
}

// MARK: Fill Mode

public extension VideoPlayer {
    var fillMode: VideoPlayerFillMode {
        get {
            let gravity = (self.view.layer as! AVPlayerLayer).videoGravity
            return gravity == .resizeAspect ? .fit : .fill
        }
        set {
            let gravity: AVLayerVideoGravity

            switch newValue {
            case .fit:

                gravity = .resizeAspect

            case .fill:

                gravity = .resizeAspectFill
            }

            (self.view.layer as! AVPlayerLayer).videoGravity = gravity
        }
    }
}
