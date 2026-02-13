//
//  LocationPickerView.swift
//  Wheya
//
//  Created by Hiromichi Murakami on 2025/07/11.
//

import SwiftUI
import MapKit

/// SwiftUI からドラッガブルな MKPointAnnotation を扱う MapView を提供
struct LocationPickerView: View {
    @Binding var locationName: String      // 選択した場所名をバインディング
    @Binding var coordinate: CLLocationCoordinate2D  // 選択した座標をバインディング
    @Environment(\.dismiss) private var dismiss     // モーダルを閉じるための環境変数
    
    @State private var locManager = LocationManager()  // 位置情報取得マネージャ
    @State private var region = MKCoordinateRegion(
        center: .init(latitude: 0, longitude: 0),        // 地図中心の初期値
        span: .init(latitudeDelta: 0.01, longitudeDelta: 0.01)  // ズームレベル
    )
    @State private var didCenterOnUser = false          // 中心合わせ済みフラグ
    
    var body: some View {
        NavigationStack {
            DraggableMapView(coordinate: $coordinate, region: $region)
                .ignoresSafeArea(edges: .top)               // 上端まで広げる
                .onAppear {
                    // draftCoordinate がすでに渡されていれば、その位置を初期中心に設定
                    if coordinate.latitude != 0 || coordinate.longitude != 0 {
                        region.center = coordinate
                        didCenterOnUser = true
                    }
                }
                .onReceive(locManager.$lastLocation.compactMap { $0 }) { loc in
                    // まだ中心合わせしていなければ、現在地を初期中心に設定
                    guard !didCenterOnUser else { return }
                    region.center = loc.coordinate
                    didCenterOnUser = true
                }
                .navigationTitle("Pick Location")         // ナビゲーションタイトル
                .navigationBarTitleDisplayMode(.inline)    // タイトル表示スタイル
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            // Done ボタン押下時に逆ジオコーディングして場所名を取得
                            let geocoder = CLGeocoder()
                            let loc = CLLocation(
                                latitude: coordinate.latitude,
                                longitude: coordinate.longitude
                            )
                            geocoder.reverseGeocodeLocation(loc) { placemarks, error in
                                if let placemark = placemarks?.first {
                                    // 住所パーツを組み立て
                                    let parts: [String?] = [
                                        placemark.name,
                                        placemark.locality,
                                        placemark.administrativeArea
                                    ]
                                    let address = parts.compactMap { $0 }.joined(separator: ", ")
                                    DispatchQueue.main.async {
                                        locationName = address
                                        dismiss()
                                    }
                                } else {
                                    // 逆ジオ失敗時は緯度経度文字列をセット
                                    DispatchQueue.main.async {
                                        locationName = String(
                                            format: "%.5f, %.5f",
                                            coordinate.latitude,
                                            coordinate.longitude
                                        )
                                        dismiss()
                                    }
                                }
                            }
                        }
                    }
                }
        }
    }
}

/// MKMapView をラップし、長押しでピン設置・ドラッグ可能にする
struct DraggableMapView: UIViewRepresentable {
    @Binding var coordinate: CLLocationCoordinate2D  // 座標バインディング
    @Binding var region: MKCoordinateRegion         // 地図領域バインディング

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView()
        mapView.delegate = context.coordinator         // DelegateをCoordinator経由で設定
        mapView.showsUserLocation = true               // 現在地表示（青いドット）
        // 長押しジェスチャーを追加
        let longPress = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handleLongPress(_:))
        )
        mapView.addGestureRecognizer(longPress)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        mapView.setRegion(region, animated: true)       // region 更新で地図を移動
        context.coordinator.updateAnnotation(on: mapView, to: coordinate) // ピン位置更新
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    class Coordinator: NSObject, MKMapViewDelegate {
        var parent: DraggableMapView
        private var annotation: MKPointAnnotation?   // ピンの参照

        init(_ parent: DraggableMapView) {
            self.parent = parent
        }

        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began,
                  let mapView = gesture.view as? MKMapView
            else { return }

            let point = gesture.location(in: mapView)
            let coord = mapView.convert(point, toCoordinateFrom: mapView)

            // 既存ピンを削除
            if let existing = annotation {
                mapView.removeAnnotation(existing)
            }
            // 新規ピンを追加
            let pin = MKPointAnnotation()
            pin.coordinate = coord
            annotation = pin
            mapView.addAnnotation(pin)
            parent.coordinate = coord                // バインディング更新
        }

        /// バインディング座標が変わったときにピンを更新
        func updateAnnotation(on mapView: MKMapView, to coord: CLLocationCoordinate2D) {
            // 非ゼロ座標の場合にのみピンを表示
            guard coord.latitude != 0 || coord.longitude != 0 else { return }
            if annotation == nil {
                let pin = MKPointAnnotation()
                pin.coordinate = coord
                annotation = pin
                mapView.addAnnotation(pin)
            } else {
                annotation?.coordinate = coord
            }
            mapView.setCenter(coord, animated: true)  // 必要なら中心追従
        }

        /// ピンの見た目設定
        func mapView(
            _ mapView: MKMapView,
            viewFor annotation: MKAnnotation
        ) -> MKAnnotationView? {
            guard annotation is MKPointAnnotation else { return nil }
            let id = "draggablePin"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: id)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            view.annotation = annotation
            view.isDraggable = true                   // ドラッグ許可
            return view
        }

        /// ドラッグ終了後に座標バインディングを更新
        func mapView(
            _ mapView: MKMapView,
            annotationView view: MKAnnotationView,
            didChange newState: MKAnnotationView.DragState,
            fromOldState oldState: MKAnnotationView.DragState
        ) {
            if newState == .ending, let coord = view.annotation?.coordinate {
                parent.coordinate = coord
            }
        }
    }
}

#if DEBUG
struct LocationPickerView_Previews: PreviewProvider {
    static var previews: some View {
        LocationPickerView(
            locationName: .constant(""),
            coordinate: .constant(
                CLLocationCoordinate2D(latitude: 37.7749,
                                       longitude: -122.4194)
            )
        )
    }
}
#endif
