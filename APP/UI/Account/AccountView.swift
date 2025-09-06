//
//  AccountView.swift
//
//  Created by pxx917144686 on 2025/08/20.
//
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct AccountView: View {
    @State var addSheet = false
    @State var animation = false
    @EnvironmentObject var appStore: AppStore
    @State var layoutRefreshTrigger = UUID()
    @State var showDeleteAlert = false
    @State var accountToDelete: Account?
    
    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // 顶部安全区域占位 - 真机适配
                GeometryReader { geometry in
                    Color.clear
                        .frame(height: geometry.safeAreaInsets.top > 0 ? geometry.safeAreaInsets.top : 44)
                        .onAppear {
                            print("[AccountView] Khu vực an toàn hàng đầu: \(geometry.safeAreaInsets.top)")
                        }
                }
                .frame(height: 44) // 固定高度，避免布局跳动
                
                // 主要内容
                VStack(spacing: 0) {
                    if appStore.accounts.isEmpty {
                        VStack(spacing: 30) {
                            Spacer()
                            VStack(spacing: 20) {
                                // Logo with Animation - 修复动画问题
                                Image(systemName: "person.circle.fill")
                                    .resizable()
                                    .scaledToFit()
                                    .frame(width: 120, height: 120)
                                    .foregroundColor(.blue)
                                    .scaleEffect(animation ? 1.05 : 1.0) // 减少动画幅度
                                    .opacity(animation ? 0.9 : 0.7) // 减少透明度变化
                                    .animation(
                                        Animation.easeInOut(duration: 1.5).repeatForever(autoreverses: true), // 减少动画时长
                                        value: animation
                                    )
                                // Welcome Text
                                VStack(spacing: 12) {
                                    Text("Apple ID")
                                        .font(.title)
                                        .fontWeight(.bold)
                                        .foregroundColor(.primary)
                                    Text("Gặp vấn đề, Liên hệ: pxx917144686,Translation by @romlayvn🇻🇳")
                                        .font(.body)
                                        .foregroundColor(.secondary)
                                        .multilineTextAlignment(.center)
                                }
                            }
                            // Add Account Button
                            Button(action: { addSheet.toggle() }) {
                                HStack(spacing: 10) {
                                    Image(systemName: "plus.circle.fill")
                                        .font(.body)
                                    Text("Thêm một tài khoản")
                                }
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            
                            // 调试按钮 - 强制刷新布局
                            #if DEBUG
                            Button(action: {
                                print("[AccountView] Làm mới thủ công")
                                layoutRefreshTrigger = UUID()
                            }) {
                                HStack(spacing: 10) {
                                    Image(systemName: "arrow.clockwise")
                                        .font(.body)
                                    Text("Làm mới bố cục")
                                }
                                .padding()
                                .background(Color.orange)
                                .foregroundColor(.white)
                                .cornerRadius(10)
                            }
                            #endif
                            
                            Spacer()
                        }
                        .padding(.horizontal, 40)
                    } else {
                        // 显示账户列表
                        List {
                            ForEach(appStore.accounts) { account in
                                NavigationLink(destination: AccountDetailView(account: account)) {
                                    AccountRowView(account: account)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                            .onDelete(perform: deleteAccount) // 保留滑动删除功能
                        }
                        .listStyle(PlainListStyle())
                    }
                }
                .background(Color(.systemBackground))
                .padding(.top, 10) // 添加额外的顶部间距
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarBackButtonHidden(true) // 隐藏返回按钮
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text("Apple ID")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if !appStore.accounts.isEmpty {
                        Button(action: { addSheet.toggle() }) {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundColor(.blue)
                        }
                    }
                }
            }
            .sheet(isPresented: $addSheet) {
                AddAccountView()
                    .environmentObject(AppStore.this)
            }
            .onAppear {
                // 强制刷新布局
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    layoutRefreshTrigger = UUID()
                    print("[AccountView] Buộc làm mới bố cục")
                }
                
                // 启动动画
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    withAnimation(.easeInOut(duration: 0.8)) {
                        animation = true
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("ForceRefreshUI"))) { _ in
                // 接收强制刷新通知 - 真机适配
                print("[AccountView] Đã nhận được một thông báo làm mới bắt buộc")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    layoutRefreshTrigger = UUID()
                    print("[AccountView] Hoàn tất việc làm mới bắt buộc thích ứng thiết bị thực tế")
                }
            }
        }
        .navigationViewStyle(.stack)
        .background(Color(.systemBackground)) // 确保整个视图有背景色
        .alert("Xác nhận xóa", isPresented: $showDeleteAlert) {
            Button("Hủy bỏ", role: .cancel) { }
            Button("Xoá bỏ", role: .destructive) {
                if let account = accountToDelete {
                    print("[AccountView] Người dùng xác nhận xóa tài khoản: \(account.email)")
                    // 执行删除操作
                    appStore.delete(id: account.id)
                    print("[AccountView] Xóa hoàn tất, số tài khoản hiện tại: \(appStore.accounts.count)")
                    
                    // 强制刷新UI
                    DispatchQueue.main.async {
                        layoutRefreshTrigger = UUID()
                    }
                    
                    // 清理状态
                    accountToDelete = nil
                }
            }
        } message: {
            if let account = accountToDelete {
                Text("Xác nhận để xóa tài khoản \(account.email) không？Hoạt động này không thể bị hủy。")
            }
        }
    }
    
    private func deleteAccount(offsets: IndexSet) {
        print("[AccountView] DeleteAccount được gọi là chỉ mục: \(offsets)")
        
        for index in offsets {
            let account = appStore.accounts[index]
            print("[AccountView] Chuẩn bị xóa tài khoản: \(account.email), ID: \(account.id)")
            
            // 设置要删除的账户并显示确认对话框
            accountToDelete = account
            showDeleteAlert = true
        }
    }
}

