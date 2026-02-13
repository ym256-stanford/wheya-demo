//
//  ShareSheet.swift
//  Wheya
//
//  Created by Hiromichi Murakami on 2025/09/16.
//

import SwiftUI
import UIKit

@MainActor
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]
    var activities: [UIActivity]? = nil
    var excludedActivityTypes: [UIActivity.ActivityType]? = nil
    var completion: UIActivityViewController.CompletionWithItemsHandler? = nil

    func makeUIViewController(context: Context) -> UIActivityViewController {
        let vc = UIActivityViewController(activityItems: items, applicationActivities: activities)
        vc.excludedActivityTypes = excludedActivityTypes
        vc.completionWithItemsHandler = completion
        return vc
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
