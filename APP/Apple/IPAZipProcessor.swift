//
//  IPAZipProcessor.swift
//  Created by pxx917144686 on 2025/09/03.
//
import Foundation
#if canImport(ZipArchive)
import ZipArchive
#endif

/// 应用元数据信息（IPAZipProcessor专用定义）
struct IPAMetadataInfo {
    let bundleId: String
    let displayName: String
    let version: String
    let externalVersionId: Int
    let externalVersionIds: [Int]?
    
    init(bundleId: String, displayName: String, version: String, externalVersionId: Int = 0, externalVersionIds: [Int]? = nil) {
        self.bundleId = bundleId
        self.displayName = displayName
        self.version = version
        self.externalVersionId = externalVersionId
        self.externalVersionIds = externalVersionIds
    }
}

// 类型别名，使用专用定义
typealias AppMetadataInfo = IPAMetadataInfo

/// IPA文件处理器，使用ZipArchive来真正处理IPA文件
class IPAZipProcessor {
    static let shared = IPAZipProcessor()
    
    private init() {}
    
    /// 为IPA文件添加iTunesMetadata.plist（使用ZipArchive）
    /// - Parameters:
    ///   - ipaPath: IPA文件路径
    ///   - appInfo: 应用信息
    /// - Returns: 处理后的IPA文件路径
    func addMetadataToIPA(at ipaPath: String, appInfo: AppMetadataInfo) async throws -> String {
        print("🔧 [IPAZipProcessor] Bắt đầu xử lý các tệp IPA: \(ipaPath)")
        
        // 创建临时工作目录
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("IPAZip_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        defer {
            // 清理临时目录
            try? FileManager.default.removeDirectory(at: tempDir)
        }
        
        // 尝试使用ZipArchive处理IPA文件
        do {
            let processedIPA = try await processWithZipArchive(ipaPath: ipaPath, appInfo: appInfo, tempDir: tempDir)
            print("✅ [IPAZipProcessor] Các tệp IPA được xử lý thành công bằng cách sử dụng ZipArchive")
            return processedIPA
        } catch {
            print("⚠️ [IPAZipProcessor] Xử lý ZipArchive không thành công: \(error)")
            print("📋 [IPAZipProcessor] Sử dụng thay thế: Lưu iTunesMetadata.plist vào thư mục Documents")
            
            // 备用方案：保存iTunesMetadata.plist到Documents目录
            return try saveMetadataToDocuments(appInfo: appInfo)
        }
    }
    
    /// 使用ZipArchive处理IPA文件
    private func processWithZipArchive(ipaPath: String, appInfo: AppMetadataInfo, tempDir: URL) async throws -> String {
        // 解压IPA文件
        let extractedDir = try extractIPA(at: ipaPath, to: tempDir)
        print("🔧 [IPAZipProcessor] Giải nén tệp IPA đã hoàn thành")
        
        // 添加iTunesMetadata.plist
        try addiTunesMetadata(to: extractedDir, with: appInfo)
        print("🔧 [IPAZipProcessor] Thêm iTunesMetadata.plist để hoàn thành")
        
        // 重新打包IPA文件
        let processedIPA = try repackIPA(from: extractedDir, originalPath: ipaPath)
        print("🔧 [IPAZipProcessor] Đóng gói lại tệp IPA được hoàn thành")
        
        return processedIPA
    }
    
    /// 解压IPA文件
    private func extractIPA(at ipaPath: String, to tempDir: URL) throws -> URL {
        let extractedDir = tempDir.appendingPathComponent("extracted")
        try FileManager.default.createDirectory(at: extractedDir, withIntermediateDirectories: true)
        
        // 尝试使用ZipArchive解压IPA文件
        #if canImport(ZipArchive)
        let success = SSZipArchive.unzipFile(atPath: ipaPath, toDestination: extractedDir.path)
        guard success else {
            throw IPAZipError.extractionFailed("Giải nén IPA không thành công")
        }
        #else
        // 如果没有ZipArchive，尝试使用系统命令
        try extractWithSystemCommand(ipaPath: ipaPath, to: extractedDir)
        #endif
        
        return extractedDir
    }
    
