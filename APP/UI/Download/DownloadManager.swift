//
//  DownloadManager.swift
//  APP
//
//  Created by pxx917144686 on 2025/08/20.
//
import Foundation
import CryptoKit
import SwiftUI
#if canImport(ZipArchive)
import ZipArchive
#endif

// 为了避免与StoreRequest.swift中的类型冲突，这里使用不同的名称
struct DownloadStoreItem {
    let url: String
    let md5: String
    let sinfs: [DownloadSinfInfo]
    let metadata: DownloadAppMetadata
}

struct DownloadAppMetadata {
    let bundleId: String
    let bundleDisplayName: String
    let bundleShortVersionString: String
    let softwareVersionExternalIdentifier: String
    let softwareVersionExternalIdentifiers: [Int]?
}

struct DownloadSinfInfo {
    let id: Int
    let sinf: String
}

// IPAProcessor类定义在IPAProcessor.swift中
#if canImport(IPAProcessor)
// 使用外部IPAProcessor
#else
// IPA处理器实现
class IPAProcessor {
    static let shared = IPAProcessor()
    
    private init() {}
    
    /// 处理IPA文件，添加SC_Info文件夹和签名信息
    func processIPA(
        at ipaPath: URL,
        withSinfs sinfs: [Any], // 使用Any类型避免编译错误
        completion: @escaping (Result<URL, Error>) -> Void
    ) {
        print("🔧 [Bộ xử lý IPA] Bắt đầu xử lý các tệp IPA: \(ipaPath.path)")
        print("🔧 [Bộ xử lý IPA] Số lượng thông tin chữ ký: \(sinfs.count)")
        
        // 在后台队列中处理
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                let processedIPA = try self.processIPAFile(at: ipaPath, withSinfs: sinfs)
                DispatchQueue.main.async {
                    completion(.success(processedIPA))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// 处理IPA文件的核心逻辑
    private func processIPAFile(at ipaPath: URL, withSinfs sinfs: [Any]) throws -> URL {
        // 创建临时工作目录
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("IPAProcessing_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            // 清理临时目录
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        print("🔧 [Bộ xử lý IPA] Tạo thư mục làm việc tạm thời: \(tempDir.path)")
        
        // 解压IPA文件
        let extractedDir = try extractIPA(at: ipaPath, to: tempDir)
        print("🔧 [Bộ xử lý IPA] Giải nén tệp IPA đã hoàn thành: \(extractedDir.path)")
        
        // 创建SC_Info文件夹和签名文件
        try createSCInfoFolder(in: extractedDir, withSinfs: sinfs)
        print("🔧 [Bộ xử lý IPA] Tạo thư mục SC_Info đã hoàn thành")
        
        // 重新打包IPA文件
        let processedIPA = try repackIPA(from: extractedDir, originalPath: ipaPath)
        print("🔧 [Bộ xử lý IPA] đóng gói lại tệp IPA được hoàn thành: \(processedIPA.path)")
        
        return processedIPA
    }
    
    /// 解压IPA文件
    private func extractIPA(at ipaPath: URL, to tempDir: URL) throws -> URL {
        let extractedDir = tempDir.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractedDir, withIntermediateDirectories: true)
        
        // 使用ZipArchive解压IPA文件
        #if canImport(ZipArchive)
        let success = SSZipArchive.unzipFile(atPath: ipaPath.path, toDestination: extractedDir.path)
        guard success else {
            throw NSError(domain: "IPAProcessing", code: 1, userInfo: [NSLocalizedDescriptionKey: "ZipArchive không thể giải nén"])
        }
        print("🔧 [Bộ xử lý IPA] giải nén thành công các tệp IPA bằng cách sử dụng ZipArchive")
        #else
        // 如果没有ZipArchive，抛出错误
        throw NSError(domain: "IPAProcessing", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy thư viện ZipArchive, vui lòng định cấu hình chính xác sự phụ thuộc"])
        #endif
        
        return extractedDir
    }
    
    /// 创建SC_Info文件夹和签名文件
    private func createSCInfoFolder(in extractedDir: URL, withSinfs sinfs: [Any]) throws {
        // 查找Payload文件夹
        let payloadDir = extractedDir.appendingPathComponent("Payload")
        guard FileManager.default.fileExists(atPath: payloadDir.path) else {
            throw NSError(domain: "IPAProcessing", code: 2, userInfo: [NSLocalizedDescriptionKey: "Thư mục Payload không tìm thấy"])
        }
        
        // 查找.app文件夹
        let appFolders = try FileManager.default.contentsOfDirectory(at: payloadDir, includingPropertiesForKeys: nil)
        guard let appFolder = appFolders.first(where: { $0.pathExtension == "app" }) else {
            throw NSError(domain: "IPAProcessing", code: 3, userInfo: [NSLocalizedDescriptionKey: "hông tìm thấy thư mục .app"])
        }
        
        print("🔧 [Bộ xử lý IPA] Tìm thư mục ứng dụng: \(appFolder.lastPathComponent)")
        
        // 创建SC_Info文件夹
        let scInfoDir = appFolder.appendingPathComponent("SC_Info")
        try FileManager.default.createDirectory(at: scInfoDir, withIntermediateDirectories: true)
        print("🔧 [Bộ xử lý IPA] Tạo thư mục SC_Info: \(scInfoDir.path)")
        
        // 为每个sinf创建对应的.sinf文件
        print("🔧 [Bộ xử lý IPA] Bắt đầu xử lý \(sinfs.count) dữ liệu sinf")
        
        if sinfs.isEmpty {
            print("⚠️ [Bộ xử lý IPA] Không có dữ liệu sinf, hãy tạo tệp .sinf mặc định")
            // 创建默认的.sinf文件，使用应用名称作为文件名
            let appName = appFolder.lastPathComponent.replacingOccurrences(of: ".app", with: "")
            let defaultSinfFileName = "\(appName).sinf"
            let defaultSinfFilePath = scInfoDir.appendingPathComponent(defaultSinfFileName)
            
            print("🔧 [Bộ xử lý IPA] Chuẩn bị để tạo tệp sinf mặc định:")
            print("   - Tên ứng dụng: \(appName)")
            print("   - Tên tập tin: \(defaultSinfFileName)")
            print("   - Hoàn thành đường dẫn: \(defaultSinfFilePath.path)")
            
            // 创建默认的sinf数据（这是一个示例数据，实际应该从StoreItem获取）
            let defaultSinfData = createDefaultSinfData(for: appName)
            
            print("🔧 [Bộ xử lý IPA] Tạo dữ liệu sinf mặc định đã hoàn thành, kích thước: \(ByteCountFormatter().string(fromByteCount: Int64(defaultSinfData.count)))")
            
            // 写入文件
            try defaultSinfData.write(to: defaultSinfFilePath)
            
            // 验证文件是否真的被创建了
            if FileManager.default.fileExists(atPath: defaultSinfFilePath.path) {
                let fileSize = try FileManager.default.attributesOfItem(atPath: defaultSinfFilePath.path)[.size] as? Int64 ?? 0
                print("✅ [Bộ xử lý IPA] đã tạo tệp chữ ký mặc định thành công: \(defaultSinfFileName)")
                print("   - Đường dẫn tập tin: \(defaultSinfFilePath.path)")
                print("   - Kích thước tập tin: \(ByteCountFormatter().string(fromByteCount: fileSize))")
                print("   - Tệp tồn tại: ✅")
            } else {
                print("❌ [Bộ xử lý IPA] tạo tệp không thành công, tệp không tồn tại: \(defaultSinfFilePath.path)")
            }
        } else {
            for (index, sinf) in sinfs.enumerated() {
                print("🔧 [Bộ xử lý IPA] Xử lý sinf thứ \(index + 1), nhập: \(type(of: sinf))")
                
                // 处理不同类型的sinf数据
                let id: Int
                let sinfString: String
                
                if let sinfInfo = sinf as? DownloadSinfInfo {
                    // 使用本地DownloadSinfInfo类型
                    id = sinfInfo.id
                    sinfString = sinfInfo.sinf
                    print("🔧 [Bộ xử lý IPA] Sử dụng loại DownloadSinfInfo，ID: \(id)")
                } else if let sinfDict = sinf as? [String: Any],
                          let sinfId = sinfDict["id"] as? Int,
                          let sinfData = sinfDict["sinf"] as? String {
                    // 兼容字典类型
                    id = sinfId
                    sinfString = sinfData
                    print("🔧 [Bộ xử lý IPA] sử dụng các loại từ điển，ID: \(id)")
                } else {
                    print("⚠️ [Bộ xử lý IPA] Cảnh báo: Định dạng dữ liệu sinf không hợp lệ: \(type(of: sinf))")
                    print("⚠️ [Bộ xử lý IPA] nội dung sinf: \(sinf)")
                    continue
                }
                
                print("🔧 [Bộ xử lý IPA] độ dài dữ liệu sinf: \(sinfString.count) ký tự")
                
                // 使用应用名称而不是ID作为文件名
                let appName = appFolder.lastPathComponent.replacingOccurrences(of: ".app", with: "")
                let sinfFileName = "\(appName).sinf"
                let sinfFilePath = scInfoDir.appendingPathComponent(sinfFileName)
                
                // 将base64编码的sinf数据转换为二进制数据
                guard let sinfData = Data(base64Encoded: sinfString) else {
                    print("⚠️ [Bộ xử lý IPA] Cảnh báo: Không thể giải mã dữ liệu cho sinf ID \(id)")
                    print("⚠️ [Bộ xử lý IPA] Chuỗi sinf thô: \(sinfString.prefix(100))...")
                    continue
                }
                
                // 写入.sinf文件
                try sinfData.write(to: sinfFilePath)
                print("✅ [Bộ xử lý IPA] tạo thành công tệp đã ký thành công: \(sinfFileName)")
                print("   - Đường dẫn tập tin: \(sinfFilePath.path)")
                print("   - Kích thước tập tin: \(ByteCountFormatter().string(fromByteCount: Int64(sinfData.count)))")
                print("   - Độ dài dữ liệu nhị phân: \(sinfData.count) Byte")
            }
            
            print("🔧 [Bộ xử lý IPA] Đã hoàn tất xử lý tệp sinf, tổng cộng \(sinfs.count) tệp đã được xử lý")
        }
        

        
        // 创建iTunesMetadata.plist文件（在IPA根目录）
        try createiTunesMetadataPlist(in: extractedDir, appFolder: appFolder)
        print("🔧 [Bộ xử lý IPA] Tạo tệp iTunesMetadata.plist")
        
        // 强制检查：确保至少有一个.sinf文件存在
        let sinfFiles = try FileManager.default.contentsOfDirectory(at: scInfoDir, includingPropertiesForKeys: nil)
        let sinfFileCount = sinfFiles.filter { $0.pathExtension == "sinf" }.count
        
        print("🔧 [Bộ xử lý IPA] Kiểm tra cuối cùng danh mục SC_Info:")
        print("   - Đường dẫn thư mục: \(scInfoDir.path)")
        print("   - Tổng số tệp: \(sinfFiles.count)")
        print("   - Số lượng tệp .sinf: \(sinfFileCount)")
        
        if sinfFileCount == 0 {
            print("❌ [Bộ xử lý IPA] Cảnh báo: Không tìm thấy tệp .sinf!")
            print("🔧 [Bộ xử lý IPA] Buộc tạo các tệp .sinf mặc định ...")
            
            let appName = appFolder.lastPathComponent.replacingOccurrences(of: ".app", with: "")
            let defaultSinfFileName = "\(appName).sinf"
            let defaultSinfFilePath = scInfoDir.appendingPathComponent(defaultSinfFileName)
            
            let defaultSinfData = createDefaultSinfData(for: appName)
            try defaultSinfData.write(to: defaultSinfFilePath)
            
            print("✅ [Bộ xử lý IPA] Đã buộc tạo thành công tệp sinf mặc định: \(defaultSinfFileName)")
        } else {
            print("✅ [Bộ xử lý IPA] Xác nhận rằng tệp .sinf tồn tại và số: \(sinfFileCount)")
        }
    }
    
    /// 创建默认的sinf数据
    private func createDefaultSinfData(for appName: String) -> Data {
        // 创建一个基本的sinf数据结构
        // 注意：这是一个示例实现，实际的sinf数据应该从Apple Store API获取
        
        // 创建一个简单的二进制数据结构作为.sinf文件
        // 实际的.sinf文件包含加密的许可证信息，这里我们创建一个占位符
        var sinfData = Data()
        
        // 添加一个简单的头部标识
        let header = "SINF".data(using: .utf8) ?? Data()
        sinfData.append(header)
        
        // 添加版本信息
        let version: UInt32 = 1
        var versionBytes = version
        sinfData.append(Data(bytes: &versionBytes, count: MemoryLayout<UInt32>.size))
        
        // 添加应用名称
        if let appNameData = appName.data(using: .utf8) {
            let nameLength: UInt32 = UInt32(appNameData.count)
            var nameLengthBytes = nameLength
            sinfData.append(Data(bytes: &nameLengthBytes, count: MemoryLayout<UInt32>.size))
            sinfData.append(appNameData)
        }
        
        // 添加时间戳
        let timestamp: UInt64 = UInt64(Date().timeIntervalSince1970)
        var timestampBytes = timestamp
        sinfData.append(Data(bytes: &timestampBytes, count: MemoryLayout<UInt64>.size))
        
        // 添加一个简单的校验和
        let checksum = sinfData.reduce(0) { $0 ^ $1 }
        var checksumBytes = checksum
        sinfData.append(Data(bytes: &checksumBytes, count: MemoryLayout<UInt8>.size))
        
        print("🔧 [Bộ xử lý IPA] Tạo dữ liệu sinf mặc định, kích thước: \(ByteCountFormatter().string(fromByteCount: Int64(sinfData.count)))")
        
        return sinfData
    }
    

    
    /// 创建iTunesMetadata.plist文件
    private func createiTunesMetadataPlist(in extractedDir: URL, appFolder: URL) throws {
        let metadataPath = extractedDir.appendingPathComponent("iTunesMetadata.plist")
        
        // 尝试从Info.plist读取应用信息
        let infoPlistPath = appFolder.appendingPathComponent("Info.plist")
        var appInfo: [String: Any] = [:]
        
        if FileManager.default.fileExists(atPath: infoPlistPath.path) {
            do {
                let infoPlistData = try Data(contentsOf: infoPlistPath)
                if let plist = try PropertyListSerialization.propertyList(from: infoPlistData, options: [], format: nil) as? [String: Any] {
                    appInfo = plist
                }
            } catch {
                print("⚠️ [Bộ xử lý IPA] không thể đọc Info.plist: \(error)")
            }
        }
        
        // 构建iTunesMetadata.plist内容
        let metadataDict: [String: Any] = [
            "appleId": appInfo["CFBundleIdentifier"] as? String ?? "com.unknown.app",
            "artistId": 0,
            "artistName": appInfo["CFBundleDisplayName"] as? String ?? appInfo["CFBundleName"] as? String ?? "Unknown Developer",
            "bundleId": appInfo["CFBundleIdentifier"] as? String ?? "com.unknown.app",
            "bundleVersion": appInfo["CFBundleVersion"] as? String ?? "1.0",
            "copyright": appInfo["NSHumanReadableCopyright"] as? String ?? "Copyright © 2025",
            "drmVersionNumber": 0,
            "fileExtension": "ipa",
            "fileName": appFolder.lastPathComponent,
            "genre": "Productivity",
            "genreId": 6007,
            "itemId": 0,
            "itemName": appInfo["CFBundleDisplayName"] as? String ?? appInfo["CFBundleName"] as? String ?? "Unknown App",
            "kind": "software",
            "playlistName": "iOS Apps",
            "price": 0.0,
            "priceDisplay": "Free",
            "rating": "4+",
            "releaseDate": appInfo["CFBundleReleaseDate"] as? String ?? "2025-01-01T00:00:00Z",
            "s": 143441,
            "softwareIcon57x57URL": "",
            "softwareIconNeedsShine": false,
            "softwareSupportedDeviceIds": [1, 2], // iPhone and iPad
            "softwareVersionBundleId": appInfo["CFBundleIdentifier"] as? String ?? "com.unknown.app",
            "softwareVersionExternalIdentifier": 0,
            "softwareVersionExternalIdentifiers": [],
            "subgenres": [],
            "vendorId": 0,
            "versionRestrictions": 0
        ]
        
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: metadataDict,
            format: .xml,
            options: 0
        )
        
        try plistData.write(to: metadataPath)
        print("🔧 [Bộ xử lý IPA] Đã tạo thành công iTunesMetadata.plist, kích thước: \(ByteCountFormatter().string(fromByteCount: Int64(plistData.count)))")
    }
    
    /// 重新打包IPA文件
    private func repackIPA(from extractedDir: URL, originalPath: URL) throws -> URL {
        let processedIPAPath = originalPath.deletingLastPathComponent()
            .appendingPathComponent("processed_\(originalPath.lastPathComponent)")
        
        // 使用ZipArchive重新打包IPA文件
        #if canImport(ZipArchive)
        let success = SSZipArchive.createZipFile(atPath: processedIPAPath.path, withContentsOfDirectory: extractedDir.path)
        guard success else {
            throw NSError(domain: "IPAProcessing", code: 4, userInfo: [NSLocalizedDescriptionKey: "Đóng gói lại IPA không thành công"])
        }
        print("🔧 [Bộ xử lý IPA] đóng gói lại thành công các tệp IPA bằng cách sử dụng ZipArchive")
        #else
        // 如果没有ZipArchive，抛出错误
        throw NSError(domain: "IPAProcessing", code: 4, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy thư viện ZipArchive, vui lòng định cấu hình chính xác sự phụ thuộc"])
        #endif
        
        // 替换原文件
        try FileManager.default.removeItem(at: originalPath)
        try FileManager.default.moveItem(at: processedIPAPath, to: originalPath)
        
        return originalPath
    }
}
#endif
/// 用于处理IPA文件下载的下载管理器，支持进度跟踪和断点续传功能
class DownloadManager: NSObject, ObservableObject {
    static let shared = DownloadManager()
    private var downloadTasks: [String: URLSessionDownloadTask] = [:]
    private var progressHandlers: [String: (DownloadProgress) -> Void] = [:]
    private var completionHandlers: [String: (Result<DownloadResult, DownloadError>) -> Void] = [:]
    private var downloadStartTimes: [String: Date] = [:]
    private var lastProgressUpdate: [String: (bytes: Int64, time: Date)] = [:]
    private var lastUIUpdate: [String: Date] = [:]
    private var downloadDestinations: [String: URL] = [:]
    private var downloadStoreItems: [String: DownloadStoreItem] = [:]
    private lazy var urlSession: URLSession = {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 7200 // 大文件下载设置为2小时
        config.allowsCellularAccess = true
        config.waitsForConnectivity = true
        config.networkServiceType = .default
        return URLSession(configuration: config, delegate: self, delegateQueue: nil)
    }()
    private override init() {
        super.init()
    }
    /// 从iTunes商店下载一个IPA文件
    /// - 参数:
    ///   - appIdentifier: 应用标识符（应用ID）
    ///   - account: 用户账户信息
    ///   - destinationURL: 保存IPA文件的本地文件URL
    ///   - appVersion: 特定的应用版本（可选）
    ///   - progressHandler: 进度回调
    ///   - completion: 完成回调
    func downloadApp(
        appIdentifier: String,
        account: Any, // 使用 Any 类型避免编译错误
        destinationURL: URL,
        appVersion: String? = nil,
        progressHandler: @escaping (DownloadProgress) -> Void,
        completion: @escaping (Result<DownloadResult, DownloadError>) -> Void
    ) {
        let downloadId = UUID().uuidString
        print("📥 [Trình quản lý tải xuống] Bắt đầu tải xuống ứng dụng: \(appIdentifier)")
        print("📥 [Trình quản lý tải xuống] ID tải xuống: \(downloadId)")
        print("📥 [Trình quản lý tải xuống] Đường dẫn đích: \(destinationURL.path)")
        print("📥 [Trình quản lý tải xuống] Phiên bản ứng dụng: \(appVersion ?? "Phiên bản mới nhất")")
        print("📥 [Trình quản lý tải xuống] Thông tin tài khoản: Đối tượng tài khoản đã được chuyển")
        Task {
            do {
                print("🔍 [Trình quản lý tải xuống] Đang truy xuất thông tin tải xuống...")
                // 首先从商店API获取下载信息
                // 使用反射获取 account 的各个字段
                let mirror = Mirror(reflecting: account)
                var dsPersonId = ""
                var passwordToken = ""
                var storeFront = ""
                
                for child in mirror.children {
                    if let label = child.label {
                        switch label {
                        case "dsPersonId":
                            dsPersonId = child.value as? String ?? ""
                        case "passwordToken":
                            passwordToken = child.value as? String ?? ""
                        case "storeResponse":
                            // 获取 storeFront
                            let storeResponseMirror = Mirror(reflecting: child.value)
                            for storeChild in storeResponseMirror.children {
                                if storeChild.label == "storeFront" {
                                    storeFront = storeChild.value as? String ?? ""
                                    break
                                }
                            }
                        default:
                            break
                        }
                    }
                }
                
                print("🔍 [Thông tin tài khoản] dsPersonId: \(dsPersonId)")
                print("🔍 [Thông tin tài khoản] passwordToken: \(passwordToken.isEmpty ? "vô giá trị" : "Đã mua lại")")
                print("🔍 [Thông tin tài khoản] storeFront: \(storeFront)")
                
                // 直接调用下载API，获取真实的 sinf 数据，包含认证信息
                let plistResponse = try await downloadFromStoreAPI(
                    appIdentifier: appIdentifier,
                    directoryServicesIdentifier: dsPersonId,
                    appVersion: appVersion,
                    passwordToken: passwordToken,
                    storeFront: storeFront
                )
                
                // 解析 songList
                guard let songList = plistResponse["songList"] as? [[String: Any]], !songList.isEmpty else {
                    let error: DownloadError = .unknownError("Không thể lấy thông tin tải xuống")
                    DispatchQueue.main.async {
                        completion(.failure(error))
                    }
                    return
                }
                
                let firstSongItem = songList[0]
                print("✅ [Trình quản lý tải xuống] Đã tải thông tin thành công")
                print("   - Tải xuống URL: \(firstSongItem["URL"] as? String ?? "không xác định")")
                print("   - MD5: \(firstSongItem["md5"] as? String ?? "không xác định")")
                
                // 检查真实的 sinf 数据
                if let sinfs = firstSongItem["sinfs"] as? [[String: Any]] {
                    print("   - Số Sinf thực: \(sinfs.count)")
                    for (index, sinf) in sinfs.enumerated() {
                        if let sinfData = sinf["sinf"] as? String {
                            print("   - Sinf \(index + 1): chiều dài \(sinfData.count) Ký tự (dữ liệu thực)")
                        }
                    }
                } else {
                    print("   - Cảnh báo: Không tìm thấy dữ liệu sinf")
                }
                
                // 将响应数据转换为DownloadStoreItem，确保使用真实的 sinf 数据
                let downloadStoreItem = convertToDownloadStoreItem(from: firstSongItem)
                
                // 开始实际的文件下载
                await startFileDownload(
                    storeItem: downloadStoreItem,
                    destinationURL: destinationURL,
                    progressHandler: progressHandler,
                    completion: completion
                )
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.networkError(error)))
                }
            }
        }
    }
    /// 恢复已暂停的下载
    /// - 参数:
    ///   - downloadId: 下载标识符
    ///   - progressHandler: 进度回调
    ///   - completion: 完成回调
    func resumeDownload(
        downloadId: String,
        progressHandler: @escaping (DownloadProgress) -> Void,
        completion: @escaping (Result<DownloadResult, DownloadError>) -> Void
    ) {
        guard let task = downloadTasks[downloadId] else {
            completion(.failure(.downloadNotFound("Không tìm thấy tác vụ tải xuống")))
            return
        }
        progressHandlers[downloadId] = progressHandler
        completionHandlers[downloadId] = completion
        task.resume()
    }
    /// 暂停一个下载
    /// - 参数:
    ///   - downloadId: 下载标识符
    func pauseDownload(downloadId: String) {
        downloadTasks[downloadId]?.suspend()
    }
    /// 取消一个下载
    /// - 参数:
    ///   - downloadId: 下载标识符
    func cancelDownload(downloadId: String) {
        downloadTasks[downloadId]?.cancel()
        cleanupDownload(downloadId: downloadId)
    }
    /// 获取当前下载进度
    /// - 参数:
    ///   - downloadId: 下载标识符
    /// - 返回: 当前进度，如果未找到下载则返回nil
    func getDownloadProgress(downloadId: String) -> DownloadProgress? {
        guard let task = downloadTasks[downloadId] else { return nil }
        return DownloadProgress(
            downloadId: downloadId,
            bytesDownloaded: task.countOfBytesReceived,
            totalBytes: task.countOfBytesExpectedToReceive,
            progress: task.countOfBytesExpectedToReceive > 0 ? 
                Double(task.countOfBytesReceived) / Double(task.countOfBytesExpectedToReceive) : 0.0,
            speed: 0, // 需要根据时间计算
            remainingTime: 0, // 需要计算
            status: task.state == .running ? .downloading : 
                   task.state == .suspended ? .paused : .completed
        )
    }
    
