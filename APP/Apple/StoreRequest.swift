//
//  StoreRequest.swift
//  APP
//
//  Created by pxx917144686 on 2025/08/20.
//
import Foundation
import CryptoKit
/// URLSession delegate for handling SSL and authentication challenges
class StoreRequestDelegate: NSObject, URLSessionDelegate {
    func urlSession(_ session: URLSession, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        // 处理SSL证书验证
        guard challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        // 对于Apple的域名，使用默认验证
        let host = challenge.protectionSpace.host
        if host.hasSuffix(".apple.com") || host.hasSuffix(".itunes.apple.com") {
            completionHandler(.performDefaultHandling, nil)
        } else {
            completionHandler(.performDefaultHandling, nil)
        }
    }
}
/// Store API request handler for authentication, downloads, and purchases
class StoreRequest {
    static let shared = StoreRequest()
    private let session: URLSession
    private let baseURL = "https://p25-buy.itunes.apple.com"
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 300
        // 添加Cookie存储
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpCookieAcceptPolicy = .always
        config.httpShouldSetCookies = true
        // 修复SSL连接问题
        config.tlsMinimumSupportedProtocolVersion = .TLSv12
        config.tlsMaximumSupportedProtocolVersion = .TLSv13
        self.session = URLSession(configuration: config, delegate: StoreRequestDelegate(), delegateQueue: nil)
    }
    /// Authenticate user with Apple ID
    /// - Parameters:
    ///   - email: Apple ID email
    ///   - password: Apple ID password
    ///   - mfa: Two-factor authentication code (optional)
    /// - Returns: Authentication response
    func authenticate(
        email: String,
        password: String,
        mfa: String? = nil
    ) async throws -> StoreAuthResponse {
        print("🚀 [Chứng nhận bắt đầu] Bắt đầu quá trình xác thực ID Apple")
        print("📧 [Tham số xác thực] Apple ID: \(email)")
        print("🔐 [Tham số xác thực] Độ dài mật khẩu: \(password.count) ký tự")
        print("📱 [Tham số xác thực] Mã xác thực nhân tố kép: \(mfa != nil ? "Cung cấp(\(mfa!.count)bit)" : "Không được cung cấp")")
        let guid = getGUID()
        print("🆔 [Thông tin thiết bị] Tạo ra GUID: \(guid)")
        let url = URL(string: "https://auth.itunes.apple.com/auth/v1/native/fast?guid=\(guid)")!
        print("🌐 [Yêu cầu URL] \(url.absoluteString)")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-apple-plist", forHTTPHeaderField: "Content-Type")
        request.setValue(getUserAgent(), forHTTPHeaderField: "User-Agent")
        print("📋 [Yêu cầu tiêu đề] Content-Type: application/x-apple-plist")
        print("📋 [Yêu cầu tiêu đề] User-Agent: \(getUserAgent())")
        // 修复认证参数构建
        let attempt = mfa != nil ? 2 : 4
        let passwordWithMFA = password + (mfa ?? "")
        print("🔢 [Tham số xác thực] attempt: \(attempt)")
        print("🔐 [Tham số xác thực] Độ dài mật khẩu sau khi hợp nhất: \(passwordWithMFA.count) ký tự")
        let bodyDict: [String: Any] = [
            "appleId": email,
            "attempt": attempt,
            "createSession": "true",
            "guid": guid,
            "password": passwordWithMFA,
            "rmp": "0",
            "why": "signIn"
        ]
        print("📦 [Request body] Xây dựng các tham số xác thực: \(bodyDict.keys.sorted())")
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: bodyDict,
            format: .xml,
            options: 0
        )
        request.httpBody = plistData
        print("📤 [Gửi một yêu cầu] Kích thước Request body: \(plistData.count) Byte")
        print("⏳ [Yêu cầu mạng] Gửi yêu cầu xác thực đến máy chủ Apple ...")
        let (data, response) = try await session.data(for: request)
        print("📥 [Phản hồi nhận] Đã nhận được phản hồi của máy chủ, kích thước dữ liệu: \(data.count) Byte")
        guard let httpResponse = response as? HTTPURLResponse else {
            print("❌ [Lỗi mạng] Không thể nhận được phản hồi HTTP")
            throw StoreError.invalidResponse
        }
        print("📊 [Trạng thái phản hồi] Mã trạng thái HTTP: \(httpResponse.statusCode)")
        print("📋 [Tiêu đề phản hồi] Tất cả các tiêu đề phản hồi: \(httpResponse.allHeaderFields)")
        let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] ?? [:]
        print("📄 [Phân tích phản hồi] Phân tích thành công phản hồi ở định dạng plist")
        print("🔍 [Nội dung phản hồi] Tất cả các khóa có trong phản hồi: \(Array(plist.keys).sorted())")
        print("📝 [Chi tiết phản hồi] Hoàn thành nội dung phản hồi: \(plist)")
        // 检查根级别的dsPersonId
        let possibleRootKeys = ["dsPersonId", "dsPersonID", "dsid", "DSID", "directoryServicesIdentifier"]
        for key in possibleRootKeys {
            if let value = plist[key] {
                print("✅ [Kiểm tra DSID] Tìm khóa ở cấp độ gốc '\(key)': \(value)")
            }
        }
        // 增强2FA错误检测
        if let customerMessage = plist["customerMessage"] as? String {
            print("💬 [Tin nhắn máy chủ] customerMessage: \(customerMessage)")
            if customerMessage == "MZFinance.BadLogin.Configurator_message" ||
               customerMessage.contains("verification code is required") {
                print("🔐 [Xác thực nhân tố kép] Mã xác thực hai yếu tố được phát hiện")
                throw StoreError.codeRequired
            }
        }
        // 检查错误信息
        if let failureType = plist["failureType"] as? String {
            print("❌ [Xác thực thất bại] failureType: \(failureType)")
        }
        if let errorMessage = plist["errorMessage"] as? String {
            print("❌ [Thông báo lỗi] errorMessage: \(errorMessage)")
        }
        print("🔄 [Phản hồi độ phân giải] Bắt đầu phân tích phản hồi xác thực ...")
        let result = try parseAuthResponse(plist: plist, httpResponse: httpResponse)
        print("✅ [Chứng nhận được hoàn thành] Quá trình chứng nhận được hoàn thành")
        return result
    }
    /// Download app information
    /// - Parameters:
    ///   - appIdentifier: App identifier
    ///   - directoryServicesIdentifier: User's DSID
    ///   - appVersion: Specific app version (optional)
    ///   - passwordToken: User's password token for authentication
    ///   - storeFront: Store front identifier
    /// - Returns: Download response with app information
    func download(
        appIdentifier: String,
        directoryServicesIdentifier: String,
        appVersion: String? = nil,
        passwordToken: String? = nil,
        storeFront: String? = nil
    ) async throws -> StoreDownloadResponse {
        let guid = getGUID()
        let url = URL(string: "\(baseURL)/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct?guid=\(guid)")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-apple-plist", forHTTPHeaderField: "Content-Type")
        request.setValue(getUserAgent(), forHTTPHeaderField: "User-Agent")
        request.setValue(directoryServicesIdentifier, forHTTPHeaderField: "X-Dsid")
        request.setValue(directoryServicesIdentifier, forHTTPHeaderField: "iCloud-DSID")
        // 添加关键的认证请求头
        if let passwordToken = passwordToken {
            request.setValue(passwordToken, forHTTPHeaderField: "X-Token")
        }
        if let storeFront = storeFront {
            request.setValue(storeFront, forHTTPHeaderField: "X-Apple-Store-Front")
        }
        // 修复请求体参数
        var body: [String: Any] = [
            "creditDisplay": "",
            "guid": guid,
            "salableAdamId": appIdentifier
        ]
        // 支持字符串和数字类型的版本ID，确保请求总是包含版本参数
        if let appVersion = appVersion {
            // 首先尝试作为整数解析
            if let versionId = Int(appVersion) {
                body["externalVersionId"] = versionId
            } else {
                // 如果无法解析为整数，直接使用字符串值
                body["externalVersionId"] = appVersion
            }
        }
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: body,
            format: .xml,
            options: 0
        )
        request.httpBody = plistData
        // 添加请求体调试信息
        if let bodyString = String(data: plistData, encoding: .utf8) {
            print("[DEBUG] Request body: \(bodyString)")
        }
        print("[DEBUG] Request URL: \(url)")
        print("[DEBUG] Request headers: \(request.allHTTPHeaderFields ?? [:])")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StoreError.invalidResponse
        }
        let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] ?? [:]
        return try parseDownloadResponse(plist: plist, httpResponse: httpResponse)
    }
    /// Purchase app
    /// - Parameters:
    ///   - appIdentifier: App identifier
    ///   - directoryServicesIdentifier: User's DSID
    ///   - passwordToken: User's password token
    ///   - countryCode: Store region country code
    /// - Returns: Purchase response
    func purchase(
        appIdentifier: String,
        directoryServicesIdentifier: String,
        passwordToken: String,
        countryCode: String
    ) async throws -> StorePurchaseResponse {
        let url = URL(string: "\(baseURL)/WebObjects/MZBuy.woa/wa/buyProduct")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(getUserAgent(), forHTTPHeaderField: "User-Agent")
        request.setValue(directoryServicesIdentifier, forHTTPHeaderField: "X-Dsid")
        request.setValue(directoryServicesIdentifier, forHTTPHeaderField: "iCloud-DSID")
        request.setValue("143441-1,29", forHTTPHeaderField: "X-Apple-Store-Front")
        request.setValue(passwordToken, forHTTPHeaderField: "X-Token")
        let body: [String: Any] = [
            "guid": getGUID(),
            "salableAdamId": appIdentifier,
            "dsPersonId": directoryServicesIdentifier,
            "passwordToken": passwordToken,
            "price": "0",
            "pricingParameters": "STDQ",
            "productType": "C",
            "appExtVrsId": "0"
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: body,
            format: .xml,
            options: 0
        )
        request.httpBody = plistData
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw StoreError.invalidResponse
        }
        let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] ?? [:]
        return try parsePurchaseResponse(plist: plist, httpResponse: httpResponse)
    }
    // MARK: - Private Helper Methods
    /// Generate user agent string
    private func getUserAgent() -> String {
        return "Configurator/2.15 (Macintosh; OS X 11.0.0; 16G29) AppleWebKit/2603.3.8"
    }
    /// Generate GUID for requests
    private func getGUID() -> String {
        // 获取真实MAC地址
        var macAddress = ""
        var ifaddrs: UnsafeMutablePointer<ifaddrs>?
        if getifaddrs(&ifaddrs) == 0 {
            var ptr = ifaddrs
            while ptr != nil {
                defer { ptr = ptr?.pointee.ifa_next }
                let interface = ptr?.pointee
                let addrFamily = interface?.ifa_addr.pointee.sa_family
                if addrFamily == UInt8(AF_LINK) {
                    let name = String(cString: (interface?.ifa_name)!)
                    if name == "en0" { // WiFi interface
                        let sockaddr_dl_ptr = interface?.ifa_addr.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { $0 }
                        if let sockaddr_dl_ptr = sockaddr_dl_ptr {
                            let sockaddr_dl = sockaddr_dl_ptr.pointee
                            let dataPtr = withUnsafePointer(to: sockaddr_dl.sdl_data) { ptr in
                                return UnsafeRawPointer(ptr).advanced(by: Int(sockaddr_dl.sdl_nlen))
                            }
                            let data = Data(bytes: dataPtr, count: Int(sockaddr_dl.sdl_alen))
                            macAddress = data.map { String(format: "%02X", $0) }.joined()
                            break
                        }
                    }
                }
            }
            freeifaddrs(ifaddrs)
        }
        return macAddress.isEmpty ? "000000000000" : macAddress
    }
    /// Parse authentication response
    private func parseAuthResponse(
        plist: [String: Any],
        httpResponse: HTTPURLResponse
    ) throws -> StoreAuthResponse {
        print("🔍 [Độ phân giải bắt đầu] parseAuthResponse - Mã trạng thái: \(httpResponse.statusCode)")
        if httpResponse.statusCode == 200 {
            print("✅ [Kiểm tra trạng thái] HTTP 200 - Yêu cầu xác thực thành công")
            // 检查所有可能的dsPersonId键名变体
            let possibleKeys = ["dsPersonId", "dsPersonID", "dsid", "DSID", "directoryServicesIdentifier"]
            print("🔍 [Tìm kiếm DSID] Tìm kiếm tên khóa DSID có thể có ở cấp độ gốc: \(possibleKeys)")
            for key in possibleKeys {
                if let value = plist[key] {
                    print("🔍 [DEBUG] Tìm chìa khóa '\(key)': \(value)")
                }
            }
            print("📋 [Thông tin tài khoản] Bắt đầu phân tích accountInfo...")
            let accountInfo = parseAccountInfo(from: plist)
            print("🔐 [Phân tích mã thông báo] Tìm kiếm passwordToken...")
            let passwordToken = plist["passwordToken"] as? String ?? ""
            print("🔐 [Kết quả mã thông báo] passwordToken: '\(passwordToken.isEmpty ? "vô giá trị" : "Nhận(\(passwordToken.count)ký tự)")")
            print("🆔 [Phân tích cú pháp DSID] Tìm kiếm dsPersonID ở cấp độ gốc ...")
            // 尝试多种可能的键名
            let dsPersonId = (plist["dsPersonId"] as? String) ?? 
                           (plist["dsPersonID"] as? String) ?? 
                           (plist["dsid"] as? String) ?? 
                           (plist["DSID"] as? String) ?? 
                           (plist["directoryServicesIdentifier"] as? String) ?? ""
            print("🆔 [DSID结果] 根级别dsPersonId: '\(dsPersonId.isEmpty ? "空" : dsPersonId)'")
            print("📡 [Pings解析] 搜索pings数组...")
            let pings = plist["pings"] as? [String]
            print("📡 [Pings结果] pings: \(pings?.count ?? 0) 个项目")
            // 获取accountInfo中的dsPersonId作为备用
            let accountDsPersonId = accountInfo?.dsPersonId ?? ""
            print("👤 [账户DSID] accountInfo中的dsPersonId: '\(accountDsPersonId.isEmpty ? "空" : accountDsPersonId)'")
            // 选择最终的dsPersonId（优先使用根级别的，然后是accountInfo中的）
            let finalDsPersonId = !dsPersonId.isEmpty ? dsPersonId : accountDsPersonId
            print("✅ [最终DSID] 选定的dsPersonId: '\(finalDsPersonId.isEmpty ? "空" : finalDsPersonId)'")
            print("🏗️ [构建响应] 创建StoreAuthResponse对象...")
            let response = StoreAuthResponse(
                accountInfo: accountInfo ?? StoreAuthResponse.AccountInfo(
                    appleId: "",
                    address: StoreAuthResponse.AccountInfo.Address(
                        firstName: "",
                        lastName: ""
                    ),
                    dsPersonId: finalDsPersonId,
                    countryCode: nil,
                    storeFront: nil
                ),
                passwordToken: passwordToken,
                dsPersonId: finalDsPersonId,
                pings: pings
            )
            print("✅ [响应完成] StoreAuthResponse创建成功")
            print("📊 [响应摘要] AppleID: \(response.accountInfo.appleId)")
            print("📊 [响应摘要] DSID: \(response.dsPersonId.isEmpty ? "空" : response.dsPersonId)")
            print("📊 [响应摘要] Token: \(response.passwordToken.isEmpty ? "空" : "已获取")")
            return response
        } else {
            print("❌ [认证失败] HTTP状态码: \(httpResponse.statusCode)")
            let failureType = plist["failureType"] as? String ?? ""
            let customerMessage = plist["customerMessage"] as? String ?? ""
            print("❌ [失败类型] failureType: \(failureType)")
            print("💬 [客户消息] customerMessage: \(customerMessage)")
            if let errorMessage = plist["errorMessage"] as? String {
                print("💬 [错误消息] errorMessage: \(errorMessage)")
            }
            print("🔍 [错误详情] 完整错误响应: \(plist)")
            // 处理特殊的认证响应情况
            if !failureType.isEmpty {
                throw StoreError.fromFailureType(failureType)
            } else if customerMessage == "MZFinance.BadLogin.Configurator_message" {
                throw StoreError.codeRequired
            } else if customerMessage.contains("AMD-Action") {
                // AMD安全挑战 - 可能需要特殊处理，但目前按成功处理
                print("⚠️ [AMD挑战] 检测到AMD安全挑战，尝试继续处理...")
                // 创建一个空的成功响应，让调用者处理
                let emptyResponse = StoreAuthResponse(
                    accountInfo: StoreAuthResponse.AccountInfo(
                        appleId: "",
                        address: StoreAuthResponse.AccountInfo.Address(
                            firstName: "",
                            lastName: ""
                        ),
                        dsPersonId: "",
                        countryCode: "US",
                        storeFront: nil
                    ),
                    passwordToken: "",
                    dsPersonId: "",
                    pings: []
                )
                return emptyResponse
            } else {
                throw StoreError.unknownError
            }
        }
    }
    /// Parse account information from plist
    private func parseAccountInfo(from plist: [String: Any]) -> StoreAuthResponse.AccountInfo? {
        guard let accountInfo = plist["accountInfo"] as? [String: Any] else {
            print("🔍 [DEBUG] parseAccountInfo: 未找到 accountInfo 字段")
            return nil
        }
        print("🔍 [DEBUG] parseAccountInfo: accountInfo 内容: \(accountInfo)")
        print("🔍 [DEBUG] parseAccountInfo: accountInfo 所有键: \(Array(accountInfo.keys))")
        let appleId = accountInfo["appleId"] as? String ?? ""
        let address = accountInfo["address"] as? [String: Any]
        let firstName = address?["firstName"] as? String ?? ""
        let lastName = address?["lastName"] as? String ?? ""
        // 检查所有可能的dsPersonId键名变体
        let possibleKeys = ["dsPersonId", "dsPersonID", "dsid", "DSID", "directoryServicesIdentifier"]
        for key in possibleKeys {
            if let value = accountInfo[key] {
                print("🔍 [DEBUG] parseAccountInfo: 找到键 '\(key)': \(value)")
            }
        }
        // 尝试多种可能的键名
        let dsPersonId = (accountInfo["dsPersonId"] as? String) ?? 
                        (accountInfo["dsPersonID"] as? String) ?? 
                        (accountInfo["dsid"] as? String) ?? 
                        (accountInfo["DSID"] as? String) ?? 
                        (accountInfo["directoryServicesIdentifier"] as? String) ?? ""
        print("🔍 [DEBUG] parseAccountInfo: 最终获取的 dsPersonId: '\(dsPersonId)')")
        let countryCode = accountInfo["countryCode"] as? String
        let storeFront = accountInfo["storeFront"] as? String
        return StoreAuthResponse.AccountInfo(
            appleId: appleId,
            address: StoreAuthResponse.AccountInfo.Address(
                firstName: firstName,
                lastName: lastName
            ),
            dsPersonId: dsPersonId,
            countryCode: countryCode,
            storeFront: storeFront
        )
    }
    /// Parse download response
    private func parseDownloadResponse(
        plist: [String: Any],
        httpResponse: HTTPURLResponse
    ) throws -> StoreDownloadResponse {
        // 添加调试日志
        print("[DEBUG] HTTP Status Code: \(httpResponse.statusCode)")
        print("[DEBUG] Response plist keys: \(plist.keys.sorted())")
        if let songListRaw = plist["songList"] {
            print("[DEBUG] songList type: \(type(of: songListRaw))")
            print("[DEBUG] songList content: \(songListRaw)")
        } else {
            print("[DEBUG] songList not found in response")
        }
        if httpResponse.statusCode == 200 {
            var songList: [StoreItem] = []
            if let songs = plist["songList"] as? [[String: Any]] {
                songList = songs.compactMap { parseStoreItem(from: $0) }
            }
            print("[DEBUG] Parsed songList count: \(songList.count)")
            let dsPersonId = plist["dsPersonID"] as? String ?? ""
            let jingleDocType = plist["jingleDocType"] as? String
            let jingleAction = plist["jingleAction"] as? String
            let pings = plist["pings"] as? [String]
            return StoreDownloadResponse(
                songList: songList,
                dsPersonId: dsPersonId,
                jingleDocType: jingleDocType,
                jingleAction: jingleAction,
                pings: pings
            )
        } else {
            let failureType = plist["failureType"] as? String ?? "unknownError"
            print("[DEBUG] Error response - failureType: \(failureType)")
            throw StoreError.fromFailureType(failureType)
        }
    }
    /// Parse store item from plist
    private func parseStoreItem(from dict: [String: Any]) -> StoreItem? {
        guard let url = dict["URL"] as? String,
              let md5 = dict["md5"] as? String else {
            return nil
        }
        var sinfs: [SinfInfo] = []
        if let sinfsArray = dict["sinfs"] as? [[String: Any]] {
            sinfs = sinfsArray.compactMap { sinfDict in
                guard let id = sinfDict["id"] as? Int,
                      let sinfString = sinfDict["sinf"] as? String else {
                    return nil
                }
                return SinfInfo(id: id, sinf: sinfString)
            }
        }
        var metadata: AppMetadata
        if let metadataDict = dict["metadata"] as? [String: Any] {
            // 修复字段名映射问题
            let bundleId = metadataDict["softwareVersionBundleId"] as? String ?? 
                          metadataDict["bundle-identifier"] as? String ?? ""
            let bundleDisplayName = metadataDict["bundleDisplayName"] as? String ?? 
                                   metadataDict["itemName"] as? String ?? 
                                   metadataDict["item-name"] as? String ?? ""
            let bundleShortVersionString = metadataDict["bundleShortVersionString"] as? String ?? 
                                          metadataDict["bundle-short-version-string"] as? String ?? ""
            let softwareVersionExternalIdentifier = String(metadataDict["softwareVersionExternalIdentifier"] as? Int ?? 0)
            let softwareVersionExternalIdentifiers = metadataDict["softwareVersionExternalIdentifiers"] as? [Int]
            print("[DEBUG] 解析metadata字段:")
            print("[DEBUG] - bundleId: \(bundleId)")
            print("[DEBUG] - bundleDisplayName: \(bundleDisplayName)")
            print("[DEBUG] - bundleShortVersionString: \(bundleShortVersionString)")
            print("[DEBUG] - softwareVersionExternalIdentifier: \(softwareVersionExternalIdentifier)")
            print("[DEBUG] - softwareVersionExternalIdentifiers count: \(softwareVersionExternalIdentifiers?.count ?? 0)")
            metadata = AppMetadata(
                bundleId: bundleId,
                bundleDisplayName: bundleDisplayName,
                bundleShortVersionString: bundleShortVersionString,
                softwareVersionExternalIdentifier: softwareVersionExternalIdentifier,
                softwareVersionExternalIdentifiers: softwareVersionExternalIdentifiers
            )
        } else {
            metadata = AppMetadata(
                bundleId: "",
                bundleDisplayName: "",
                bundleShortVersionString: "",
                softwareVersionExternalIdentifier: "",
                softwareVersionExternalIdentifiers: nil
            )
        }
        return StoreItem(
            url: url,
            md5: md5,
            sinfs: sinfs,
            metadata: metadata
        )
    }
    /// Parse purchase response
    private func parsePurchaseResponse(
        plist: [String: Any],
        httpResponse: HTTPURLResponse
    ) throws -> StorePurchaseResponse {
        if httpResponse.statusCode == 200 {
            let dsPersonId = plist["dsPersonID"] as? String ?? ""
            let jingleDocType = plist["jingleDocType"] as? String
            let jingleAction = plist["jingleAction"] as? String
            let pings = plist["pings"] as? [String]
            return StorePurchaseResponse(
                dsPersonId: dsPersonId,
                jingleDocType: jingleDocType,
                jingleAction: jingleAction,
                pings: pings
            )
        } else {
            throw StoreError.fromFailureType(plist["failureType"] as? String ?? "unknownError")
        }
    }
}
// MARK: - Response Types
enum StoreError: Error, LocalizedError, Equatable {
    case networkError(Error)
    case invalidResponse
    case authenticationFailed
    case accountNotFound
    case invalidCredentials
    case serverError(Int)
    case unknown(String)
    case genericError
    case invalidItem
    case invalidLicense
    case unknownError
    case codeRequired
    case lockedAccount
    case keychainError
    var errorDescription: String? {
        switch self {
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .authenticationFailed:
            return "Authentication failed"
        case .accountNotFound:
            return "Account not found"
        case .invalidCredentials:
            return "Invalid credentials"
        case .serverError(let code):
            return "Server error: \(code)"
        case .unknown(let message):
            return "Unknown error: \(message)"
        case .genericError:
            return "Generic error occurred"
        case .invalidItem:
            return "Invalid item"
        case .invalidLicense:
            return "Invalid license"
        case .codeRequired:
            return "Verification code required"
        case .lockedAccount:
            return "Account is locked"
        case .keychainError:
            return "Keychain error occurred"
        case .unknownError:
            return "Unknown error occurred"
        }
    }
    static func fromFailureType(_ failureType: String) -> StoreError {
        switch failureType {
        case "authenticationFailed":
            return .authenticationFailed
        case "accountNotFound":
            return .accountNotFound
        case "invalidCredentials":
            return .invalidCredentials
        case "codeRequired":
            return .codeRequired
        case "lockedAccount":
            return .lockedAccount
        default:
            return .unknownError
        }
    }
    static func == (lhs: StoreError, rhs: StoreError) -> Bool {
        switch (lhs, rhs) {
        case (.invalidResponse, .invalidResponse),
             (.authenticationFailed, .authenticationFailed),
             (.accountNotFound, .accountNotFound),
             (.invalidCredentials, .invalidCredentials),
             (.genericError, .genericError),
             (.invalidItem, .invalidItem),
             (.invalidLicense, .invalidLicense),
             (.unknownError, .unknownError):
            return true
        case (.networkError(let lhsError), .networkError(let rhsError)):
            return lhsError.localizedDescription == rhsError.localizedDescription
        case (.serverError(let lhsCode), .serverError(let rhsCode)):
            return lhsCode == rhsCode
        case (.unknown(let lhsMessage), .unknown(let rhsMessage)):
            return lhsMessage == rhsMessage
        default:
            return false
        }
    }
}
struct StoreAuthResponse: Codable {
    let accountInfo: AccountInfo
    let passwordToken: String
    let dsPersonId: String
    let pings: [String]?
    struct AccountInfo: Codable {
        let appleId: String
        let address: Address
        let dsPersonId: String
        let countryCode: String?
        let storeFront: String?
        struct Address: Codable {
            let firstName: String
            let lastName: String
        }
    }
}

// MARK: - 响应类型定义
struct StoreDownloadResponse: Codable {
    let songList: [StoreItem]
    let dsPersonId: String
    let jingleDocType: String?
    let jingleAction: String?
    let pings: [String]?
}

struct StorePurchaseResponse: Codable {
    let dsPersonId: String
    let jingleDocType: String?
    let jingleAction: String?
    let pings: [String]?
}

struct StoreItem: Codable {
    let url: String
    let md5: String
    let sinfs: [SinfInfo]
    let metadata: AppMetadata
}

struct AppMetadata: Codable {
    let bundleId: String
    let bundleDisplayName: String
    let bundleShortVersionString: String
    let softwareVersionExternalIdentifier: String
    let softwareVersionExternalIdentifiers: [Int]?
    enum CodingKeys: String, CodingKey {
        case bundleId = "softwareVersionBundleId"
        case bundleDisplayName
        case bundleShortVersionString
        case softwareVersionExternalIdentifier
        case softwareVersionExternalIdentifiers
    }
}

struct SinfInfo: Codable {
    let id: Int
    let sinf: String
}