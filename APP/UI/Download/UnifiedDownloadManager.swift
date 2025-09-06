//
//  UnifiedDownloadManager.swift
//  APP
//
//  Created by pxx917144686 on 2025/08/20.
//

import Foundation
import SwiftUI
import Combine

/// 底层下载和UI层管理
@MainActor
class UnifiedDownloadManager: ObservableObject {
    static let shared = UnifiedDownloadManager()
    
    @Published var downloadRequests: [DownloadRequest] = []
    @Published var completedRequests: Set<UUID> = []
    @Published var activeDownloads: Set<UUID> = []
    
    private let downloadManager = DownloadManager.shared
    
    private init() {}
    
    /// 添加下载请求
    func addDownload(
        bundleIdentifier: String,
        name: String,
        version: String,
        identifier: Int,
        iconURL: String? = nil,
        versionId: String? = nil
    ) -> UUID {
        print("🔍 [Thêm Tải xuống] Bắt đầu thêm yêu cầu tải xuống")
        print("   - Bundle ID: \(bundleIdentifier)")
        print("   - Tên: \(name)")
        print("   - Phiên bản: \(version)")
        print("   - Định danh: \(identifier)")
        print("   - ID phiên bản: \(versionId ?? "không có")")
        
        let package = DownloadArchive(
            bundleIdentifier: bundleIdentifier,
            name: name,
            version: version,
            identifier: identifier,
            iconURL: iconURL
        )
        
        let request = DownloadRequest(
            bundleIdentifier: bundleIdentifier,
            version: version,
            name: name,
            package: package,
            versionId: versionId
        )
        
        downloadRequests.append(request)
        print("✅ [Thêm tải xuống] Yêu cầu tải xuống đã được thêm，ID: \(request.id)")
        print("📊 [Thêm tải xuống] Tổng số yêu cầu tải xuống hiện tại: \(downloadRequests.count)")
        print("🖼️ [Thông tin biểu tượng] URL biểu tượng: \(request.iconURL ?? "无")")
        print("📦 [Thông tin gói] Tên gói: \(request.package.name), Định danh: \(request.package.identifier)")
        return request.id
    }
    
    /// 删除下载请求
    func deleteDownload(request: DownloadRequest) {
        if let index = downloadRequests.firstIndex(where: { $0.id == request.id }) {
            downloadRequests.remove(at: index)
            activeDownloads.remove(request.id)
            completedRequests.remove(request.id)
            print("🗑️ [Xóa tải xuống] Yêu cầu tải xuống đã xóa: \(request.name)")
        }
    }
    
