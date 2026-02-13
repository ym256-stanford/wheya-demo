//
//  LocationSharingOption.swift
//  Wheya
//
//  Created by Yuliia Murakami on 7/8/25.
//

/// 位置共有の設定オプションを表す列挙型
enum LocationSharingOption: Identifiable, Hashable {
    case preset(Int)      // 例: .preset(10)
    case custom(Int)

    var id: String {
        switch self {
        case .preset(let m): return "preset-\(m)"
        case .custom(let m): return "custom-\(m)"
        }
    }

    var minutes: Int {
        switch self {
        case .preset(let m), .custom(let m): return m
        }
    }

    var displayText: String {
        "\(minutes) min before"
    }

    static let presets: [LocationSharingOption] = [
        .preset(5), .preset(10), .preset(15), .preset(30)
    ]
}
