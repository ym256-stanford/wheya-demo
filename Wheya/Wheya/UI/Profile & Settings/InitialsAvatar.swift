//
//  InitialsAvatar.swift
//  Wheya
//
//  Created by Yuliia Murakami on 9/13/25.
//


import UIKit

enum InitialsAvatar {
    static func fromName(_ name: String, size: CGFloat = 256, interfaceStyle: UIUserInterfaceStyle? = nil) -> UIImage {
        let initials = makeInitials(name)

        let trait = interfaceStyle.map { UITraitCollection(userInterfaceStyle: $0) } ?? UIScreen.main.traitCollection
        let bg = resolvedAvatarBackground(for: trait)

        let fmt = UIGraphicsImageRendererFormat.default()
        fmt.scale = UIScreen.main.scale
        let r = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: fmt)

        let img = r.image { _ in
            bg.setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: size, height: size)).fill()

            // initials (white)
            let font = UIFont.systemFont(ofSize: size * 0.42, weight: .semibold)
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: UIColor.white]
            let t = NSAttributedString(string: initials, attributes: attrs)
            let sz = t.size()
            t.draw(in: CGRect(x: (size - sz.width)/2, y: (size - sz.height)/2, width: sz.width, height: sz.height).integral)
        }
        return img.withRenderingMode(.alwaysOriginal)
    }

    private static func resolvedAvatarBackground(for trait: UITraitCollection) -> UIColor {
        // Dark ~ iOS “elevated” gray (#1C1C1E). Light ~ slightly darker than systemGray5
        let dynamic = UIColor { t in
            // UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1) // #1C1C1E
            // UIColor(white: 0.82, alpha: 1) // #D2D2D2
            // UIColor(white: 0.10, alpha: 1)  // #191919
            // UIColor(white: 0.72, alpha: 1)  // #B8B8B8
            if t.userInterfaceStyle == .dark {
                return UIColor(white: 0.82, alpha: 1) //
            } else {
                return UIColor(white: 0.82, alpha: 1) // ~#D2D2D2
            }
        }
        return dynamic.resolvedColor(with: trait)
    }

    private static func makeInitials(_ name: String) -> String {
        let parts = name.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
        guard let first = parts.first?.first else { return "?" }
        let last = (parts.count > 1 ? parts.last!.first! : first)
        return String(first).uppercased() + String(last).uppercased()
    }
}


enum DefaultAvatar {
    /// Person glyph on an Apple-style system gray circle.
    static func person(size: CGFloat = 256, interfaceStyle: UIUserInterfaceStyle? = nil) -> UIImage {
        let trait = interfaceStyle.map { UITraitCollection(userInterfaceStyle: $0) } ?? UIScreen.main.traitCollection
        let bg = UIColor.systemGray5.resolvedColor(with: trait)

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = UIScreen.main.scale
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: size, height: size), format: format)

        let img = renderer.image { _ in
            // System gray circle
            bg.setFill()
            UIBezierPath(ovalIn: CGRect(x: 0, y: 0, width: size, height: size)).fill()

            // SF Symbol centered (white for strong contrast)
            let cfg = UIImage.SymbolConfiguration(pointSize: size * 0.44, weight: .regular)
            if let symbol = UIImage(systemName: "person.fill", withConfiguration: cfg)?
                .withTintColor(.white, renderingMode: .alwaysOriginal) {
                let sz = symbol.size
                let rect = CGRect(
                    x: (size - sz.width) / 2.0,
                    y: (size - sz.height) / 2.0,
                    width: sz.width,
                    height: sz.height
                )
                symbol.draw(in: rect)
            }
        }

        return img.withRenderingMode(.alwaysOriginal)
    }
}

