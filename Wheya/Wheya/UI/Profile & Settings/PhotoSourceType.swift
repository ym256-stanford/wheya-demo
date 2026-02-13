//
//  PhotoSourceType.swift
//  Wheya
//
//  Created by Yuliia Murakami on 6/9/25.
//

/// 画像の取得元を表す列挙型
enum PhotoSourceType: Identifiable {
    /// カメラから取得
    case camera
    /// 写真ライブラリから取得
    case photoLibrary

    /// Identifiable プロトコル用の一意な ID
    var id: String {
        switch self {
        case .camera:
            return "camera"
        case .photoLibrary:
            return "photoLibrary"
        }
    }
}