    /// 将StoreItem转换为DownloadStoreItem，确保使用真实的 sinf 数据
    private func convertToDownloadStoreItem(from storeItem: Any) -> DownloadStoreItem {
        print("🔍 [Bắt đầu chuyển đổi] Bắt đầu phân tích dữ liệu StoreItem")
        print("🔍 [Bắt đầu chuyển đổi] Loại StoreItem: \(type(of: storeItem))")
        
        // 检查是否是字典类型
        if let dict = storeItem as? [String: Any] {
            print("🔍 [Bắt đầu chuyển đổi] Đã phát hiện loại từ điển, truy cập trực tiếp vào các giá trị khóa")
            
            // 直接访问字典键值
            let url = dict["URL"] as? String ?? ""
            let md5 = dict["md5"] as? String ?? ""
            
            print("🔍 [Bắt đầu chuyển đổi] Lấy từ từ điển:")
            print("   - URL: \(url.isEmpty ? "vô giá trị" : "Thu được(\(url.count)ký tự)")")
            print("   - MD5: \(md5.isEmpty ? "vô giá trị" : "Thu được(\(md5.count)ký tự)")")
            
            // 获取元数据
            var bundleId = "unknown"
            var bundleDisplayName = "Unknown App"
            var bundleShortVersionString = "1.0"
            var softwareVersionExternalIdentifier = "0"
            var softwareVersionExternalIdentifiers: [Int] = []
            
            if let metadata = dict["metadata"] as? [String: Any] {
                bundleId = metadata["softwareVersionBundleId"] as? String ?? "unknown"
                bundleDisplayName = metadata["bundleDisplayName"] as? String ?? "Unknown App"
                bundleShortVersionString = metadata["bundleShortVersionString"] as? String ?? "1.0"
                if let extId = metadata["softwareVersionExternalIdentifier"] as? Int {
                    softwareVersionExternalIdentifier = String(extId)
                }
                softwareVersionExternalIdentifiers = metadata["softwareVersionExternalIdentifiers"] as? [Int] ?? []
                
                print("🔍 [Bắt đầu chuyển đổi] Lấy từ metadata:")
                print("   - Bundle ID: \(bundleId)")
                print("   - Display Name: \(bundleDisplayName)")
                print("   - Version: \(bundleShortVersionString)")
                print("   - External ID: \(softwareVersionExternalIdentifier)")
            }
            
            // 获取真实的 sinf 数据
            var sinfs: [DownloadSinfInfo] = []
            if let sinfsArray = dict["sinfs"] as? [[String: Any]] {
                print("🔍 [Chuyển đổi bắt đầu] Đã tìm thấy mảng sinfs, độ dài: \(sinfsArray.count)")
                
                for (index, sinfDict) in sinfsArray.enumerated() {
                    print("🔍 [Bắt đầu chuyển đổi] Phân tích cú pháp Sinf \(index + 1):")
                    
                    // 获取 sinf ID
                    let sinfId = sinfDict["id"] as? Int ?? index
                    print("   - ID: \(sinfId)")
                    
                    // 获取 sinf 数据 - 修复类型处理问题
                    if let sinfData = sinfDict["sinf"] {
                        print("   - Kiểu dữ liệu sinf: \(type(of: sinfData))")
                        
                        var finalSinfData: String = ""
                        
                        // 处理不同类型的 sinf 数据
                        if let stringData = sinfData as? String {
                            finalSinfData = stringData
                            print("   - Loại chuỗi dữ liệu sinf, độ dài: \(stringData.count)")
                        } else if let dataData = sinfData as? Data {
                            finalSinfData = dataData.base64EncodedString()
                            print("   - Kiểu dữ liệu sinf data, chuyển đổi sang base64, độ dài: \(finalSinfData.count)")
                        } else {
                            // 尝试转换为字符串
                            finalSinfData = "\(sinfData)"
                            print("   - Các loại dữ liệu sinf khác, được chuyển đổi thành chuỗi, độ dài: \(finalSinfData.count)")
                        }
                        
                        // 验证数据有效性
                        if !finalSinfData.isEmpty && finalSinfData.count > 10 {
                            let sinfInfo = DownloadSinfInfo(
                                id: sinfId,
                                sinf: finalSinfData
                            )
                            sinfs.append(sinfInfo)
                            print("✅ [Bắt đầu chuyển đổi] Đã thêm thành công Sinf \(index + 1)，ID: \(sinfId)，Độ dài dữ liệu: \(finalSinfData.count)")
                        } else {
                            print("⚠️ [Chuyển đổi bắt đầu] Dữ liệu Sinf \(index + 1) không hợp lệ, bỏ qua")
                        }
                    } else {
                        print("⚠️ [Bắt đầu chuyển đổi] Sinf \(index + 1) Không có trường sinf")
                    }
                }
            } else {
                print("⚠️ [Chuyển đổi bắt đầu] Không tìm thấy mảng Sinfs hoặc lỗi định dạng")
            }
            
            // 验证必要字段
            guard !url.isEmpty && !md5.isEmpty else {
                print("❌ [Chuyển đổi không thành công] Không thể lấy được URL hoặc MD5")
                print("🔍 [Bắt đầu chuyển đổi] Nội dung từ điển: \(dict)")
                return createDefaultDownloadStoreItem()
            }
            
            let downloadMetadata = DownloadAppMetadata(
                bundleId: bundleId,
                bundleDisplayName: bundleDisplayName,
                bundleShortVersionString: bundleShortVersionString,
                softwareVersionExternalIdentifier: softwareVersionExternalIdentifier,
                softwareVersionExternalIdentifiers: softwareVersionExternalIdentifiers
            )
            
            print("✅ [Chuyển đổi thành công] Đã phân tích thành dữ liệu sau:")
            print("   - URL: \(url)")
            print("   - MD5: \(md5)")
            print("   - Bundle ID: \(bundleId)")
            print("   - Display Name: \(bundleDisplayName)")
            print("   - Số lượng sinf thực sự: \(sinfs.count)")
            
            print("✅ [Chuyển đổi hoàn tất] Đã tạo thành công DownloadStoreItem, chứa dữ liệu chữ ký ID Apple thực")
            return DownloadStoreItem(
                url: url,
                md5: md5,
                sinfs: sinfs,
                metadata: downloadMetadata
            )
        } else {
            print("❌ [Chuyển đổi thất bại] StoreItem không phải là loại từ điển")
            return createDefaultDownloadStoreItem()
        }
    }
    
