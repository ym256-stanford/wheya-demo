//
//  ShareTextWithPreviewItemSource.swift
//  Wheya
//
//  Created by Hiromichi Murakami on 2025/09/16.
//

import UIKit
import LinkPresentation

final class ShareTextWithPreviewItemSource: NSObject, UIActivityItemSource {
    private let text: String
    private let previewTitle: String?     // ← 追加
    private let image: UIImage?

    init(text: String, previewTitle: String? = nil, previewImage: UIImage?) {
        self.text = text
        self.previewTitle = previewTitle
        self.image = previewImage
        super.init()
    }

    func activityViewControllerPlaceholderItem(_ : UIActivityViewController) -> Any { text }
    func activityViewController(_ : UIActivityViewController,
                                itemForActivityType: UIActivity.ActivityType?) -> Any? { text }

    // メール等の「件名」に使われる（対応アプリのみ）
    func activityViewController(_ : UIActivityViewController,
                                subjectForActivityType activityType: UIActivity.ActivityType?) -> String {
        previewTitle ?? ""
    }

    func activityViewControllerLinkMetadata(_ : UIActivityViewController) -> LPLinkMetadata? {
        // タイトル or 画像のどちらかがあればプレビューを出す
        guard previewTitle != nil || image != nil else { return nil }
        let meta = LPLinkMetadata()
        if let t = previewTitle { meta.title = t }             // ← ここでタイトル表示
        if let img = image {
            meta.iconProvider  = NSItemProvider(object: img)
            meta.imageProvider = NSItemProvider(object: img)
        }
        return meta
    }
}
