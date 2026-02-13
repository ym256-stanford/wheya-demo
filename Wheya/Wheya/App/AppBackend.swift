//
//  AppBackend.swift
//  Wheya
//
//  Created by Yuliia Murakami on 9/16/25.
//

import Foundation

// Minimal client your app calls. Your server does the real Apple work.
final class AppBackend {
    static let shared = AppBackend()

    // TODO: Point this at your API
    private let baseURL = URL(string: "https://api.example.com")!
    private let session = URLSession(configuration: .default)

    // Send the one-time authorizationCode to your backend so it can exchange & store the refresh_token.
    func registerSIWA(
        appleUserID: String,
        authorizationCode: Data?,
        identityToken: Data?,
        fullName: String?
    ) async throws {
        // If user reuses an existing Apple login sheet, code can be nil. That's OK; just skip.
        guard let authorizationCode, let codeStr = String(data: authorizationCode, encoding: .utf8) ?? authorizationCode.base64EncodedString() as String? else {
            return
        }

        let tokenStr = identityToken.flatMap { String(data: $0, encoding: .utf8) } ?? identityToken?.base64EncodedString()

        var req = URLRequest(url: baseURL.appendingPathComponent("/auth/apple/register"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(RegisterPayload(
            appleUserID: appleUserID,
            authorizationCode: codeStr,
            identityToken: tokenStr,
            fullName: fullName
        ))

        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    // Ask your backend to revoke the stored SIWA refresh_token with Apple.
    func revokeSIWA(forAppleUserID userID: String) async throws {
        var req = URLRequest(url: baseURL.appendingPathComponent("/auth/apple/revoke"))
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["appleUserID": userID])

        let (_, resp) = try await session.data(for: req)
        guard let http = resp as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    // MARK: - Models
    private struct RegisterPayload: Codable {
        let appleUserID: String
        let authorizationCode: String
        let identityToken: String?
        let fullName: String?
    }
}