    /// 创建默认的DownloadStoreItem（用于错误情况）
    private func createDefaultDownloadStoreItem() -> DownloadStoreItem {
        return DownloadStoreItem(
            url: "",
            md5: "",
            sinfs: [],
            metadata: DownloadAppMetadata(
                bundleId: "unknown",
                bundleDisplayName: "Unknown App",
                bundleShortVersionString: "1.0",
                softwareVersionExternalIdentifier: "0",
                softwareVersionExternalIdentifiers: []
            )
        )
    }
    
    /// 开始实际的文件下载
    private func startFileDownload(
        storeItem: DownloadStoreItem,
        destinationURL: URL,
        progressHandler: @escaping (DownloadProgress) -> Void,
        completion: @escaping (Result<DownloadResult, DownloadError>) -> Void
    ) async {
        guard let downloadURL = URL(string: storeItem.url) else {
            DispatchQueue.main.async {
                completion(.failure(.invalidURL("URL tải xuống không hợp lệ: \(storeItem.url)")))
            }
            return
        }
        print("🚀 [Tải xuống bắt đầu] URL: \(downloadURL.absoluteString)")
        let downloadId = UUID().uuidString
        var request = URLRequest(url: downloadURL)
        // 添加必要的请求头以确保下载稳定性
        request.setValue("bytes=0-", forHTTPHeaderField: "Range")
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        request.setValue("gzip, deflate, br", forHTTPHeaderField: "Accept-Encoding")
        request.setValue("*/*", forHTTPHeaderField: "Accept")
        let downloadTask = urlSession.downloadTask(with: request)
        // 记录下载开始时间和目标URL
        downloadStartTimes[downloadId] = Date()
        downloadTasks[downloadId] = downloadTask
        progressHandlers[downloadId] = progressHandler
        // 存储目标URL和转换后的downloadStoreItem信息，供delegate使用
        downloadDestinations[downloadId] = destinationURL
        downloadStoreItems[downloadId] = storeItem // 这里存储的是转换后的DownloadStoreItem
        completionHandlers[downloadId] = completion
        print("📥 [Tải xuống nhiệm vụ] ID: \(downloadId) đã được tạo và bắt đầu")
        downloadTask.resume()
    }
    /// 验证下载文件的完整性
    private func verifyFileIntegrity(fileURL: URL, expectedMD5: String) -> Bool {
        guard let fileData = try? Data(contentsOf: fileURL) else {
            return false
        }
        let digest = Insecure.MD5.hash(data: fileData)
        let calculatedMD5 = digest.map { String(format: "%02hhx", $0) }.joined()
        return calculatedMD5.lowercased() == expectedMD5.lowercased()
    }
    /// 清理下载资源
    private func cleanupDownload(downloadId: String) {
        downloadTasks.removeValue(forKey: downloadId)
        progressHandlers.removeValue(forKey: downloadId)
        completionHandlers.removeValue(forKey: downloadId)
        downloadStartTimes.removeValue(forKey: downloadId)
        lastProgressUpdate.removeValue(forKey: downloadId)
        lastUIUpdate.removeValue(forKey: downloadId)
        downloadDestinations.removeValue(forKey: downloadId)
        downloadStoreItems.removeValue(forKey: downloadId)
        print("🧹 [Hoàn tất dọn dẹp] Tất cả tài nguyên của tác vụ tải xuống \(downloadId) đã được dọn dẹp")
    }
    /// 从Apple Store API获取真实的下载信息，包含真实的 sinf 数据
    private func downloadFromStoreAPI(
        appIdentifier: String,
        directoryServicesIdentifier: String,
        appVersion: String?,
        passwordToken: String,
        storeFront: String
    ) async throws -> [String: Any] {
        print("🔍 [Store API] Bắt đầu nhận thông tin tải xuống thực tế...")
        
        // 构建请求URL
        let guid = generateGUID()
        let url = URL(string: "https://p25-buy.itunes.apple.com/WebObjects/MZFinance.woa/wa/volumeStoreDownloadProduct?guid=\(guid)")!
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-apple-plist", forHTTPHeaderField: "Content-Type")
        request.setValue("Configurator/2.15 (Macintosh; OS X 11.0.0; 16G29) AppleWebKit/2603.3.8", forHTTPHeaderField: "User-Agent")
        request.setValue(directoryServicesIdentifier, forHTTPHeaderField: "X-Dsid")
        request.setValue(directoryServicesIdentifier, forHTTPHeaderField: "iCloud-DSID")
        
        // 添加认证头，确保获取真实的 sinf 数据
        if !passwordToken.isEmpty {
            request.setValue(passwordToken, forHTTPHeaderField: "X-Token")
        }
        if !storeFront.isEmpty {
            request.setValue(storeFront, forHTTPHeaderField: "X-Apple-Store-Front")
        }
        
        // 构建请求体
        var body: [String: Any] = [
            "creditDisplay": "",
            "guid": guid,
            "salableAdamId": appIdentifier
        ]
        
        if let appVersion = appVersion {
            body["externalVersionId"] = appVersion
        }
        
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: body,
            format: .xml,
            options: 0
        )
        request.httpBody = plistData
        
