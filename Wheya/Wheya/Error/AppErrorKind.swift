//
//  AppErrorKind.swift
//  Wheya
//
//  Created by Yuliia Murakami on 9/16/25.
//

import Foundation

/// App-wide error categories that drive user-facing UI.
public enum AppErrorKind: Equatable, Sendable {
    // Storage / persistence
    case dataStoreInitFailed
    
    // Sign in / authorization
    case appleCanceled               // user dismissed Apple sheet → usually no UI
    case appleUnknown                // any non-cancel Apple sign-in failure
    case authRevoked                 // credentialState revoked/notFound/transferred

    // iCloud / CloudKit availability
    case noICloud                    // device not signed into iCloud
    case genericCloud                // restricted / couldNotDetermine / temporarilyUnavailable
    case networkOffline              // networkUnavailable/networkFailure
    case rateLimited(TimeInterval?)  // requestRateLimited/serviceUnavailable (retryAfter)
    case quotaExceeded               // user’s iCloud storage full

    // Data / records / assets
    case recordNotFound              // CKError.unknownItem etc.
    case imageEncodingFailed         // could not compress/prepare asset
    case imageTooLarge               // preflight size check failed

    // Fallback
    case generic                     // everything else
}

