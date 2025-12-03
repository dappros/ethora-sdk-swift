//
//  AuthAPI.swift
//  XMPPChatCore
//
//  Authentication API (mirrors src/networking/api-requests/auth.api.ts)
//

import Foundation
import os.log

public struct AuthAPI {
    // MARK: - Response Models
    
    public struct LoginResponse: Codable {
        public let success: Bool
        public let token: String
        public let refreshToken: String
        public let user: UserResponse
        public let app: AppResponse?
        public let isAllowedNewAppCreate: Bool?
    }
    
    public struct UserResponse: Codable {
        public let defaultWallet: WalletResponse?
        public let tempPassword: String?
        public let utm: String?
        public let isBot: Bool?
        public let _id: String
        public let firstName: String?
        public let lastName: String?
        public let email: String?
        public let username: String?
        public let tags: [String]?
        public let profileImage: String?
        public let emails: [EmailResponse]?
        public let appId: String?
        public let xmppPassword: String?
        public let roles: [String]?
        public let isProfileOpen: Bool?
        public let isAssetsOpen: Bool?
        public let isAgreeWithTerms: Bool?
        public let homeScreen: String?
        public let registrationChannelType: String?
        public let updatedAt: String?
        public let __v: Int?
        public let authMethod: String?
        public let resetPasswordExpires: String?
        public let resetPasswordToken: String?
        public let xmppUsername: String?
        public let description: String?
        public let signupPlan: String?
    }
    
    public struct WalletResponse: Codable {
        public let walletAddress: String
    }
    
    public struct EmailResponse: Codable {
        public let loginType: String?
        public let email: String?
        public let verified: Bool?
        public let _id: String?
    }
    
    public struct AppResponse: Codable {
        public let isUserDataEncrypted: Bool?
    }
    
    // MARK: - Login with Email
    
    /// Login with email and password (mirrors loginEmail in auth.api.ts)
    /// POST /users/login-with-email
    /// - Parameters:
    ///   - email: User email
    ///   - password: User password
    ///   - baseURL: API base URL
    ///   - appToken: App token for Authorization header
    /// - Returns: LoginResponse with token, refreshToken, and user data
    public static func loginWithEmail(
        email: String,
        password: String,
        baseURL: URL = URL(string: "https://api.ethoradev.com/v1")!,
        appToken: String = AppConfig.appToken
    ) async throws -> LoginResponse {
        // FORCE VISIBLE LOGGING - This MUST appear in Xcode console
        NSLog("🔥🔥🔥 AUTHAPI.LOGINWITHEMAIL CALLED 🔥🔥🔥")
        print("🔥🔥🔥 AUTHAPI.LOGINWITHEMAIL CALLED 🔥🔥🔥")
        
        let url = baseURL.appendingPathComponent("users/login-with-email")
        NSLog("🌐 AuthAPI.loginWithEmail: URL = %@", url.absoluteString)
        NSLog("📧 AuthAPI.loginWithEmail: email = %@", email)
        print("🌐 AuthAPI.loginWithEmail: URL = \(url.absoluteString)")
        print("📧 AuthAPI.loginWithEmail: email = \(email)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(appToken, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        struct LoginBody: Codable {
            let email: String
            let password: String
        }
        let body = LoginBody(email: email, password: password)
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthAPIError.networkError("No HTTPURLResponse")
        }
        
        // Log full API response to console - USING MULTIPLE METHODS TO ENSURE VISIBILITY
        let separator = "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        let statusText = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
        
        // Use NSLog for guaranteed visibility in Xcode console
        NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        NSLog("📦 FULL API RESPONSE (/users/login-with-email):")
        NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        NSLog("Status: %d", httpResponse.statusCode)
        NSLog("Status Text: %@", statusText)
        NSLog("")
        
        // Log headers
        NSLog("Headers:")
        for (key, value) in httpResponse.allHeaderFields {
            if let keyString = key as? String, let valueString = value as? String {
                NSLog("  %@: %@", keyString, valueString)
            }
        }
        NSLog("")
        