        print("🔍 [Store API] Gửi yêu cầu đến: \(url.absoluteString)")
        print("🔍 [Store API] Request Body: \(body)")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw DownloadError.networkError(NSError(domain: "StoreAPI", code: -1, userInfo: [NSLocalizedDescriptionKey: "Phản hồi HTTP không hợp lệ"]))
        }
        
        print("🔍 [Store API] Mã trạng thái phản hồi: \(httpResponse.statusCode)")
        
        if httpResponse.statusCode != 200 {
            let errorMessage = String(data: data, encoding: .utf8) ?? "Lỗi không xác định"
            print("❌ [Store API] Yêu cầu không thành công: \(errorMessage)")
            throw DownloadError.networkError(NSError(domain: "StoreAPI", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorMessage]))
        }
        
        // 解析响应
        let plist = try PropertyListSerialization.propertyList(
            from: data,
            options: [],
            format: nil
        ) as? [String: Any] ?? [:]
        
        print("🔍 [Store API] Phản hồi chứa khóa: \(Array(plist.keys).sorted())")
        
        // 详细调试：检查 songList 结构
        if let songList = plist["songList"] as? [[String: Any]], !songList.isEmpty {
            print("🔍 [Store API] Đã tìm thấy songList, chứa \(songList.count) mục")
            
            let firstSong = songList[0]
            print("🔍 [Store API] Khóa của song đầu tiên: \(Array(firstSong.keys).sorted())")
            
            // 检查 sinfs 字段
            if let sinfs = firstSong["sinfs"] as? [[String: Any]], !sinfs.isEmpty {
                print("✅ [Store API] Đã thu thập thành công dữ liệu sinf thực, số lượng: \(sinfs.count)")
                for (index, sinf) in sinfs.enumerated() {
                    print("🔍 [Store API] Sinf \(index + 1) key: \(Array(sinf.keys).sorted())")
                    if let sinfData = sinf["sinf"] as? String {
                        print("🔍 [Store API] Sinf \(index + 1): chiều dài \(sinfData.count) ký tự")
                        print("🔍 [Store API] Sinf \(index + 1) 100 ký tự đầu tiên: \(String(sinfData.prefix(100)))")
                    } else {
                        print("⚠️ [Store API] Sinf \(index + 1): Lỗi loại trường sinf: \(type(of: sinf["sinf"]))")
                    }
                }
            } else {
                print("⚠️ [Store API] Dữ liệu Sinf không tìm thấy")
                print("🔍 [Store API] Loại trường Sinfs: \(type(of: firstSong["sinfs"]))")
                if let sinfsRaw = firstSong["sinfs"] {
                    print("🔍 [Store API] sinfs giá trị ban đầu: \(sinfsRaw)")
                }
            }
            
            // 检查其他重要字段
            print("🔍 [Store API] Trường URL: \(firstSong["URL"] ?? "không tìm thấy")")
            print("🔍 [Store API] Trường MD5: \(firstSong["md5"] ?? "không tìm thấy")")
            print("🔍 [Store API] Trường metadata: \(type(of: firstSong["metadata"]))")
            
            if let metadata = firstSong["metadata"] as? [String: Any] {
                print("🔍 [Store API] Khóa metadata: \(Array(metadata.keys).sorted())")
            }
        } else {
            print("⚠️ [Store API] songList là định dạng trống hoặc không chính xác")
            print("🔍 [Store API] songList kiểu: \(type(of: plist["songList"]))")
        }
        
        // 返回原始 plist 数据
        return plist
    }
    

    
    /// 生成GUID
    private func generateGUID() -> String {
        return UUID().uuidString.replacingOccurrences(of: "-", with: "").prefix(12).uppercased()
    }
    
    /// 将商店API错误映射为DownloadError
    private func mapStoreError(_ failureType: String, customerMessage: String?) -> DownloadError {
        switch failureType {
        case "INVALID_ITEM":
            return .appNotFound(customerMessage ?? "Không tìm thấy ứng dụng")
        case "INVALID_LICENSE":
            return .licenseError(customerMessage ?? "Giấy phép không hợp lệ")
        case "INVALID_CREDENTIALS":
            return .authenticationError(customerMessage ?? "Xác thực thất bại")
        default:
            return .unknownError(customerMessage ?? "Lỗi không xác định")
        }
    }
}
// MARK: - URLSessionDownloadDelegate
extension DownloadManager: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // 查找此任务的下载ID
        guard let downloadId = downloadTasks.first(where: { $0.value == downloadTask })?.key,
              let completion = completionHandlers[downloadId],
              let destinationURL = downloadDestinations[downloadId],
              let storeItem = downloadStoreItems[downloadId] else {
            print("❌ [Tải xuống hoàn tất] Không tìm thấy ID tác vụ tải xuống, trình xử lý hoàn tất, URL đích hoặc storeItem")
            return
        }
        print("📁 [Tệp tạm thời] Tải xuống hoàn tất, vị trí tệp tạm thời: \(location.path)")
        print("📂 [Vị trí đích] sẽ được chuyển đến: \(destinationURL.path)")
        // 检查临时文件是否存在
        guard FileManager.default.fileExists(atPath: location.path) else {
            print("❌ [Tệp tạm thời] Tệp không tồn tại: \(location.path)")
            DispatchQueue.main.async {
                completion(.failure(.fileSystemError("Tệp tải xuống tạm thời không tồn tại")))
            }
            cleanupDownload(downloadId: downloadId)
            return
        }
        // 立即移动文件到目标位置
        do {
            // 确保目标目录存在
            let targetDirectory = destinationURL.deletingLastPathComponent()
            if !FileManager.default.fileExists(atPath: targetDirectory.path) {
                try FileManager.default.createDirectory(at: targetDirectory, withIntermediateDirectories: true, attributes: nil)
                print("📁 [Tạo danh mục] Thư mục đích đã được tạo: \(targetDirectory.path)")
            }
            // 如果目标文件已存在，先删除
            if FileManager.default.fileExists(atPath: destinationURL.path) {
                try FileManager.default.removeItem(at: destinationURL)
                print("🗑️ [Dọn dẹp tệp] Các tệp hiện có đã bị xóa: \(destinationURL.path)")
            }
            // 移动文件
            try FileManager.default.moveItem(at: location, to: destinationURL)
            print("✅ [Di chuyển tệp] Đã di chuyển thành công đến: \(destinationURL.path)")
            // 创建包含完整信息的结果
            let result = DownloadResult(
                downloadId: downloadId,
                fileURL: destinationURL,
                fileSize: downloadTask.countOfBytesReceived,
                metadata: DownloadAppMetadata(
                    bundleId: storeItem.metadata.bundleId,
                    bundleDisplayName: storeItem.metadata.bundleDisplayName,
                    bundleShortVersionString: storeItem.metadata.bundleShortVersionString,
                    softwareVersionExternalIdentifier: storeItem.metadata.softwareVersionExternalIdentifier,
                    softwareVersionExternalIdentifiers: storeItem.metadata.softwareVersionExternalIdentifiers
                ),
                sinfs: storeItem.sinfs,
                expectedMD5: storeItem.md5
            )
            print("✅ [Tải xuống hoàn thành] Kích thước tệp: \(ByteCountFormatter().string(fromByteCount: downloadTask.countOfBytesReceived))")
            
            // 处理IPA文件，添加SC_Info文件夹和签名信息
            print("🔧 [Tải xuống hoàn thành] Bắt đầu xử lý các tệp IPA ...")
            print("🔧 [Tải xuống hoàn tất] Số lượng thông tin chữ ký: \(storeItem.sinfs.count)")
            
            // 调试：检查storeItem的详细信息
            print("🔍 [gỡ lỗi] chi tiết storeItem:")
            print("   - URL: \(storeItem.url)")
            print("   - MD5: \(storeItem.md5)")
            print("   - Bundle ID: \(storeItem.metadata.bundleId)")
            print("   - Display Name: \(storeItem.metadata.bundleDisplayName)")
            print("   - Version: \(storeItem.metadata.bundleShortVersionString)")
            print("   - Số lượng Sinf: \(storeItem.sinfs.count)")
            
            for (index, sinf) in storeItem.sinfs.enumerated() {
                print("   - Sinf \(index + 1): ID=\(sinf.id), Độ dài dữ liệu =\(sinf.sinf.count)")
            }
            
            // 无论是否有签名信息，都要处理IPA文件，确保创建.sinf文件
            print("🔧 [Tải xuống hoàn tất] Bắt đầu xử lý tệp IPA, đảm bảo các tệp chữ ký cần thiết được tạo...")
            print("🔧 [Tải xuống hoàn thành] Số lượng thông tin chữ ký: \(storeItem.sinfs.count)")
            
            IPAProcessor.shared.processIPA(at: destinationURL, withSinfs: storeItem.sinfs) { processingResult in
                switch processingResult {
                case .success(let processedIPA):
                    print("✅ [Xử lý IPA] Đã xử lý thành công tệp IPA: \(processedIPA.path)")
                    
                    // 添加iTunesMetadata.plist
                    Task {
                        do {
                            print("🔧 [Xử lý siêu dữ liệu] Bắt đầu thêm iTunesMetadata.plist vào IPA ...")
                            // 安全解包metadata
                            guard let metadata = result.metadata else {
                                print("❌ [Xử lý metadata] metadata trống, không thể tạo iTunesMetadata.plist")
                                DispatchQueue.main.async {
                                    completion(.success(result))
                                }
                                return
                            }
                            
                            print("🔧 [Xử lý metadata] Thông tin metadata:")
                            print("   - Bundle ID: \(metadata.bundleId)")
                            print("   - Display Name: \(metadata.bundleDisplayName)")
                            print("   - Version: \(metadata.bundleShortVersionString)")
                            
                            // 直接生成iTunesMetadata.plist
                            let finalIPA = try await self.generateiTunesMetadata(
                                for: processedIPA.path,
                                bundleId: metadata.bundleId,
                                displayName: metadata.bundleDisplayName,
                                version: metadata.bundleShortVersionString,
                                externalVersionId: Int(metadata.softwareVersionExternalIdentifier) ?? 0,
                                externalVersionIds: metadata.softwareVersionExternalIdentifiers
                            )
                            
                            print("✅ [Xử lý metadata] Đã tạo thành công iTunesMetadata.plist và cuối cùng là IPA: \(finalIPA)")
                            
                            DispatchQueue.main.async {
                                completion(.success(result))
                            }
                        } catch {
                            print("❌ [Xử lý metadata] Không tạo được iTunesMetadata.plist: \(error)")
                            DispatchQueue.main.async {
                                completion(.success(result))
                            }
                        }
                    }
                case .failure(let error):
                    print("❌ [Xử lý IPA] Xử lý không thành công: \(error.localizedDescription)")
                    // 即使处理失败，也返回下载结果，但记录错误
                    DispatchQueue.main.async {
                        completion(.success(result))
                    }
                }
            }
        } catch {
            print("❌ [Di chuyển tệp không thành công] \(error.localizedDescription)")
            DispatchQueue.main.async {
                completion(.failure(.fileSystemError("Di chuyển tệp không thành công: \(error.localizedDescription)")))
            }
        }
        cleanupDownload(downloadId: downloadId)
    }
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        // 查找此任务的下载ID
        guard let downloadId = downloadTasks.first(where: { $0.value == downloadTask })?.key,
              let progressHandler = progressHandlers[downloadId],
              let startTime = downloadStartTimes[downloadId] else {
            return
        }
        let currentTime = Date()
        // 计算下载速度
        var speed: Double = 0.0
        var remainingTime: TimeInterval = 0.0
        if let lastUpdate = lastProgressUpdate[downloadId] {
            let timeDiff = currentTime.timeIntervalSince(lastUpdate.time)
            if timeDiff > 0 {
                let bytesDiff = totalBytesWritten - lastUpdate.bytes
                speed = Double(bytesDiff) / timeDiff
            }
        } else {
            // 首次更新，使用总体平均速度
            let totalTime = currentTime.timeIntervalSince(startTime)
            if totalTime > 0 {
                speed = Double(totalBytesWritten) / totalTime
            }
        }
        // 计算剩余时间
        if speed > 0 && totalBytesExpectedToWrite > totalBytesWritten {
            let remainingBytes = totalBytesExpectedToWrite - totalBytesWritten
            remainingTime = Double(remainingBytes) / speed
        }
        let progressValue = totalBytesExpectedToWrite > 0 ? 
            Double(totalBytesWritten) / Double(totalBytesExpectedToWrite) : 0.0
        let progress = DownloadProgress(
            downloadId: downloadId,
            bytesDownloaded: totalBytesWritten,
            totalBytes: totalBytesExpectedToWrite,
            progress: progressValue,
            speed: speed,
            remainingTime: remainingTime,
            status: .downloading
        )
        // 修复UI更新频率控制逻辑，确保进度实时更新
        let lastUIUpdateTime = lastUIUpdate[downloadId] ?? Date.distantPast
        let shouldUpdate = currentTime.timeIntervalSince(lastUIUpdateTime) >= 0.1 || progressValue >= 1.0
        // 更新进度记录（在UI更新判断之后）
        lastProgressUpdate[downloadId] = (bytes: totalBytesWritten, time: currentTime)
        if shouldUpdate {
            lastUIUpdate[downloadId] = currentTime
            DispatchQueue.main.async {
                progressHandler(progress)
            }
        }
    }
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let downloadTask = task as? URLSessionDownloadTask,
              let downloadId = downloadTasks.first(where: { $0.value == downloadTask })?.key,
              let completion = completionHandlers[downloadId] else {
            return
        }
        if let error = error {
            DispatchQueue.main.async {
                completion(.failure(.networkError(error)))
            }
        }
        cleanupDownload(downloadId: downloadId)
    }
}
// MARK: - 下载模型
/// 下载状态
enum DownloadStatus: String, Codable {
    case waiting
    case downloading
    case paused
    case completed
    case failed
    case cancelled
}

