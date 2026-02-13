//
//  EditNotesView.swift
//  Wheya
//
//  Created by Hiromichi Murakami on 2025/07/11.
//

import SwiftUI

// MARK: - EditNotesView

/// ミーティングのノートを追加・編集するシンプルなフォーム
struct EditNotesView: View {
    // MARK: - Bindings and Environment

    /// 親ビューと双方向にバインディングされるノート文字列
    @Binding var notes: String

    /// 新規作成モードか編集モードかを示すフラグ
    let isNew: Bool

    /// このビューを閉じるためのアクション
    @Environment(\.dismiss) private var dismiss

    // MARK: - Local State

    /// 保存前のローカルドラフトノート
    @State private var draft: String

    /// テキストフィールドに自動フォーカスを当てる状態
    @FocusState private var isFocused: Bool

    // MARK: - Initialization

    /// 初期化：親のノートバインディングと新規フラグを受け取り、ドラフトに初期値をコピー
    init(title: Binding<String>, isNew: Bool = false) {
        self._notes = title
        self.isNew  = isNew
        _draft      = State(initialValue: title.wrappedValue)
    }

    // MARK: - Body

    var body: some View {
        Form {
            HStack {
                // ノート入力用テキストフィールド
                TextField("Add Meeting Notes", text: $draft)
                    .focused($isFocused)           // ビュー表示後に自動フォーカス
                    .disableAutocorrection(true)   // 自動補正を無効化

                // ドラフトに文字がある場合にクリアボタンを表示
                if !draft.isEmpty {
                    Button {
                        draft = ""               // クリア操作
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, Constants.rowVerticalPadding)
        }
        .navigationTitle(isNew ? "Add Notes" : "Edit Notes")  // タイトルをモードで切替
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 保存ボタン：ドラフトを親に適用して閉じる
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    notes = draft
                    dismiss()
                }
            }
        }
        .onAppear {
            // フォーカスを当てる遅延実行
            DispatchQueue.main.async {
                isFocused = true
            }
        }
    }
}

// MARK: - Constants

private enum Constants {
    static let rowVerticalPadding: CGFloat = 4  // 行の上下パディング
}

// MARK: - Preview

#Preview {
    NavigationStack {
        EditNotesView(title: .constant("Example notes"), isNew: true)
    }
}
