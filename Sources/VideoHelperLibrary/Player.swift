//
//  Player.swift
//  VideoHelperLibrary
//
//  Created by Jan Remes on 02/12/2020.
//  Copyright © 2020 Jan Remes. All rights reserved.
//

import AVKit

/// A player error
public enum VideoPlayerError: Int {
    case unknown
    case loading

    private static let Domain = "com.videoHelperLibrary"

    /// The associated error
    ///
    /// - Returns: The error
    public func error() -> NSError {
        switch self {
        case .unknown:

            return NSError(domain: type(of: self).Domain, code: self.rawValue, userInfo: [NSLocalizedDescriptionKey: "An unknown error occurred."])

        case .loading:

            return NSError(domain: type(of: self).Domain, code: self.rawValue, userInfo: [NSLocalizedDescriptionKey: "An error occurred while loading the content."])
        }
    }
}

public enum VideoPlayerState {
    case loading
    case ready
    case playing
    case paused
    case failed
}

public enum VideoPlayerFillMode {
    case fit
    case fill
}
