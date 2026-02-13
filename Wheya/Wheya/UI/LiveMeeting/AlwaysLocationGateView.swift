//
//  AlwaysLocationGateView.swift
//  Wheya
//
//  Created by Yuliia Murakami on 9/19/25.
//

import SwiftUI
import CoreLocation

struct AlwaysLocationGateView: View {
    @Environment(LocationSharingService.self) private var svc
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "location.circle.fill")
                .font(.system(size: 48, weight: .semibold))
            Text("Allow “Always” to Share Location")
                .font(.title3).bold()
            Text("We share your live location with attendees during the meeting window, even if the app is closed.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            } label: {
                Text("Open Settings")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .overlay(RoundedRectangle(cornerRadius: 12).stroke(.gray.opacity(0.3)))
            }

            Text(statusText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .padding(24)
    }

    private var statusText: String {
        switch svc.authStatus {
        case .authorizedAlways: return "Status: Always (ready)"
        case .authorizedWhenInUse: return "Status: While Using (tap above to upgrade)"
        case .denied: return "Status: Denied (use Settings)"
        case .restricted: return "Status: Restricted"
        case .notDetermined: return "Status: Not Determined"
        @unknown default: return "Status: Unknown"
        }
    }
}
