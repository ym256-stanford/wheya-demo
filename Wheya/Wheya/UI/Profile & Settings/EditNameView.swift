//
//  EditNameView.swift
//  Wheya
//
//  Created by Hiromichi Murakami on 6/4/25.
//

import SwiftUI

struct EditNameView: View {
    @Environment(\.dismiss) private var dismiss       // View を閉じるための環境変数
    @Binding var name: String                         // 親ビューと双方向バインドする「名前」だけ
    @FocusState private var isFocused: Bool           // テキストフィールドのフォーカス制御

    var onSave: (String) async -> Void                // 名前変更を永続化するクロージャ
    @State private var draft: String                  // 編集用のローカルドラフト

    /// 初期化：渡された name バインディングの現在値を draft にコピー
    init(name: Binding<String>, onSave: @escaping (String) async -> Void) {
        self._name = name
        self.onSave = onSave
        self._draft = State(initialValue: name.wrappedValue)
    }

    var body: some View {
        Form {
            HStack(spacing: 8) {
                // 入力フィールド
                TextField("Enter your name", text: $draft)
                    .focused($isFocused)                   // onAppear でフォーカスを当てる
                    .autocapitalization(.words)            // 単語の先頭を自動大文字化
                    .disableAutocorrection(true)           // 自動補正を無効化
                    .padding(.trailing, draft.isEmpty ? 0 : 4) // 文字あり時に余白確保

                // 文字入力中はクリアボタンを表示
                if !draft.isEmpty {
                    Button { draft = "" } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
        .navigationTitle("Edit Name")                        // ナビゲーションタイトル
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // Save ボタン：ドラフトを binding に反映＆永続化クロージャ呼び出し
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
                    name = trimmed
                    Task {
                        await onSave(trimmed)
                        dismiss()
                    }
                }
                .disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty) // 空文字は無効
            }
        }
        .onAppear { isFocused = true }  // 画面表示時に入力フィールドへ自動フォーカス
    }
}