    /// 使用系统命令解压IPA文件（备用方案）
    private func extractWithSystemCommand(ipaPath: String, to extractedDir: URL) throws {
        #if os(macOS)
        // macOS上使用unzip命令
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-q", ipaPath, "-d", extractedDir.path]
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw IPAZipError.extractionFailed("Giải nén lệnh hệ thống không thành công, mã thoát: \(process.terminationStatus)")
        }
        #else
        // iOS上无法使用系统命令，抛出错误
        throw IPAZipError.extractionFailed("Không thể giải nén các tệp IPA bằng cách sử dụng các lệnh hệ thống trên iOS")
        #endif
    }
    
    /// 添加iTunesMetadata.plist到解压的IPA目录
    private func addiTunesMetadata(to extractedDir: URL, with appInfo: AppMetadataInfo) throws {
        let metadataPath = extractedDir.appendingPathComponent("iTunesMetadata.plist")
        
        // 构建iTunesMetadata.plist内容
        let metadataDict: [String: Any] = [
            "appleId": appInfo.bundleId,
            "artistId": 0,
            "artistName": appInfo.displayName,
            "bundleId": appInfo.bundleId,
            "bundleVersion": appInfo.version,
            "copyright": "Copyright © 2025",
            "drmVersionNumber": 0,
            "fileExtension": "ipa",
            "fileName": "\(appInfo.displayName).ipa",
            "genre": "Productivity",
            "genreId": 6007,
            "itemId": 0,
            "itemName": appInfo.displayName,
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
            "softwareVersionExternalIdentifier": appInfo.externalVersionId,
            "softwareVersionExternalIdentifiers": appInfo.externalVersionIds ?? [],
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
        print("🔧 [IPAZipProcessor] Tạo thành công iTunesMetadata.plist，Kích cỡ: \(ByteCountFormatter().string(fromByteCount: Int64(plistData.count)))")
    }
    
    /// 重新打包IPA文件
    private func repackIPA(from extractedDir: URL, originalPath: String) throws -> String {
        let processedIPAPath = URL(fileURLWithPath: originalPath).deletingLastPathComponent()
            .appendingPathComponent("processed_\(URL(fileURLWithPath: originalPath).lastPathComponent)")
        
        // 尝试使用ZipArchive重新打包IPA文件
        #if canImport(ZipArchive)
        let success = SSZipArchive.createZipFile(atPath: processedIPAPath.path, withContentsOfDirectory: extractedDir.path)
        guard success else {
            throw IPAZipError.packagingFailed("Đóng gói lại IPA không thành công")
        }
        #else
        // 如果没有ZipArchive，尝试使用系统命令
        try repackWithSystemCommand(from: extractedDir, to: processedIPAPath)
        #endif
        
        // 替换原文件
        try FileManager.default.removeItem(at: URL(fileURLWithPath: originalPath))
        try FileManager.default.moveItem(at: processedIPAPath, to: URL(fileURLWithPath: originalPath))
        
        return originalPath
    }
    
    /// 使用系统命令重新打包IPA文件（备用方案）
    private func repackWithSystemCommand(from extractedDir: URL, to outputPath: URL) throws {
        #if os(macOS)
        // macOS上使用zip命令
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.arguments = ["-r", "-q", outputPath.path, "."]
        process.currentDirectoryURL = extractedDir
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            throw IPAZipError.packagingFailed("Gói lệnh hệ thống không thành công, mã thoát: \(process.terminationStatus)")
        }
        #else
        // iOS上无法使用系统命令，抛出错误
        throw IPAZipError.packagingFailed("Các tệp IPA không thể được đóng gói bằng cách sử dụng các lệnh hệ thống trên iOS")
        #endif
    }
    
    /// 备用方案：保存iTunesMetadata.plist到Documents目录
    private func saveMetadataToDocuments(appInfo: AppMetadataInfo) throws -> String {
        let metadataDict: [String: Any] = [
            "appleId": appInfo.bundleId,
            "artistId": 0,
            "artistName": appInfo.displayName,
            "bundleId": appInfo.bundleId,
            "bundleVersion": appInfo.version,
            "copyright": "Copyright © 2025",
            "drmVersionNumber": 0,
            "fileExtension": "ipa",
            "fileName": "\(appInfo.displayName).ipa",
            "genre": "Productivity",
            "genreId": 6007,
            "itemId": 0,
            "itemName": appInfo.displayName,
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
            "softwareVersionExternalIdentifier": appInfo.externalVersionId,
            "softwareVersionExternalIdentifiers": appInfo.externalVersionIds ?? [],
            "subgenres": [],
            "vendorId": 0,
            "versionRestrictions": 0
        ]
        
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: metadataDict,
            format: .xml,
            options: 0
        )
        
        // 保存到Documents目录
        let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let finalMetadataPath = documentsPath.appendingPathComponent("iTunesMetadata_\(appInfo.bundleId).plist")
        try plistData.write(to: finalMetadataPath)
        
        print("📁 [IPAZipProcessor] Kế hoạch thay thế：iTunesMetadata.plist Được lưu vào: \(finalMetadataPath.path)")
        print("📋 [IPAZipProcessor] Vui lòng thêm tệp này vào tệp IPA theo cách thủ công")
        
        return finalMetadataPath.path
    }
}

// MARK: - 应用元数据信息
// 注意：AppMetadataInfo现在在IPAMetadataProcessor.swift中定义，避免重复
// struct AppMetadataInfo {
//     let bundleId: String
//     let displayName: String
//     let version: String
//     let externalVersionId: Int
//     let externalVersionIds: [Int]?
//     
//     init(bundleId: String, displayName: String, version: String, externalVersionId: Int = 0, externalVersionIds: [Int]? = nil) {
//         self.bundleId = bundleId
//         self.displayName = displayName
//         self.version = version
//         self.externalVersionId = externalVersionId
//         self.externalVersionIds = externalVersionIds
//     }
// }

// MARK: - 错误类型
enum IPAZipError: Error, LocalizedError {
    case extractionFailed(String)
    case packagingFailed(String)
    case libraryNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .extractionFailed(let message):
            return "Giải nén IPA không thành công: \(message)"
        case .packagingFailed(let message):
            return "Đóng gói IPA không thành công: \(message)"
        case .libraryNotFound(let message):
            return "Không tìm thấy thư viện: \(message)"
        }
    }
}

// MARK: - FileManager扩展
extension FileManager {
    func removeDirectory(at url: URL) throws {
        if fileExists(atPath: url.path) {
            try removeItem(at: url)
        }
    }
}