        // Log response body
        NSLog("Full Response Data:")
        if let responseBody = String(data: data, encoding: .utf8) {
            // Try to pretty print JSON
            if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted]),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                NSLog("%@", prettyString)
            } else {
                NSLog("%@", responseBody)
            }
        } else {
            NSLog("⚠️ Could not decode response body as UTF-8")
            NSLog("   Response data size: %d bytes", data.count)
        }
        NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        // Also use print for good measure
        print(separator)
        print("📦 FULL API RESPONSE (/users/login-with-email):")
        print(separator)
        print("Status: \(httpResponse.statusCode)")
        print("Status Text: \(statusText)")
        print("")
        print("Headers:")
        for (key, value) in httpResponse.allHeaderFields {
            if let keyString = key as? String, let valueString = value as? String {
                print("  \(keyString): \(valueString)")
            }
        }
            print("")
        print("Full Response Data:")
        if let responseBody = String(data: data, encoding: .utf8) {
            if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted]),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                print(prettyString)
            } else {
            print(responseBody)
            }
        } else {
            print("⚠️ Could not decode response body as UTF-8")
            print("   Response data size: \(data.count) bytes")
        }
        print(separator)
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "<no body>"
            print("❌ AuthAPI.loginWithEmail HTTP Error \(httpResponse.statusCode): \(errorBody)")
            throw AuthAPIError.httpError(httpResponse.statusCode, errorBody)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        do {
            let loginResponse = try decoder.decode(LoginResponse.self, from: data)
            
            // Print parsed login response details
            print("✅ AuthAPI.loginWithEmail: SUCCESS! Parsed response:")
            print("   success: \(loginResponse.success)")
            print("   token: \(loginResponse.token.prefix(50))...")
            print("   refreshToken: \(loginResponse.refreshToken.prefix(50))...")
            print("   user._id: \(loginResponse.user._id)")
            print("   user.email: \(loginResponse.user.email ?? "nil")")
            print("   user.firstName: \(loginResponse.user.firstName ?? "nil")")
            print("   user.lastName: \(loginResponse.user.lastName ?? "nil")")
            print("   user.xmppUsername: \(loginResponse.user.xmppUsername ?? "nil")")
            print("   user.xmppPassword: \(loginResponse.user.xmppPassword ?? "nil")")
            print("   user.appId: \(loginResponse.user.appId ?? "nil")")
            
            return loginResponse
        } catch {
            let jsonString = String(data: data, encoding: .utf8) ?? "<no data>"
            print("❌ AuthAPI.loginWithEmail Decode Error: \(error)")
            print("📄 Response body: \(jsonString)")
            throw AuthAPIError.decodeError(error.localizedDescription)
        }
    }
    
    // MARK: - Refresh Token
    
    /// Refresh user token (mirrors refresh in apiClient.ts)
    /// POST /users/login/refresh
    /// - Parameters:
    ///   - refreshToken: Current refresh token
    ///   - baseURL: API base URL
    ///   - appToken: App token for Authorization header
    /// - Returns: New token and refreshToken
    public static func refreshToken(
        refreshToken: String,
        baseURL: URL = URL(string: "https://api.ethoradev.com/v1")!,
        appToken: String = AppConfig.appToken
    ) async throws -> (token: String, refreshToken: String) {
        let url = baseURL.appendingPathComponent("users/login/refresh")
        print("🌐 AuthAPI.refreshToken: URL = \(url.absoluteString)")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(appToken, forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        
        // Send refreshToken in body
        struct RefreshBody: Codable {
            let refreshToken: String
        }
        let body = RefreshBody(refreshToken: refreshToken)
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthAPIError.networkError("No HTTPURLResponse")
        }
        
        // Log full API response to console - USING MULTIPLE METHODS TO ENSURE VISIBILITY
        let separator = "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        let statusText = HTTPURLResponse.localizedString(forStatusCode: httpResponse.statusCode)
        
        // Use NSLog for guaranteed visibility in Xcode console
        NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        NSLog("📦 FULL API RESPONSE (/users/login/refresh):")
        NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        NSLog("Status: %d", httpResponse.statusCode)
        NSLog("Status Text: %@", statusText)
        NSLog("")
        
        // Log headers
        NSLog("Headers:")
        for (key, value) in httpResponse.allHeaderFields {
            if let keyString = key as? String, let valueString = value as? String {
                NSLog("  %@: %@", keyString, valueString)
            }
        }
        NSLog("")
        
        // Log response body
        NSLog("Full Response Data:")
        if let responseBody = String(data: data, encoding: .utf8) {
            if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted]),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                NSLog("%@", prettyString)
            } else {
                NSLog("%@", responseBody)
            }
        } else {
            NSLog("⚠️ Could not decode response body as UTF-8")
            NSLog("   Response data size: %d bytes", data.count)
        }
        NSLog("━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━")
        
        // Also use print for good measure
        print(separator)
        print("📦 FULL API RESPONSE (/users/login/refresh):")
        print(separator)
        print("Status: \(httpResponse.statusCode)")
        print("Status Text: \(statusText)")
        print("")
        print("Headers:")
        for (key, value) in httpResponse.allHeaderFields {
            if let keyString = key as? String, let valueString = value as? String {
                print("  \(keyString): \(valueString)")
            }
        }
        print("")
        print("Full Response Data:")
        if let responseBody = String(data: data, encoding: .utf8) {
            if let jsonObject = try? JSONSerialization.jsonObject(with: data, options: []),
               let prettyData = try? JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted]),
               let prettyString = String(data: prettyData, encoding: .utf8) {
                print(prettyString)
            } else {
                print(responseBody)
            }
        } else {
            print("⚠️ Could not decode response body as UTF-8")
            print("   Response data size: \(data.count) bytes")
        }
        print(separator)
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "<no body>"
            print("❌ AuthAPI.refreshToken HTTP Error \(httpResponse.statusCode): \(errorBody)")
            throw AuthAPIError.httpError(httpResponse.statusCode, errorBody)
        }
        
        struct RefreshResponse: Codable {
            let token: String
            let refreshToken: String
        }
        
        let decoder = JSONDecoder()
        let refresh = try decoder.decode(RefreshResponse.self, from: data)
        print("✅ AuthAPI.refreshToken: Got new token prefix=\(refresh.token.prefix(20))...")
        return (refresh.token, refresh.refreshToken)
    }
    
    // MARK: - Upload File
    
    /// Upload file (mirrors uploadFile in auth.api.ts)
    /// POST /files/
    /// - Parameters:
    ///   - fileData: File data to upload
    ///   - fileName: Name of the file
    ///   - mimeType: MIME type of the file
    ///   - baseURL: API base URL
    ///   - token: User token for Authorization header
    /// - Returns: UploadResponse with file information
    public static func uploadFile(
        fileData: Data,
        fileName: String,
        mimeType: String,
        baseURL: URL = URL(string: "https://api.ethoradev.com/v1")!,
        token: String
    ) async throws -> UploadResponse {
        
        let url = baseURL.appendingPathComponent("files/")
        print("🌐 AuthAPI.uploadFile: URL = \(url.absoluteString)")
        print("📁 Uploading file: \(fileName) (\(fileData.count) bytes, \(mimeType))")
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        
        // Create multipart form data
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        
        var body = Data()
        
        // Add file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"files\"; filename=\"\(fileName)\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: \(mimeType)\r\n\r\n".data(using: .utf8)!)
        body.append(fileData)
        body.append("\r\n".data(using: .utf8)!)
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        
        request.httpBody = body
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AuthAPIError.networkError("No HTTPURLResponse")
        }
        
        guard (200..<300).contains(httpResponse.statusCode) else {
            let errorBody = String(data: data, encoding: .utf8) ?? "<no body>"
            print("❌ AuthAPI.uploadFile HTTP Error \(httpResponse.statusCode): \(errorBody)")
            throw AuthAPIError.httpError(httpResponse.statusCode, errorBody)
        }
        
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        
        do {
            let uploadResponse = try decoder.decode(UploadResponse.self, from: data)
            print("✅ AuthAPI.uploadFile: SUCCESS! Uploaded \(uploadResponse.results.count) file(s)")
            return uploadResponse
        } catch {
            let jsonString = String(data: data, encoding: .utf8) ?? "<no data>"
            print("❌ AuthAPI.uploadFile Decode Error: \(error)")
            print("📄 Response body: \(jsonString)")
            throw AuthAPIError.decodeError(error.localizedDescription)
        }
    }
}

// MARK: - Upload Response Models

public struct UploadResponse: Codable {
    public let results: [UploadResult]
}

public struct UploadResult: Codable {
    public let _id: String
    public let filename: String
    public let mimetype: String
    public let size: String
    public let location: String
    public let locationPreview: String?
    public let createdAt: String
    public let expiresAt: String?
    public let isVisible: Bool?
    public let userId: String?
    public let originalname: String?
    public let ownerKey: String?
    public let duration: String?
    public let updatedAt: String?
    public let isPrivate: Bool?
    public let __v: Int?
}

public enum AuthAPIError: Error, LocalizedError {
    case httpError(Int, String)
    case decodeError(String)
    case networkError(String)
    
    public var errorDescription: String? {
        switch self {
        case .httpError(let code, let body):
            return "HTTP \(code): \(body)"
        case .decodeError(let message):
            return "Decode error: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}

