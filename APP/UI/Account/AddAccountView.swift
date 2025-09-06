import SwiftUI
import Foundation

// MARK: - Modern Text Field Style
struct ModernTextFieldStyle: TextFieldStyle {
    let themeManager: ThemeManager
    
    func _body(configuration: TextField<Self._Label>) -> some View {
        configuration
            .padding()
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(themeManager.selectedTheme == .dark ? 
                          ModernDarkColors.surfacePrimary : 
                          Color.gray.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(themeManager.selectedTheme == .dark ? 
                                   ModernDarkColors.borderPrimary : 
                                   Color.gray.opacity(0.3), lineWidth: 1)
                    )
            )
            .foregroundColor(themeManager.selectedTheme == .dark ? .white : .black)
            .accentColor(themeManager.accentColor)
    }
}
struct AddAccountView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var vm: AppStore
    @StateObject private var themeManager = ThemeManager.shared
    @State private var email: String = ""
    @State private var password: String = ""
    @State private var code: String = ""
    @State private var errorMessage: String = ""
    @State private var isLoading: Bool = false
    @State private var showTwoFactorField: Bool = false
    var body: some View {
        NavigationView {
            ZStack {
                // 适配深色模式的背景
                themeManager.backgroundColor
                    .ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // 顶部安全区域占位
                    GeometryReader { geometry in
                        Color.clear
                            .frame(height: geometry.safeAreaInsets.top > 0 ? geometry.safeAreaInsets.top : 44)
                    }
                    .frame(height: 44)
                    
                    // 主要内容区域 - 完美居中
                    VStack(spacing: 0) {
                        Spacer()
                        
                        // 标题区域 - 完全居中
                        VStack(spacing: 20) {
                            Image("AppLogo")
                                .resizable()
                                .scaledToFit()
                                .frame(width: 120, height: 120)
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
                            
                            VStack(spacing: 8) {
                                Text("Apple ID")
                                    .font(.largeTitle)
                                    .fontWeight(.bold)
                                    .foregroundColor(themeManager.primaryTextColor)
                                
                                Text("Đăng nhập vào tài khoản của bạn")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Spacer()
                        
                        // 输入表单区域
                        VStack(spacing: 24) {
                            // Apple ID 输入框
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Apple ID")
                                    .font(.headline)
                                    .foregroundColor(themeManager.primaryTextColor)
                                TextField("Nhập Apple ID của bạn", text: $email)
                                    .textFieldStyle(ModernTextFieldStyle(themeManager: themeManager))
                                    .keyboardType(.emailAddress)
                                    .autocapitalization(.none)
                                    .disableAutocorrection(true)
                            }
                            
                            // 密码输入框
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Mật khẩu")
                                    .font(.headline)
                                    .foregroundColor(themeManager.primaryTextColor)
                                SecureField("Nhập mật khẩu của bạn", text: $password)
                                    .textFieldStyle(ModernTextFieldStyle(themeManager: themeManager))
                            }
                            
                            // 双重认证码输入框（条件显示）
                            if showTwoFactorField {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text("Mã xác thực 2 yếu tố")
                                        .font(.headline)
                                        .foregroundColor(themeManager.primaryTextColor)
                                    TextField("Nhập mã xác minh 6 chữ số", text: $code)
                                        .textFieldStyle(ModernTextFieldStyle(themeManager: themeManager))
                                        .keyboardType(.numberPad)
                                        .onChange(of: code) { newValue in
                                            // 限制输入长度为6位
                                            if newValue.count > 6 {
                                                code = String(newValue.prefix(6))
                                            }
                                        }
                                    Text("Vui lòng kiểm tra thiết bị đáng tin cậy hoặc tin nhắn văn bản của bạn để lấy mã xác minh")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                .transition(.opacity.combined(with: .move(edge: .top)))
                            }
                        }
                        .padding(.horizontal, 24)
                        
                        Spacer()
                        
                        // 登录按钮区域
                        VStack(spacing: 16) {
                            Button(action: {
                                Task {
                                    await authenticate()
                                }
                            }) {
                                HStack(spacing: 12) {
                                    if isLoading {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "person.crop.circle.fill")
                                            .font(.title2)
                                    }
                                    Text(isLoading ? "Xác minh ..." : "Thêm một tài khoản")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 16)
                                .background(
                                    LinearGradient(
                                        colors: [themeManager.accentColor, themeManager.accentColor.opacity(0.8)],
                                        startPoint: .leading,
                                        endPoint: .trailing
                                    )
                                )
                                .foregroundColor(.white)
                                .cornerRadius(16)
                                .shadow(color: themeManager.accentColor.opacity(0.3), radius: 8, x: 0, y: 4)
                            }
                            .disabled(isLoading || email.isEmpty || password.isEmpty)
                            
                            // 错误信息显示
                            if !errorMessage.isEmpty {
                                HStack(spacing: 8) {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                    Text(errorMessage)
                                        .font(.caption)
                                        .foregroundColor(.red)
                                        .multilineTextAlignment(.center)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(8)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 32)
                    }
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Hủy bỏ") {
                        dismiss()
                    }
                    .foregroundColor(themeManager.primaryTextColor)
                }
            }
            .onAppear {
                // 保持用户当前的主题设置，不强制重置
            }
        }
    }
    @MainActor
    private func authenticate() async {
        guard !email.isEmpty && !password.isEmpty else {
            errorMessage = "Vui lòng nhập đầy đủ ID Apple và Mật khẩu"
            return
        }
        
        print("🔐 [AddAccountView] Bắt đầu quá trình xác thực")
        print("📧 [AddAccountView] Apple ID: \(email)")
        print("🔐 [AddAccountView] Độ dài mật khẩu: \(password.count)")
        print("📱 [AddAccountView] Mã xác minh: \(showTwoFactorField ? code : "không có")")
        
        isLoading = true
        errorMessage = ""
        
        do {
            print("🚀 [AddAccountView] Gọi vm.addAccount...")
            // 使用AppStore的addAccount方法进行认证和添加
            try await vm.addAccount(
                email: email,
                password: password,
                code: showTwoFactorField ? code : nil
            )
            print("✅ [AddAccountView] Xác thực đã thành công, hãy tắt chế độ xem")
            // 成功后直接关闭视图
            dismiss()
        } catch {
            print("❌ [AddAccountView] Xác thực thất bại: \(error)")
            print("❌ [AddAccountView] Loại lỗi: \(type(of: error))")
            
            isLoading = false
            
            if let storeError = error as? StoreError {
                print("🔍 [AddAccountView] Đã phát hiện StoreError: \(storeError)")
                switch storeError {
                case .invalidCredentials:
                    errorMessage = "ID Apple hoặc mật khẩu không chính xác, vui lòng kiểm tra và thử lại"
                case .codeRequired:
                    print("🔐 [AddAccountView] Cần mã xác thực hai yếu tố")
                    if !showTwoFactorField {
                        withAnimation(.easeInOut(duration: 0.3)) {
                            showTwoFactorField = true
                        }
                    } else {
                        errorMessage = "Mã xác minh không chính xác, vui lòng kiểm tra xem mã xác minh có đúng không"
                    }
                case .lockedAccount:
                    errorMessage = "ID Apple của bạn đã bị khóa, vui lòng thử lại sau hoặc liên hệ với hỗ trợ của Apple"
                case .networkError:
                    errorMessage = "Đã xảy ra lỗi mạng trong quá trình xác thực ID Apple. Vui lòng kiểm tra kết nối mạng của bạn và thử lại"
                case .authenticationFailed:
                    errorMessage = "Xác thực không thành công, vui lòng kiểm tra kết nối mạng và thông tin tài khoản"
                case .invalidResponse:
                    errorMessage = "Phản hồi máy chủ không hợp lệ, vui lòng thử lại sau"
                case .unknownError:
                    errorMessage = "Lỗi không xác định, vui lòng thử lại sau"
                default:
                    errorMessage = "Đã xảy ra lỗi trong quá trình xác thực ID Apple: \(storeError.localizedDescription)"
                }
            } else {
                print("🔍 [AddAccountView] Loại lỗi không xác định: \(error)")
                errorMessage = "Đã xảy ra lỗi trong quá trình xác thực ID Apple: \(error.localizedDescription)"
            }
        }
    }
}