/// 下载进度信息
struct DownloadProgress {
    let downloadId: String
    let bytesDownloaded: Int64
    let totalBytes: Int64
    let progress: Double // 0.0 到 1.0
    let speed: Double // 字节/秒
    let remainingTime: TimeInterval // 秒
    let status: DownloadStatus
    var formattedProgress: String {
        return String(format: "%.1f%%", progress * 100)
    }
    var formattedSize: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: bytesDownloaded)) / \(formatter.string(fromByteCount: totalBytes))"
    }
    var formattedSpeed: String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return "\(formatter.string(fromByteCount: Int64(speed)))/s"
    }
    var formattedRemainingTime: String {
        if remainingTime <= 0 {
            return "--:--"
        }
        let hours = Int(remainingTime) / 3600
        let minutes = (Int(remainingTime) % 3600) / 60
        let seconds = Int(remainingTime) % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%02d:%02d", minutes, seconds)
        }
    }
}

/// 下载结果
struct DownloadResult {
    let downloadId: String
    let fileURL: URL
    let fileSize: Int64
    var metadata: DownloadAppMetadata?
    var sinfs: [DownloadSinfInfo]?
    var expectedMD5: String?
    var isIntegrityValid: Bool {
        guard let expectedMD5 = expectedMD5,
              let fileData = try? Data(contentsOf: fileURL) else {
            return false
        }
        let digest = Insecure.MD5.hash(data: fileData)
        let calculatedMD5 = digest.map { String(format: "%02hhx", $0) }.joined()
        return calculatedMD5.lowercased() == expectedMD5.lowercased()
    }
}
// 数据模型现已统一在StoreClient.swift中
/// 下载特定的错误
enum DownloadError: LocalizedError {
    case invalidURL(String)
    case appNotFound(String)
    case licenseError(String)
    case authenticationError(String)
    case downloadNotFound(String)
    case fileSystemError(String)
    case integrityCheckFailed(String)
    case licenseCheckFailed(String)
    case networkError(Error)
    case unknownError(String)
    var errorDescription: String? {
        switch self {
        case .invalidURL(let message):
            return "URL không hợp lệ: \(message)"
        case .appNotFound(let message):
            return "Không tìm thấy ứng dụng: \(message)"
        case .licenseError(let message):
            return "Lỗi giấy phép: \(message)"
        case .authenticationError(let message):
            return "Lỗi xác thực: \(message)"
        case .downloadNotFound(let message):
            return "Không tìm thấy tải xuống: \(message)"
        case .fileSystemError(let message):
            return "Lỗi hệ thống tệp: \(message)"
        case .integrityCheckFailed(let message):
            return "Kiểm tra tính toàn vẹn không thành công: \(message)"
        case .licenseCheckFailed(let message):
            return "Kiểm tra giấy phép không thành công: \(message)"
        case .networkError(let error):
            return "Lỗi mạng: \(error.localizedDescription)"
        case .unknownError(let message):
            return "Lỗi không xác định: \(message)"
        }
    }
}



