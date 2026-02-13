//
//  SearchCompleter.swift
//  Wheya
//
//  Created by Hiromichi Murakami on 2025/06/07.
//

import Foundation
import MapKit
import Combine

/// MapKit の補完検索を SwiftUI 用にラップするクラス
final class SearchCompleter: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    // MARK: - 公開プロパティ

    /// 検索候補の結果を公開（SwiftUI ビューが監視）
    @Published var results: [MKLocalSearchCompletion] = []

    // MARK: - 内部プロパティ

    /// MapKit の補完検索オブジェクト
    private let completer = MKLocalSearchCompleter()

    // MARK: - 初期化

    /// デリゲートを設定して初期化
    override init() {
        super.init()
        completer.delegate = self
    }

    // MARK: - パブリック API

    /// 検索文字列をセットすると自動的に補完検索が始まる
    var queryFragment: String {
        get { completer.queryFragment }
        set { completer.queryFragment = newValue }
    }

    /// 現在の検索をキャンセルし、結果をクリアする
    func clear() {
        completer.cancel()
        DispatchQueue.main.async {
            self.results = []
        }
    }

    // MARK: - MKLocalSearchCompleterDelegate

    /// 補完結果が更新されたときに呼ばれる
    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        DispatchQueue.main.async {
            self.results = completer.results
        }
    }

    /// 補完検索でエラー発生時に呼ばれる
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("SearchCompleter error:", error)
    }
}
