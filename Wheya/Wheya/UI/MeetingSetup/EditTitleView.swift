//
//  EditTitleView.swift
//  Wheya
//
//  Created by Hiromichi Murakami on 2025/05/27.
//

import SwiftUI

// MARK: - EditTitleView

/// ミーティングのタイトルを追加・編集するためのシンプルなフォーム
struct EditTitleView: View {
    // MARK: Bindings and Environment

    /// 親ビューと双方向バインディングされるタイトル文字列
    @Binding var title: String

    /// 新規作成モードか編集モードかを示すフラグ
    let isNew: Bool

    /// このビューを閉じるためのアクション
    @Environment(\.dismiss) private var dismiss

    // MARK: Local State

    /// 保存前のローカルドラフトタイトル
    @State private var draft: String

    /// テキストフィールドに自動でフォーカスを当てるための状態
    @FocusState private var isFocused: Bool

    // MARK: Initialization

    /// 初期化：親のタイトルバインディングと新規フラグを受け取り、ドラフトに初期値をコピー
    init(title: Binding<String>, isNew: Bool = false) {
        self._title = title
        self.isNew  = isNew
        _draft      = State(initialValue: title.wrappedValue)
    }

    // MARK: Body

    var body: some View {
        Form {
            HStack {
                // タイトル入力用テキストフィールド
                TextField("Add Meeting Title", text: $draft)
                    .focused($isFocused)           // ビュー表示後に自動フォーカス
                    .autocapitalization(.words)    // 単語ごとに大文字化
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
        .navigationTitle(isNew ? "Add Title" : "Edit Title")  // タイトルをモードに合わせて切替
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            // 保存ボタン：ドラフトを親に反映して閉じる
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    title = draft
                    dismiss()
                }
                // 空白のみの場合は無効化
                .disabled(draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
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
    static let rowVerticalPadding: CGFloat = 4  // 行垂直パディング
}

// MARK: - Preview

#Preview {
    NavigationStack {
        EditTitleView(title: .constant("Example"), isNew: true)
    }
}