// MARK: - 下载请求模型
/// 下载请求模型
struct UnifiedDownloadRequest: Identifiable, Codable {
    let id: String
    let bundleIdentifier: String
    let name: String
    let version: String
    let identifier: String
    let iconURL: String?
    let versionId: String?
    var status: DownloadStatus
    var progress: Double
    let createdAt: Date
    var completedAt: Date?
    var filePath: String?
    var errorMessage: String?
    
    var isCompleted: Bool {
        return status == .completed
    }
    
    var isFailed: Bool {
        return status == .failed
    }
    
    var isDownloading: Bool {
        return status == .downloading
    }
    
    var isPaused: Bool {
        return status == .paused
    }
}

// MARK: - iTunesMetadata生成方法
extension DownloadManager {
    /// 使用ZipArchive处理IPA文件
    private func processIPAWithZipArchive(
        at ipaPath: String,
        appInfo: DownloadAppMetadata
    ) async throws -> String {
        print("🔧 [ZipArchive] Bắt đầu xử lý các tệp IPA: \(ipaPath)")
        print("🔧 [ZipArchive] Thông tin ứng dụng:")
        print("   - Bundle ID: \(appInfo.bundleId)")
        print("   - Display Name: \(appInfo.bundleDisplayName)")
        print("   - Version: \(appInfo.bundleShortVersionString)")
        
        // 创建临时工作目录
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("IPAProcessing_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        print("🔧 [ZipArchive] Tạo một thư mục tạm thời: \(tempDir.path)")
        
        defer {
            // 清理临时目录
            try? FileManager.default.removeItem(at: tempDir)
            print("🧹 [ZipArchive] Dọn dẹp các thư mục tạm thời: \(tempDir.path)")
        }
        
        let extractedDir = tempDir.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractedDir, withIntermediateDirectories: true)
        print("🔧 [ZipArchive] Tạo một thư mục không được giải nén: \(extractedDir.path)")
        
        // 使用ZipArchive解压IPA文件
        #if canImport(ZipArchive)
        print("🔧 [ZipArchive] Bắt đầu giải nén tệp IPA ...")
        
        let success = SSZipArchive.unzipFile(atPath: ipaPath, toDestination: extractedDir.path)
        guard success else {
            throw NSError(domain: "ZipArchiveProcessing", code: 1, userInfo: [NSLocalizedDescriptionKey: "Giải nén IPA không thành công"])
        }
        print("✅ [ZipArchive] Tệp IPA được giải nén thành công")
        
        // 创建iTunesMetadata.plist
        print("🔧 [ZipArchive] Bắt đầu tạo iTunesMetadata.plist...")
        try createiTunesMetadataPlist(in: extractedDir, appInfo: appInfo)
        print("🔧 [ZipArchive] Tạo thành công iTunesMetadata.plist")
        
        // 重新打包IPA文件
        print("🔧 [ZipArchive] Bắt đầu đóng gói lại các tệp IPA ...")
        let processedIPAPath = URL(fileURLWithPath: ipaPath).deletingLastPathComponent()
            .appendingPathComponent("processed_\(URL(fileURLWithPath: ipaPath).lastPathComponent)")
        
        let repackSuccess = SSZipArchive.createZipFile(atPath: processedIPAPath.path, withContentsOfDirectory: extractedDir.path)
        guard repackSuccess else {
            throw NSError(domain: "ZipArchiveProcessing", code: 2, userInfo: [NSLocalizedDescriptionKey: "Đóng gói lại IPA không thành công"])
        }
        print("✅ [ZipArchive] Tệp IPA đóng gói lại thành công")
        
        // 验证处理后的文件是否存在
        guard FileManager.default.fileExists(atPath: processedIPAPath.path) else {
            throw NSError(domain: "ZipArchiveProcessing", code: 3, userInfo: [NSLocalizedDescriptionKey: "Tệp IPA đã xử lý không tồn tại"])
        }
        
        // 获取文件大小
        let fileSize = try FileManager.default.attributesOfItem(atPath: processedIPAPath.path)[.size] as? Int64 ?? 0
        print("✅ [ZipArchive] Kích thước tệp IPA đã xử lý: \(ByteCountFormatter().string(fromByteCount: fileSize))")
        
        // 替换原文件
        print("🔧 [ZipArchive] Bắt đầu thay thế tệp gốc ...")
        try FileManager.default.removeItem(at: URL(fileURLWithPath: ipaPath))
        try FileManager.default.moveItem(at: processedIPAPath, to: URL(fileURLWithPath: ipaPath))
        print("✅ [ZipArchive] Đã thay thế thành công tệp gốc")
        
        return ipaPath
        #else
        // 如果没有ZipArchive，抛出错误
        throw NSError(domain: "IPAProcessing", code: 1, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy thư viện ZipArchive, vui lòng định cấu hình chính xác sự phụ thuộc"])
        #endif
    }
    
    /// 创建iTunesMetadata.plist文件
    private func createiTunesMetadataPlist(in extractedDir: URL, appInfo: DownloadAppMetadata) throws {
        let metadataPath = extractedDir.appendingPathComponent("iTunesMetadata.plist")
        print("🔧 [ZipArchive] Sẵn sàng để tạo iTunesMetadata.plist: \(metadataPath.path)")
        
        // 构建iTunesMetadata.plist内容
        let metadataDict: [String: Any] = [
            "appleId": appInfo.bundleId,
            "artistId": 0,
            "artistName": appInfo.bundleDisplayName,
            "bundleId": appInfo.bundleId,
            "bundleVersion": appInfo.bundleShortVersionString,
            "copyright": "Copyright © 2025",
            "drmVersionNumber": 0,
            "fileExtension": "ipa",
            "fileName": "\(appInfo.bundleDisplayName).ipa",
            "genre": "Productivity",
            "genreId": 6007,
            "itemId": 0,
            "itemName": appInfo.bundleDisplayName,
            "kind": "software",
            "playlistName": "iOS Apps",
            "price": 0.0,
            "priceDisplay": "Free",
            "rating": "4+",
            "releaseDate": "2025-01-01T00:00:00Z",
            "s": 143441,
            "softwareIcon57x57URL": "",
            "softwareIconNeedsShine": false,
            "softwareSupportedDeviceIds": [1, 2], // iPhone and iPad
            "softwareVersionBundleId": appInfo.bundleId,
            "softwareVersionExternalIdentifier": Int(appInfo.softwareVersionExternalIdentifier) ?? 0,
            "softwareVersionExternalIdentifiers": appInfo.softwareVersionExternalIdentifiers ?? [],
            "subgenres": [],
            "vendorId": 0,
            "versionRestrictions": 0
        ]
        
        print("🔧 [ZipArchive] Từ điển metadata được xây dựng chứa các trường \(metadataDict.count)")
        print("🔧 [ZipArchive] Giá trị trường khóa:")
        print("   - appleId: \(metadataDict["appleId"] ?? "nil")")
        print("   - artistName: \(metadataDict["artistName"] ?? "nil")")
        print("   - bundleId: \(metadataDict["bundleId"] ?? "nil")")
        print("   - bundleVersion: \(metadataDict["bundleVersion"] ?? "nil")")
        
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: metadataDict,
            format: .xml,
            options: 0
        )
        
        print("🔧 [ZipArchive] Dữ liệu plist tuần tự hóa thành công, kích thước: \(ByteCountFormatter().string(fromByteCount: Int64(plistData.count)))")
        
        try plistData.write(to: metadataPath)
        print("🔧 [ZipArchive] Đã ghi thành công iTunesMetadata.plist vào: \(metadataPath.path)")
        
        // 验证文件是否真的被创建了
        if FileManager.default.fileExists(atPath: metadataPath.path) {
            let fileSize = try FileManager.default.attributesOfItem(atPath: metadataPath.path)[.size] as? Int64 ?? 0
            print("✅ [ZipArchive] Tệp iTunesMetadata.plist được xác nhận là tồn tại và kích thước của nó là: \(ByteCountFormatter().string(fromByteCount: fileSize))")
        } else {
            print("❌ [ZipArchive] Không tạo được tệp iTunesMetadata.plist, tệp không tồn tại")
        }
    }
    
