//
//  LocationSearchView.swift
//  Wheya
//
//  Created by Hiromichi Murakami on 2025/06/07.
//

import SwiftUI
import MapKit

// MARK: - LocationSearchView

/// 地図ベースのオートコンプリート検索結果をリスト表示するビュー
/// 選択された住所文字列と座標をバインディングで更新する
struct LocationSearchView: View {
    // MARK: Data Shared With Me
    /// ビューを閉じるための環境変数
    @Environment(\.dismiss) private var dismiss
    // Pass the whole meeting and not some parts to avoid race conditions
    @Binding var meeting: Meeting
    
    // MARK: Data In
    /// 新規追加モードか編集モードか
    let isNew: Bool

    // MARK: Data Owned By Me
    /// ユーザー入力を保持する検索文字列
    @State private var query: String

    /// MKLocalSearchCompleter をラップした補完ヘルパー
    @State private var completer = SearchCompleter()

    /// 検索フィールドにフォーカスする状態管理
    @FocusState private var searchIsFocused: Bool

    // MARK: - Initialization

    init(
        meeting: Binding<Meeting>,
        isNew: Bool = false
    ) {
        self._meeting = meeting
        // 編集時は既存の住所を初期値にセット
        self._query      = State(initialValue: meeting.wrappedValue.locationName)
        self.isNew       = isNew
    }

    // MARK: - Body
 
    var body: some View {
        List {
            // 検索補完結果を行ごとに表示
            ForEach(completer.results, id: \.self, content: suggestionRow)
        }
        .listStyle(.plain)
        // 検索バーをリストに追加
        .searchable(text: $query, prompt: "Search Meeting Location")
        .searchFocused($searchIsFocused)
        // 検索文字列の変更を監視
        .onChange(of: query) { _, newValue in
            if newValue.isEmpty {
                completer.clear()                // 文字列が空なら結果をクリア
            } else {
                completer.queryFragment = newValue  // 入力文字で補完を実行
            }
        }
        // ナビゲーションタイトルをモードに応じて変更
        .navigationTitle(isNew ? "Add Location" : "Edit Location")
        .navigationBarTitleDisplayMode(.inline)
        // ビュー表示時に検索フィールドにフォーカス
        .onAppear {
            DispatchQueue.main.async {
                searchIsFocused = true
            }
        }
        // To avoid a stuck keyboard
        .onDisappear {
            searchIsFocused = false
        }
    }

    // MARK: - Suggestion Row Helper

    /// 補完候補を行として描画するヘルパーメソッド
    private func suggestionRow(_ suggestion: MKLocalSearchCompletion) -> some View {
        VStack(alignment: .leading) {
            Text(suggestion.title)              // 主題
                .font(.headline)
            Text(suggestion.subtitle)           // 補助説明
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())             // 行全体をタップ可能に
        .onTapGesture { select(suggestion) }   // タップで選択処理
    }

    private func select(_ suggestion: MKLocalSearchCompletion) {
        let request = MKLocalSearch.Request(completion: suggestion)
        MKLocalSearch(request: request).start { response, _ in
            if let coord = response?.mapItems.first?.placemark.coordinate {
                DispatchQueue.main.async {

                    meeting = Meeting(
                        recordID: meeting.recordID,
                        createdAt: meeting.createdAt,
                        title: meeting.title,
                        date: meeting.date,
                        locationName: suggestion.title,
                        latitude: coord.latitude,
                        longitude: coord.longitude,
                        notes: meeting.notes,
                        shareMinutes: meeting.shareMinutes
                    )
                    
                    // Adds a tiny delay to allow searchIsFocused = false to finish defocusing the field before dismissing
                    searchIsFocused = false
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        dismiss()
                    }
                }
            }
        }
    }
}



