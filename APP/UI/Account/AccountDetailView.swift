//  AccountDetailView.swift
//
//  Created by pxx917144686 on 2025/08/20.
//

import SwiftUI

struct AccountDetailView: View {
    let account: Account
    @Environment(\.presentationMode) var presentationMode
    @Environment(\.colorScheme) var colorScheme
    @EnvironmentObject var appStore: AppStore
    @State private var showingDeleteAlert = false
    @State private var isPasswordVisible = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {                    
                    // 账户详情卡片
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Apple ID")
                            .font(.headline)
                            .fontWeight(.semibold)
                        
                        VStack(spacing: 12) {
                            infoRow(label: "Apple ID", value: account.email)
                            infoRow(label: "Tên", value: account.name)
                            infoRow(label: "DS_ID", value: account.dsPersonId)
                            infoRow(label: "Khu vực", value: account.countryCode)
                            
                            // 密码令牌行（带显示/隐藏功能）
                            HStack {
                                Text("Mật khẩu Token")
                                    .foregroundColor(.secondary)
                                    .frame(width: 80, alignment: .leading)
                                
                                Text(isPasswordVisible ? account.passwordToken : String(repeating: "*", count: account.passwordToken.count))
                                    .foregroundColor(.primary)
                                
                                Spacer()
                                
                                Button(action: {
                                    isPasswordVisible.toggle()
                                }) {
                                    Image(systemName: isPasswordVisible ? "eye.slash.fill" : "eye.fill")
                                        .foregroundColor(.blue)
                                }
                            }
                        }
                    }
                    .padding()
                    .background(backgroundColor)
                    .cornerRadius(12)
                    
                    // 删除按钮
                    Button(action: {
                        showingDeleteAlert = true
                    }) {
                        HStack {
                            Image(systemName: "trash.fill")
                            Text("Xóa một tài khoản")
                        }
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(12)
                    }
                }
                .padding()
            }
            .background(backgroundGradient)
            .navigationBarTitleDisplayMode(.inline)
            .alert("Xác nhận xóa", isPresented: $showingDeleteAlert) {
                Button("Xoá bỏ", role: .destructive) {
                    deleteAccount()
                }
                Button("Hủy bỏ", role: .cancel) { }
            } message: {
                Text("Bạn có chắc là bạn muốn xóa tài khoản này không? Hoạt động này không thể bị hủy。")
            }
        }
    }
    
    // MARK: - 主题感知的背景颜色
    private var backgroundColor: Color {
        switch colorScheme {
        case .dark:
            return Color(.systemGray6).opacity(0.8)
        case .light:
            return Color(.systemGray6)
        @unknown default:
            return Color(.systemGray6)
        }
    }
    
    // MARK: - 主题感知的背景渐变
    private var backgroundGradient: some View {
        Group {
            if colorScheme == .dark {
                // 深色模式：统一深色背景
                Color.black
                    .ignoresSafeArea()
            } else {
                // 浅色模式：浅色渐变背景
                LinearGradient(
                    colors: [
                        Color(.systemBackground),
                        Color(.systemGray6).opacity(0.3)
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea()
            }
        }
    }
    
    private func infoRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
                .frame(width: 80, alignment: .leading)
            
            Text(value)
                .foregroundColor(.primary)
            
            Spacer()
        }
    }
    
    private func deleteAccount() {
        print("[AccountDetailView] Xóa một tài khoản: \(account.email)")
        // 调用AppStore的删除方法
        appStore.delete(id: account.id)
        print("[AccountDetailView] Xóa hoàn thành, số tài khoản hiện tại: \(appStore.accounts.count)")
        // 关闭详情页面
        presentationMode.wrappedValue.dismiss()
    }
}