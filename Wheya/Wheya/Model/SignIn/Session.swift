//
//  Session.swift
//  Wheya
//
//  Created by Yuliia Murakami on 7/3/25.
//

import Foundation
import Observation
import UIKit

/// ユーザーのセッション情報（認証状態・プロフィール）を管理するクラス
@Observable
class Session {
    /// Apple ID 取得時に設定されるユーザー識別子
    var appleUserID: String? {
        didSet {
            // UserDefaults に保存
            UserDefaults.standard.set(appleUserID, forKey: "appleUserID")
        }
    }

    /// ログイン状態のフラグ
    var isLoggedIn: Bool {
        didSet {
            // UserDefaults にログイン状態を保存
            UserDefaults.standard.set(isLoggedIn, forKey: "isLoggedIn")
        }
    }
    
    // Gate that forces Profile->EditName on first login or empty name
    var requiresProfileName: Bool = false

    // MARK: - Init

    init() {
        // アプリ起動時に UserDefaults から以前の値を復元
        self.appleUserID = UserDefaults.standard.string(forKey: "appleUserID")
        self.isLoggedIn = UserDefaults.standard.bool(forKey: "isLoggedIn")
    }

    /// サインアウト処理: キャッシュ削除と状態クリア
    func signOut() {
        // セッション情報をクリア
        appleUserID = nil
        isLoggedIn = false
        // UserDefaults からも削除
        UserDefaults.standard.removeObject(forKey: "appleUserID")
        UserDefaults.standard.set(false, forKey: "isLoggedIn")
    }
}