    /// 为IPA文件生成iTunesMetadata.plist - 强制确保每个IPA都包含元数据
    /// - Parameters:
    ///   - ipaPath: IPA文件路径
    ///   - bundleId: 应用包ID
    ///   - displayName: 应用显示名称
    ///   - version: 应用版本
    ///   - externalVersionId: 外部版本ID
    ///   - externalVersionIds: 外部版本ID数组
    /// - Returns: 处理后的IPA文件路径
    private func generateiTunesMetadata(
        for ipaPath: String,
        bundleId: String,
        displayName: String,
        version: String,
        externalVersionId: Int,
        externalVersionIds: [Int]?
    ) async throws -> String {
        print("🔧 [iTunesMetadata] Bắt đầu tạo iTunesMetadata.plist cho các tệp IPA: \(ipaPath)")
        print("🔧 [iTunesMetadata] Thông tin tham số:")
        print("   - Bundle ID: \(bundleId)")
        print("   - Display Name: \(displayName)")
        print("   - Version: \(version)")
        print("   - External Version ID: \(externalVersionId)")
        print("   - External Version IDs: \(externalVersionIds ?? [])")
        
        // 构建iTunesMetadata.plist内容
        let metadataDict: [String: Any] = [
            "appleId": bundleId,
            "artistId": 0,
            "artistName": displayName,
            "bundleId": bundleId,
            "bundleVersion": version,
            "copyright": "Copyright © 2025",
            "drmVersionNumber": 0,
            "fileExtension": "ipa",
            "fileName": "\(displayName).ipa",
            "genre": "Productivity",
            "genreId": 6007,
            "itemId": 0,
            "itemName": displayName,
            "kind": "software",
            "playlistName": "iOS Apps",
            "price": 0.0,
            "priceDisplay": "Free",
            "rating": "4+",
            "releaseDate": "2025-01-01T00:00:00Z",
            "s": 143441,
            "softwareIcon57x57URL": "",
            "softwareIconNeedsShine": false,
            "softwareSupportedDeviceIds": [1, 2], // iPhone and iPad
            "softwareVersionBundleId": bundleId,
            "softwareVersionExternalIdentifier": externalVersionId,
            "softwareVersionExternalIdentifiers": externalVersionIds ?? [],
            "subgenres": [],
            "vendorId": 0,
            "versionRestrictions": 0
        ]
        
        print("🔧 [iTunesMetadata] Từ điển siêu dữ liệu được xây dựng chứa các trường \(metadataDict.count)")
        
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: metadataDict,
            format: .xml,
            options: 0
        )
        