    /// 开始下载
    func startDownload(for request: DownloadRequest) {
        guard !activeDownloads.contains(request.id) else { 
            print("⚠️ [Tải xuống Bỏ qua] Yêu cầu \(request.id) đã ở trong hàng đợi tải xuống")
            return 
        }
        
        print("🚀 [Tải xuống bắt đầu] Bắt đầu tải xuống: \(request.name) v\(request.version)")
        print("🔍 [Gỡ lỗi] Tải xuống chi tiết yêu cầu:")
        print("   - Bundle ID: \(request.bundleIdentifier)")
        print("   - Phiên bản: \(request.version)")
        print("   - ID phiên bản: \(request.versionId ?? "không có")")
        print("   - Định danh gói: \(request.package.identifier)")
        print("   - Tên gói: \(request.package.name)")
        print("   - Trạng thái hiện tại: \(request.runtime.status)")
        print("   - Tiến trình hiện tại: \(request.runtime.progressValue)")
        
        activeDownloads.insert(request.id)
        request.runtime.status = .downloading
        request.runtime.error = nil
        
        // 重置进度，使用动态大小
        request.runtime.progress = Progress(totalUnitCount: 0)
        request.runtime.progress.completedUnitCount = 0
        
        print("✅ [Cập nhật trạng thái] Trạng thái đã được đặt thành: \(request.runtime.status)")
        print("✅ [Đặt lại tiến độ] Đặt lại tiến độ cho: \(request.runtime.progressValue)")
        
        Task {
            do {
                guard let account = AppStore.this.accounts.first else {
                    await MainActor.run {
                        request.runtime.error = "Vui lòng thêm tài khoản ID Apple trước"
                        request.runtime.status = .failed
                        self.activeDownloads.remove(request.id)
                        print("❌ [Xác thực không thành công] Không tìm thấy tài khoản Apple, ID hợp lệ")
                    }
                    return
                }
                
                print("🔐 [Thông tin xác thực] Sử dụng tài khoản: \(account.email)")
                print("🏪 [Lưu trữ thông tin] StoreFront: \(account.storeResponse.storeFront)")
                
                // 确保认证状态
                AuthenticationManager.shared.setCookies(account.cookies)
                
                // 借鉴旧代码的成功实现 - 使用正确的Account结构体
                let storeAccount = Account(
                    name: account.email,
                    email: account.email,
                    firstName: account.firstName,
                    lastName: account.lastName,
                    passwordToken: account.storeResponse.passwordToken,
                    directoryServicesIdentifier: account.storeResponse.directoryServicesIdentifier,
                    dsPersonId: account.storeResponse.directoryServicesIdentifier,
                    cookies: account.cookies,
                    countryCode: account.countryCode,
                    storeResponse: account.storeResponse
                )
                
                // 创建目标文件URL
                let documentsPath = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
                let sanitizedName = request.package.name.replacingOccurrences(of: "/", with: "_")
                let destinationURL = documentsPath.appendingPathComponent("\(sanitizedName)_\(request.version).ipa")
                
                print("📁 [Đường dẫn tệp] Vị trí đích: \(destinationURL.path)")
                print("🆔 [Thông tin ứng dụng] ID: \(request.package.identifier), 版本: \(request.versionId ?? request.version)")
                
                // 使用DownloadManager进行下载
                downloadManager.downloadApp(
                    appIdentifier: String(request.package.identifier),
                    account: storeAccount,
                    destinationURL: destinationURL,
                    appVersion: request.versionId,
                    progressHandler: { downloadProgress in
                        Task { @MainActor in
                            // 使用新的进度更新方法
                            request.runtime.updateProgress(
                                completed: downloadProgress.bytesDownloaded,
                                total: downloadProgress.totalBytes
                            )
                            request.runtime.speed = downloadProgress.formattedSpeed
                            request.runtime.status = downloadProgress.status
                            
                            // 每1%进度打印一次日志，确保实时更新
                            let progressPercent = Int(downloadProgress.progress * 100)
                            if progressPercent % 1 == 0 && progressPercent > 0 {
                                print("📊 [Tải xuống tiến trình] \(request.name): \(progressPercent)% (\(downloadProgress.formattedSize)) - tốc độ: \(downloadProgress.formattedSpeed)")
                            }
                            
                            // 强制触发UI更新 
                            request.objectWillChange.send()
                            request.runtime.objectWillChange.send()
                        }
                    },
                    completion: { result in
                        Task { @MainActor in
                            switch result {
                            case .success(let downloadResult):
                                // 确保进度显示为100%
                                request.runtime.updateProgress(
                                    completed: downloadResult.fileSize,
                                    total: downloadResult.fileSize
                                )
                                request.runtime.status = .completed
                                // ✅ 添加localFilePath赋值
                                request.localFilePath = downloadResult.fileURL.path
                                self.completedRequests.insert(request.id)
                                print("✅ [Tải xuống hoàn thành] \(request.name) Được lưu vào: \(downloadResult.fileURL.path)")
                                print("📊 [Thông tin tập tin] Kích thước: \(ByteCountFormatter().string(fromByteCount: downloadResult.fileSize))")
                                
                            case .failure(let error):
                                request.runtime.error = error.localizedDescription
                                request.runtime.status = .failed
                                print("❌ [Tải xuống không thành công] \(request.name): \(error.localizedDescription)")
                            }
                            
                            self.activeDownloads.remove(request.id)
                        }
                    }
                )
                
            } catch {
                await MainActor.run {
                    request.runtime.error = error.localizedDescription
                    request.runtime.status = .failed
                    self.activeDownloads.remove(request.id)
                    print("❌ [Tải xuống ngoại lệ] \(request.name): \(error.localizedDescription)")
                }
            }
        }
    }
        
