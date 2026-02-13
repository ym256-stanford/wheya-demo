//
//  LocationManager.swift
//  Wheya
//
//  Created by Hiromichi Murakami on 2025/07/11.
//

import Foundation
import CoreLocation

/// 現在地を取得して公開するクラス
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    /// 取得した最新の位置情報を公開する
    @Published var lastLocation: CLLocation?

    /// CoreLocation のマネージャー本体
    private let manager = CLLocationManager()

    override init() {
        super.init()
        // Delegate を設定
        manager.delegate = self
        // 位置情報の精度を最高に設定
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // アプリ使用中のみ位置情報取得の許可をリクエスト
        manager.requestWhenInUseAuthorization()
        // 継続的に位置情報を更新させて内部でウォームアップ
        manager.startUpdatingLocation()
        // 一度だけ位置情報を取得
        manager.requestLocation()
    }

    // MARK: - CLLocationManagerDelegate

    /// 位置情報が更新されると呼ばれる
    func locationManager(_ manager: CLLocationManager,
                         didUpdateLocations locations: [CLLocation]) {
        // 最初の位置情報を lastLocation にセット（Published で通知）
        lastLocation = locations.first
    }

    /// 位置情報取得に失敗したときに呼ばれる
    func locationManager(_ manager: CLLocationManager,
                         didFailWithError error: Error) {
        // エラー内容をログに出力
        print("Location error:", error)
    }
}
