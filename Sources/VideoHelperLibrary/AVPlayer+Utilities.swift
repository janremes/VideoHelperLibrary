//
//  AVPlayer+Utilities.swift
//  VideoHelperLibrary
//
//  Created by Jan Remes on 02/12/2020.
//  Copyright © 2020 Jan Remes. All rights reserved.
//

import AVFoundation
import Foundation

extension AVPlayer {
    var errorForPlayerOrItem: NSError? {
        // First try to return the current item's error

        if let error = self.currentItem?.error {
            // If current item's error has an underlying error, return that

            if let underlyingError = (error as NSError).userInfo[NSUnderlyingErrorKey] as? NSError {
                return underlyingError
            } else {
                return error as NSError?
            }
        }

        // Otherwise, try to return the player error

        if let error = self.error {
            return error as NSError?
        }

        // An error cannot be found

        return nil
    }
}

extension AVPlayer.Status {
    var printValue: String {
        switch self {
        case .failed:
            return "failed"
        case .unknown:
            return "unknown"
        case .readyToPlay:
            return "readyToPlay"
        @unknown default:
            return "default"
        }
    }
}

extension AVPlayerItem.Status {
    var printValue: String {
        switch self {
        case .failed:
            return "failed"
        case .unknown:
            return "unknown"
        case .readyToPlay:
            return "readyToPlay"
        @unknown default:
            return "default"
        }
    }
}