    /// 检查下载是否完成
    func isCompleted(for request: DownloadRequest) -> Bool {
        return completedRequests.contains(request.id)
    }
    
    /// 获取活跃下载数量
    var activeDownloadCount: Int {
        return activeDownloads.count
    }
    
    /// 获取已完成下载数量
    var completedDownloadCount: Int {
        return completedRequests.count
    }
}

// MARK: - 数据模型

/// 下载应用信息结构
struct DownloadArchive {
    let bundleIdentifier: String
    let name: String
    let version: String
    let identifier: Int
    let iconURL: String?
    let description: String?
    
    init(bundleIdentifier: String, name: String, version: String, identifier: Int = 0, iconURL: String? = nil, description: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.name = name
        self.version = version
        self.identifier = identifier
        self.iconURL = iconURL
        self.description = description
    }
}

/// 下载运行时信息
class DownloadRuntime: ObservableObject {
    @Published var status: DownloadStatus = .waiting
    @Published var progress: Progress = Progress(totalUnitCount: 0)
    @Published var speed: String = ""
    @Published var error: String?
    @Published var progressValue: Double = 0.0  // 添加独立的进度值
    
    init() {
        // 初始化时不需要设置totalUnitCount，它会在updateProgress中设置
        progress.completedUnitCount = 0
    }
    
    /// 更新进度值并触发UI更新 
    func updateProgress(completed: Int64, total: Int64) {
        // 创建新的Progress对象，因为totalUnitCount是只读的
        progress = Progress(totalUnitCount: total)
        progress.completedUnitCount = completed
        progressValue = total > 0 ? Double(completed) / Double(total) : 0.0
        
        // 强制触发UI更新 
        objectWillChange.send()
        
        // 打印调试信息 
        let percent = Int(progressValue * 100)
        print("🔄 [Cập nhật tiến độ] \(percent)% (\(ByteCountFormatter().string(fromByteCount: completed))/\(ByteCountFormatter().string(fromByteCount: total)))")
        
        // 确保UI立即更新
        DispatchQueue.main.async {
            self.objectWillChange.send()
        }
    }
}

/// 下载请求
class DownloadRequest: Identifiable, ObservableObject, Equatable {
    let id = UUID()
    let bundleIdentifier: String
    let version: String
    let name: String
    let createdAt: Date
    let package: DownloadArchive
    let versionId: String?
    @Published var localFilePath: String?
    // Hold subscriptions for forwarding child changes
    private var cancellables: Set<AnyCancellable> = []
    @Published var runtime: DownloadRuntime { didSet { bindRuntime() } }
    
    var iconURL: String? {
        return package.iconURL
    }
    
    var identifier: Int {
        return package.identifier
    }
    
    init(bundleIdentifier: String, version: String, name: String, package: DownloadArchive, versionId: String? = nil) {
        self.bundleIdentifier = bundleIdentifier
        self.version = version
        self.name = name
        self.createdAt = Date()
        self.package = package
        self.versionId = versionId
        self.runtime = DownloadRuntime()
        // Bind after runtime is set
        bindRuntime()
    }
    
    // Forward inner object changes to this object so SwiftUI can refresh when runtime's @Published values change
    private func bindRuntime() {
        cancellables.removeAll()
        runtime.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }
    
    /// 获取下载状态提示
    var hint: String {
        if let error = runtime.error {
            return error
        }
        return switch runtime.status {
        case .waiting:
            NSLocalizedString("Chờ...", comment: "")
        case .downloading:
            [
                String(Int(runtime.progressValue * 100)) + "%",
                runtime.speed.isEmpty ? "" : runtime.speed,
            ]
            .compactMap { $0 }
            .joined(separator: " ")
        case .paused:
            NSLocalizedString("Tạm dừng", comment: "")
        case .completed:
            NSLocalizedString("Hoàn thành", comment: "")
        case .failed:
            NSLocalizedString("Tải xuống không thành công", comment: "")
        case .cancelled:
            NSLocalizedString("Bị hủy bỏ", comment: "")
        }
    }
    
    // MARK: - Equatable
    static func == (lhs: DownloadRequest, rhs: DownloadRequest) -> Bool {
        return lhs.id == rhs.id
    }
}