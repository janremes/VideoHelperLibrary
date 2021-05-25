//
//  CMTime+Utilities.swift
//  VideoHelperLibrary
//
//  Created by Jan Remes on 02/12/2020.
//  Copyright © 2020 Jan Remes. All rights reserved.
//

import AVFoundation
import Foundation

extension CMTime {
    var timeInterval: TimeInterval? {
        if CMTIME_IS_INVALID(self) || CMTIME_IS_INDEFINITE(self) {
            return nil
        }

        return CMTimeGetSeconds(self)
    }
}