        print("🔧 [iTunesMetadata] Đã tạo thành công dữ liệu plist, kích thước: \(ByteCountFormatter().string(fromByteCount: Int64(plistData.count)))")
        
        // 强制使用ZipArchive处理IPA文件，确保iTunesMetadata.plist被添加
        do {
            print("🔧 [iTunesMetadata] Hãy thử sử dụng ZipArchive để xử lý tệp IPA...")
            let appInfo = DownloadAppMetadata(
                bundleId: bundleId,
                bundleDisplayName: displayName,
                bundleShortVersionString: version,
                softwareVersionExternalIdentifier: String(externalVersionId),
                softwareVersionExternalIdentifiers: externalVersionIds
            )
            
            let processedIPA = try await processIPAWithZipArchive(at: ipaPath, appInfo: appInfo)
            print("✅ [iTunesMetadata] Đã sử dụng ZipArchive thành công để xử lý các tệp IPA: \(processedIPA)")
            return processedIPA
            
        } catch {
            print("❌ [iTunesMetadata] Quá trình xử lý ZipArchive không thành công: \(error)")
            print("🔄 [iTunesMetadata] Hãy thử giải pháp thay thế: trích xuất và thêm trực tiếp iTunesMetadata.plist")
            
            // 备用方案：直接解压IPA，添加iTunesMetadata.plist，然后重新打包
            return try await fallbackAddiTunesMetadata(to: ipaPath, plistData: plistData)
        }
    }
    
    /// 备用方案：直接解压IPA并添加iTunesMetadata.plist
    private func fallbackAddiTunesMetadata(to ipaPath: String, plistData: Data) async throws -> String {
        print("🔄 [Giải pháp thay thế] Bắt đầu xử lý các tệp IPA trực tiếp")
        
        #if canImport(ZipArchive)
        // 创建临时工作目录
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("FallbackIPAProcessing_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            // 清理临时目录
            try? FileManager.default.removeItem(at: tempDir)
        }
        
        let extractedDir = tempDir.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractedDir, withIntermediateDirectories: true)
        
        // 解压IPA文件
        let ipaURL = URL(fileURLWithPath: ipaPath)
        print("🔧 [Giải pháp tiêu chuẩn] Bắt đầu giải nén tệp IPA: \(ipaURL.path)")
        
        let success = SSZipArchive.unzipFile(atPath: ipaURL.path, toDestination: extractedDir.path)
        guard success else {
            throw NSError(domain: "FallbackIPAProcessing", code: 1, userInfo: [NSLocalizedDescriptionKey: "Giải nén IPA không thành công"])
        }
        print("✅ [Giải pháp thay thế] Tệp IPA đã được giải nén thành công")
        
        // 在根目录添加iTunesMetadata.plist
        let metadataPath = extractedDir.appendingPathComponent("iTunesMetadata.plist")
        try plistData.write(to: metadataPath)
        print("✅ [Giải pháp thay thế] iTunesMetadata.plist đã được thêm vào thư mục giải nén")
        
        // 重新打包IPA文件
        let processedIPAPath = ipaURL.deletingLastPathComponent()
            .appendingPathComponent("processed_\(ipaURL.lastPathComponent)")
        
        print("🔧 [Giải pháp thay thế] Bắt đầu đóng gói lại tệp IPA thành: \(processedIPAPath.path)")
        
        let repackSuccess = SSZipArchive.createZipFile(atPath: processedIPAPath.path, withContentsOfDirectory: extractedDir.path)
        guard repackSuccess else {
            throw NSError(domain: "FallbackIPAProcessing", code: 2, userInfo: [NSLocalizedDescriptionKey: "Đóng gói lại IPA không thành công"])
        }
        print("✅ [Giải pháp thay thế] Tệp IPA đóng gói lại thành công")
        
        // 验证处理后的文件是否存在
        guard FileManager.default.fileExists(atPath: processedIPAPath.path) else {
            throw NSError(domain: "FallbackIPAProcessing", code: 3, userInfo: [NSLocalizedDescriptionKey: "Tệp IPA đã xử lý không tồn tại"])
        }
        
        // 获取文件大小
        let fileSize = try FileManager.default.attributesOfItem(atPath: processedIPAPath.path)[.size] as? Int64 ?? 0
        print("✅ [Giải pháp thay thế] Kích thước tệp IPA đã xử lý: \(ByteCountFormatter().string(fromByteCount: fileSize))")
        
        // 替换原文件
        print("🔧 [Giải pháp thay thế] Bắt đầu thay thế tệp gốc...")
        try FileManager.default.removeItem(at: ipaURL)
        try FileManager.default.moveItem(at: processedIPAPath, to: ipaURL)
        
        print("✅ [Giải pháp thay thế] Tệp IPA gốc đã được thay thế thành công bằng phiên bản có chứa iTunesMetadata.plist")
        return ipaURL.path
        
        #else
        // 如果没有ZipArchive，抛出错误
        throw NSError(domain: "FallbackIPAProcessing", code: 3, userInfo: [NSLocalizedDescriptionKey: "Không tìm thấy thư viện ZipArchive, không thể xử lý tệp IPA"])
        #endif
    }
}