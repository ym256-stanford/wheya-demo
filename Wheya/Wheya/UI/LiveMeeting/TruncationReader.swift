//
//  TruncationReader.swift
//  Wheya
//
//  Created by Hiromichi Murakami on 2025/08/12.
//

import SwiftUI
import UIKit

/// 指定幅・行数で UILabel が「…」省略になるかを検知
struct TruncationReader: UIViewRepresentable {
    let text: String
    let font: UIFont
    let width: CGFloat
    let lineLimit: Int
    @Binding var isTruncated: Bool

    func makeUIView(context: Context) -> UILabel { UILabel() }

    func updateUIView(_ uiView: UILabel, context: Context) {
        // ① 全文の高さ
        let full = UILabel()
        full.numberOfLines = 0
        full.font = font
        full.text = text
        full.lineBreakMode = .byWordWrapping
        let fullSize = full.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))

        // ② 制限（例: 1行）の高さ（末尾…）
        let limited = UILabel()
        limited.numberOfLines = lineLimit
        limited.font = font
        limited.text = text
        limited.lineBreakMode = .byTruncatingTail
        let limSize = limited.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))

        let truncated = limSize.height < fullSize.height - 0.5
        if truncated != isTruncated {
            DispatchQueue.main.async { self.isTruncated = truncated }
        }
    }
}