// MARK: - Account Row View
struct AccountRowView: View {
    let account: Any
    @EnvironmentObject var themeManager: ThemeManager
    
    var body: some View {
        HStack(spacing: 16) {
            // 账户头像
            Image(systemName: "person.circle.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 50, height: 50)
                .foregroundColor(.blue)
            
            // 账户信息
            VStack(alignment: .leading, spacing: 6) { // 增加间距
                if let account = account as? Account {
                    Text(account.email)
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    if !account.name.isEmpty {
                        Text(account.name)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(2) // 允许两行显示
                    }
                    
                    HStack(spacing: 8) {
                        // 显示地区代码，使用更友好的显示方式
                        let regionDisplay = getRegionDisplay(for: account.countryCode)
                        Text(regionDisplay)
                            .font(.caption)
                            .foregroundColor(.white) // 改为白色以提高可读性
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4) // 增加垂直间距
                            .background(
                                Capsule()
                                    .fill(Color.blue.opacity(0.8)) // 使用更明显的颜色
                            )
                        
                        if !account.dsPersonId.isEmpty {
                            Text("DS: \(account.dsPersonId)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 2)
                                .background(
                                    RoundedRectangle(cornerRadius: 4)
                                        .fill(Color.gray.opacity(0.1))
                                )
                        }
                    }
                } else {
                    // 如果无法转换为Account类型，显示默认信息
                    Text("Thông tin tài khoản")
                        .font(.headline)
                        .foregroundColor(.primary)
                    Text("Không thể tải chi tiết")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
        }
        .padding(.vertical, 12) // 增加垂直间距
        .padding(.horizontal, 4) // 添加水平间距
        .background(Color(.systemBackground)) // 确保有背景色
    }
    
    // MARK: - 辅助方法
    private func getRegionDisplay(for countryCode: String) -> String {
        // 地区代码映射 - 完整版本（去重）
        let regionMap: [String: String] = [
            // 北美
            "US": "Hoa Kỳ",
"CA": "Canada",
"MX": "Mexico",

// Châu Âu
"GB": "Vương quốc Anh",
"DE": "Đức",
"FR": "Pháp",
"IT": "Ý",
"ES": "Tây Ban Nha",
"NL": "Hà Lan",
"SE": "Thụy Điển",
"NO": "Na Uy",
"DK": "Đan Mạch",
"FI": "Phần Lan",
"CH": "Thụy Sĩ",
"AT": "Áo",
"BE": "Bỉ",
"IE": "Ireland",
"PT": "Bồ Đào Nha",
"GR": "Hy Lạp",
"PL": "Ba Lan",
"CZ": "Cộng hòa Séc",
"HU": "Hungary",
"RO": "Romania",
"BG": "Bulgaria",
"HR": "Croatia",
"SI": "Slovenia",
"SK": "Slovakia",
"LT": "Litva",
"LV": "Latvia",
"EE": "Estonia",
"LU": "Luxembourg",
"MT": "Malta",
"CY": "Síp",
"IS": "Iceland",
"LI": "Liechtenstein",
"MC": "Monaco",
"AD": "Andorra",
"SM": "San Marino",
"VA": "Vatican",

// Châu Á
"CN": "Trung Quốc",
"HK": "Hồng Kông",
"MO": "Ma Cao",
"TW": "Đài Loan",
"JP": "Nhật Bản",
"KR": "Hàn Quốc",
"SG": "Singapore",
"TH": "Thái Lan",
"VN": "Việt Nam",
"MY": "Malaysia",
"ID": "Indonesia",
"PH": "Philippines",
"IN": "Ấn Độ",
"PK": "Pakistan",
"BD": "Bangladesh",
"LK": "Sri Lanka",
"NP": "Nepal",
"MM": "Myanmar",
"KH": "Campuchia",
"LA": "Lào",
"BN": "Brunei",
"TL": "Đông Timor",
"MN": "Mông Cổ",
"KZ": "Kazakhstan",
"UZ": "Uzbekistan",
"KG": "Kyrgyzstan",
"TJ": "Tajikistan",
"TM": "Turkmenistan",
"AF": "Afghanistan",
"IR": "Iran",
"IQ": "Iraq",
"SA": "Ả Rập Xê Út",
"AE": "Các Tiểu vương quốc Ả Rập Thống nhất",
"QA": "Qatar",
"KW": "Kuwait",
"BH": "Bahrain",
"OM": "Oman",
"YE": "Yemen",
"JO": "Jordan",
"LB": "Liban",
"SY": "Syria",
"IL": "Israel",
"PS": "Palestine",
"TR": "Thổ Nhĩ Kỳ",
"GE": "Georgia",
"AM": "Armenia",
"AZ": "Azerbaijan",

// Châu Đại Dương
"AU": "Úc",
"NZ": "New Zealand",
"FJ": "Fiji",
"PG": "Papua New Guinea",
"NC": "New Caledonia",
"PF": "Polynesia thuộc Pháp",
"VU": "Vanuatu",
"SB": "Quần đảo Solomon",
"TO": "Tonga",
"WS": "Samoa",
"KI": "Kiribati",
"TV": "Tuvalu",
"NR": "Nauru",
"PW": "Palau",
"MH": "Quần đảo Marshall",
"FM": "Micronesia",
"CK": "Quần đảo Cook",
"NU": "Niue",
"TK": "Tokelau",

// Nam Mỹ
"BR": "Brazil",
"AR": "Argentina",
"CL": "Chile",
"CO": "Colombia",
"PE": "Peru",
"VE": "Venezuela",
"EC": "Ecuador",
"BO": "Bolivia",
"PY": "Paraguay",
"UY": "Uruguay",
"GY": "Guyana",
"SR": "Suriname",
"FK": "Quần đảo Falkland",
"GF": "Guiana thuộc Pháp",

// Châu Phi
"ZA": "Nam Phi",
"EG": "Ai Cập",
"NG": "Nigeria",
"KE": "Kenya",
"ET": "Ethiopia",
"TZ": "Tanzania",
"UG": "Uganda",
"GH": "Ghana",
"CI": "Bờ Biển Ngà",
"SN": "Senegal",
"ML": "Mali",
"BF": "Burkina Faso",
"NE": "Niger",
"TD": "Tchad",
"SD": "Sudan",
"SS": "Nam Sudan",
"CF": "Cộng hòa Trung Phi",
"CM": "Cameroon",
"GQ": "Guinea Xích Đạo",
"GA": "Gabon",
"CG": "Cộng hòa Congo",
"CD": "Cộng hòa Dân chủ Congo",
"AO": "Angola",
"ZM": "Zambia",
"ZW": "Zimbabwe",
"BW": "Botswana",
"NA": "Namibia",
"SZ": "Eswatini",
"LS": "Lesotho",
"MG": "Madagascar",
"MU": "Mauritius",
"SC": "Seychelles",
"KM": "Comoros",
"DJ": "Djibouti",
"SO": "Somalia",
"ER": "Eritrea",
"LY": "Libya",
"TN": "Tunisia",
"DZ": "Algeria",
"MA": "Ma-rốc",
"EH": "Tây Sahara",
"MR": "Mauritania",

// Trung Mỹ và Caribe
"GT": "Guatemala",
"BZ": "Belize",
"SV": "El Salvador",
"HN": "Honduras",
"NI": "Nicaragua",
"CR": "Costa Rica",
"PA": "Panama",
"CU": "Cuba",
"JM": "Jamaica",
"HT": "Haiti",
"DO": "Cộng hòa Dominica",
"PR": "Puerto Rico",
"TT": "Trinidad và Tobago",
"BB": "Barbados",
"GD": "Grenada",
"LC": "Saint Lucia",
"VC": "Saint Vincent và Grenadines",
"AG": "Antigua và Barbuda",
"KN": "Saint Kitts và Nevis",
"DM": "Dominica",
"BS": "Bahamas",
"TC": "Quần đảo Turks và Caicos",
"KY": "Quần đảo Cayman",
"BM": "Bermuda",
"AW": "Aruba",
"CW": "Curaçao",
"SX": "Sint Maarten",
"MF": "Saint-Martin thuộc Pháp",
"BL": "Saint Barthélemy",
"GP": "Guadeloupe",
"MQ": "Martinique",
"RE": "Réunion",
"YT": "Mayotte",
"WF": "Wallis và Futuna",
"TF": "Lãnh thổ phía Nam thuộc Pháp",
"PM": "Saint Pierre và Miquelon",
"GL": "Greenland",
"FO": "Quần đảo Faroe",
"AX": "Quần đảo Åland",
"SJ": "Svalbard và Jan Mayen",
"BV": "Đảo Bouvet",
"GS": "Nam Georgia và Quần đảo Nam Sandwich",
"IO": "Lãnh thổ Ấn Độ Dương thuộc Anh",
"SH": "Saint Helena",
"GI": "Gibraltar"

        ]
        
        // 如果找到对应的中文名称，返回"中文名 (代码)"格式
        if let chineseName = regionMap[countryCode] {
            return "\(chineseName) (\(countryCode))"
        } else {
            // 如果没有找到，只返回代码
            return countryCode
        }
    }
}