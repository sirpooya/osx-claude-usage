//
//  UsageDetailView.swift
//  ClaudeUsage
//
//  Created by f-is-h on 2025-10-15.
//  Copyright © 2025 f-is-h. All rights reserved.
//

import SwiftUI

/// Popover 的固定排版尺寸。高度要手算，因为 body 上挂了显式 frame
/// （NSHostingController 的 preferredContentSize 只跟随这个 frame）。
private enum PopoverMetrics {
    /// 一行限制的高度：标题行 15 + 间距 5 + 进度条 5，再留 1 的余量
    static let rowHeight: CGFloat = 26
    /// 限制行之间的间距
    static let rowSpacing: CGFloat = 12
    /// 限制列表左右边距
    static let horizontalPadding: CGFloat = 16
    /// 标题栏上方留白 + 标题行 + 底部留白
    static let chromeHeight: CGFloat = 18 + 20 + 20
    /// 空状态（未登录 / 出错 / 加载中）用固定高度：图标 + 文案 + 按钮比进度条列表高
    static let stateHeight: CGFloat = 210

    /// n 行限制占的高度
    static func rowsHeight(_ rowCount: Int) -> CGFloat {
        guard rowCount > 0 else { return 0 }
        return CGFloat(rowCount) * rowHeight + CGFloat(rowCount - 1) * rowSpacing
    }
}

/// 用量详情视图
/// 显示 Claude 的当前使用情况，包括百分比进度条、倒计时和重置时间
struct UsageDetailView: View {
    @Binding var usageData: UsageData?
    @Binding var codexUsageData: CodexUsageData?
    @Binding var errorMessage: String?
    @Binding var codexErrorMessage: String?
    /// Codex 三级刷新均失败，需要用户手动重新登录
    @Binding var codexNeedsRelogin: Bool
    @ObservedObject var refreshState: RefreshState
    /// 菜单操作回调
    var onMenuAction: ((MenuAction) -> Void)? = nil
    @StateObject private var localization = LocalizationManager.shared
    /// 是否有可用更新（用于显示文字和徽章）
    @Binding var hasAvailableUpdate: Bool
    /// 是否应显示更新徽章（用户未确认时才显示徽章）
    @Binding var shouldShowUpdateBadge: Bool

    /// 菜单操作类型
    enum MenuAction {
        case generalSettings
        case authSettings
        case checkForUpdates
        case about
        case claudeStatus
        case codexStatus
        case coffee
        case githubSponsor
        case quit
        case refresh
        case refreshClaude
        case refreshCodex
        case codexRelogin
    }
    
    // 用于动画的状态（改为从外部传入，避免每次重建视图时重置）
    @State var rotationAngle: Double = 0
    @State var animationTimer: Timer?
    // 显示更新通知
    @State private var showUpdateNotification = false
    // 显示模式切换（false: 重置时间, true: 剩余时间）
    // 默认走剩余时间：倒计时（"3d 12h left"）比绝对时间戳（"Aug 24 2 AM"）更直接，
    // 用户不用自己算差值。注意不能用 UserDefaults.bool(forKey:)，键不存在时它返回
    // false，会把这个默认值又翻回重置时间。
    @AppStorage("showRemainingMode") private var savedRemainingMode = true
    @State private var showRemainingMode =
        (UserDefaults.standard.object(forKey: "showRemainingMode") as? Bool) ?? true
    
    // MARK: - Body

    private var isMultiProviderActive: Bool {
        UserSettings.shared.isMultiProviderActive
            && (codexUsageData != nil || codexErrorMessage != nil || UserSettings.shared.hasValidCodexCredentials)
    }

    private var isCodexOnlyActive: Bool {
        !isMultiProviderActive
            && ((!UserSettings.shared.hasValidCredentials && UserSettings.shared.hasValidCodexCredentials)
                || (usageData == nil && (codexUsageData != nil || codexErrorMessage != nil)))
    }

    private var isClaudeRefreshing: Bool {
        refreshState.isRefreshingProvider(.claude)
    }

    /// 获取当前 Claude 活动的显示类型
    private var activeDisplayTypes: [LimitType] {
        guard let data = usageData else { return [] }
        return UserSettings.shared.getActiveDisplayTypes(usageData: data)
            .filter { $0.provider == .claude }
    }

    /// 获取当前 Codex 活动的显示类型
    private var activeCodexDisplayTypes: [LimitType] {
        guard let codex = codexUsageData else { return [] }
        return UserSettings.shared.getActiveDisplayTypes(usageData: nil, codexUsageData: codex)
            .filter { $0.provider == .codex }
    }

    /// Claude 列实际渲染的限制行数（含超出前两个槽位的模型行）
    private func claudeRowCount(for data: UsageData?) -> Int {
        guard let data else { return 2 }
        let types = UserSettings.shared.getActiveDisplayTypes(usageData: data)
            .filter { $0.provider == .claude }
        var count = types.count
        // 智能模式会把第三个及以后的模型也补成行，高度得算上，否则会被裁掉
        if UserSettings.shared.displayMode == .smart {
            count += max(0, data.weeklyModels.count - 2)
        }
        return max(count, 1)
    }

    /// Codex 列实际渲染的限制行数
    private func codexRowCount(for codex: CodexUsageData?) -> Int {
        guard let codex else { return 2 }
        let types = UserSettings.shared.getActiveDisplayTypes(usageData: nil, codexUsageData: codex)
            .filter { $0.provider == .codex }
        return max(types.count, 1)
    }

    /// 单 Provider（Claude）模式高度
    private var dynamicHeight: CGFloat {
        if errorMessage != nil || usageData == nil {
            return PopoverMetrics.stateHeight
        }
        return PopoverMetrics.chromeHeight
            + contentSpacing
            + PopoverMetrics.rowsHeight(claudeRowCount(for: usageData))
    }

    /// Codex-only 模式高度
    private var codexOnlyHeight: CGFloat {
        if codexUsageData == nil {
            return PopoverMetrics.stateHeight
        }
        return PopoverMetrics.chromeHeight
            + contentSpacing
            + PopoverMetrics.rowsHeight(codexRowCount(for: codexUsageData))
    }

    /// 双 Provider 模式高度（取两列的较高者）
    private var multiProviderHeight: CGFloat {
        let claudeHeight: CGFloat = (errorMessage != nil || usageData == nil)
            ? PopoverMetrics.stateHeight
            : PopoverMetrics.chromeHeight + contentSpacing
                + PopoverMetrics.rowsHeight(claudeRowCount(for: usageData))

        let codexHeight: CGFloat = codexUsageData == nil
            ? PopoverMetrics.stateHeight
            : PopoverMetrics.chromeHeight + contentSpacing
                + PopoverMetrics.rowsHeight(codexRowCount(for: codexUsageData))

        return max(claudeHeight, codexHeight)
    }

    private var contentSpacing: CGFloat {
        let visibleTypeCount = isCodexOnlyActive ? activeCodexDisplayTypes.count : activeDisplayTypes.count
        return visibleTypeCount >= 2 ? 10 : 16
    }

    private var multiProviderDividerHeight: CGFloat {
        max(35, multiProviderHeight - 28)
    }

    private var contentWidth: CGFloat {
        isMultiProviderActive ? 580 : 290
    }

    private var contentHeight: CGFloat {
        if isMultiProviderActive {
            return multiProviderHeight
        }
        if isCodexOnlyActive {
            return codexOnlyHeight
        }
        return dynamicHeight
    }

    /// 未登录状态。不是错误，所以不用警告图标，只给一个动作：登录。
    private var signedOutState: some View {
        VStack(spacing: 12) {
            Image(systemName: "key.fill")
                .font(.system(size: 30))
                .foregroundColor(UsageColorScheme.brand)

            Text(L.Usage.signInPrompt)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: {
                WebLoginWindowManager.shared.showLoginWindow { _ in
                    // 登录完直接拉一次数据，省得用户再点刷新
                    onMenuAction?(.refresh)
                }
            }) {
                Text(L.WebLogin.browserLoginRecommended)
            }
            .buttonStyle(.borderedProminent)
            .tint(UsageColorScheme.brand)
        }
        .padding()
    }

    /// 真正的错误状态。按钮写什么就做什么，不再拿"运行诊断"当设置入口。
    /// 文案允许换行，之前固定单行会把消息截断成 "...information in..."。
    private func errorState(_ error: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 30))
                .foregroundColor(.orange)

            Text(error)
                .font(.subheadline)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Button(L.Usage.refresh) { onMenuAction?(.refresh) }
                Button(L.Usage.goToSettings) { onMenuAction?(.authSettings) }
            }
            .buttonStyle(.bordered)
        }
        .padding()
    }

    @ViewBuilder
    private var claudeMainContent: some View {
        if let error = errorMessage {
            // 没登录不算错误，按空状态处理；只有真出错才摆警告图标。
            // 原来这里靠 error.contains("Authentication"/"configured") 猜是哪种情况，
            // 而实际文案是 "Please configure authentication information..."，
            // 两个判断都不成立，于是只剩下那个名不副实的"运行诊断"按钮。
            if !UserSettings.shared.hasValidCredentials {
                signedOutState
            } else {
                errorState(error)
            }
        } else if let data = usageData {
            // 使用数据：每条限制一行整宽进度条。点一下在「重置时间 / 剩余时间」间切换
            VStack(spacing: PopoverMetrics.rowSpacing) {
                ForEach(activeDisplayTypes, id: \.self) { type in
                    UnifiedLimitRow(
                        type: type,
                        data: data,
                        showRemainingMode: showRemainingMode,
                        isRefreshing: isClaudeRefreshing
                    )
                }
                // 前两个模型走上面的 opus / sonnet 槽位；第三个及以后的模型
                // （如同时出现 Fable + Opus + Sonnet）在此按 Claude API 顺序补齐，
                // 配色在两个槽位之间轮换，标签用 API 返回的模型名。
                // 仅智能模式展开全部；自定义模式尊重用户勾选的固定槽位。
                if UserSettings.shared.displayMode == .smart {
                    let overflow = Array(data.weeklyModels.enumerated()).dropFirst(2)
                    ForEach(overflow, id: \.offset) { entry in
                        UnifiedLimitRow(
                            type: entry.offset % 2 == 0 ? .opusWeekly : .sonnetWeekly,
                            data: data,
                            showRemainingMode: showRemainingMode,
                            isRefreshing: isClaudeRefreshing,
                            weeklyModelOverride: entry.element
                        )
                    }
                }
            }
            .padding(.horizontal, PopoverMetrics.horizontalPadding)
            .contentShape(Rectangle())
            .onTapGesture {
                toggleRemainingMode()
            }
        } else {
            // 加载中
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                Text(L.Usage.loading)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(height: 100)
        }
    }

    // MARK: - Header Buttons

    /// 刷新按钮 + 三点菜单按钮（共用于单列和双列头部）
    @ViewBuilder
    private var refreshAndMenuButtons: some View {
        Button(action: { onMenuAction?(.refresh) }) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 14))
                .foregroundColor(.secondary)
                .opacity(refreshState.canRefresh ? 1.0 : 0.3)
                .rotationEffect(.degrees(refreshState.isRefreshing ? rotationAngle : 0))
                .frame(width: 20, height: 20)
        }
        .buttonStyle(.plain)
        .disabled(!refreshState.canRefresh || refreshState.isRefreshing)
        .focusable(false)

        ZStack(alignment: .topTrailing) {
            Menu {
                if UserSettings.shared.accounts.count > 1 {
                    Menu {
                        ForEach(UserSettings.shared.accounts) { account in
                            Button(action: { UserSettings.shared.switchToAccount(account) }) {
                                HStack {
                                    Text(account.displayName)
                                    if account.id == UserSettings.shared.currentAccountId {
                                        Spacer(); Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        let name = UserSettings.shared.currentAccountName ?? L.Menu.account
                        Label("\(L.Menu.accountPrefix) \(name)", systemImage: "person.2")
                    }
                    Divider()
                }

                if UserSettings.shared.codexAccounts.count > 1 {
                    Menu {
                        ForEach(UserSettings.shared.codexAccounts) { account in
                            Button(action: { UserSettings.shared.switchToCodexAccount(account) }) {
                                HStack {
                                    Text(account.displayName)
                                    if account.id == UserSettings.shared.currentCodexAccountId {
                                        Spacer(); Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        let name = UserSettings.shared.currentCodexAccount?.displayName ?? "Codex"
                        Label("Codex: \(name)", systemImage: "person.2.fill")
                    }
                    Divider()
                }

                Button(action: { onMenuAction?(.generalSettings) }) {
                    Label(L.Menu.generalSettings, systemImage: "gearshape")
                }
                Button(action: { onMenuAction?(.authSettings) }) {
                    Label(L.Menu.authSettings, systemImage: "key")
                }
                if hasAvailableUpdate {
                    Button(action: { onMenuAction?(.checkForUpdates) }) {
                        Label { Text(createUpdateMenuText()) } icon: {
                            Image(systemName: "exclamationmark.arrow.trianglehead.2.clockwise.rotate.90")
                        }
                    }
                } else {
                    Button(action: { onMenuAction?(.checkForUpdates) }) {
                        Label(L.Menu.checkUpdates, systemImage: "arrow.triangle.2.circlepath")
                    }
                }
                Button(action: { onMenuAction?(.about) }) {
                    Label(L.Menu.about, systemImage: "info.circle")
                }
                Divider()
                if !UserSettings.shared.accounts.isEmpty {
                    Button(action: { onMenuAction?(.claudeStatus) }) {
                        Label(L.Menu.claudeStatus, systemImage: "safari")
                    }
                }
                if !UserSettings.shared.codexAccounts.isEmpty {
                    Button(action: { onMenuAction?(.codexStatus) }) {
                        Label(L.Menu.codexStatus, systemImage: "safari.fill")
                    }
                }
                Button(action: { onMenuAction?(.coffee) }) {
                    Label(L.Menu.coffee, systemImage: "cup.and.saucer")
                }
                Button(action: { onMenuAction?(.githubSponsor) }) {
                    Label(L.Menu.githubSponsor, systemImage: "heart")
                }
                Divider()
                Button(action: { onMenuAction?(.quit) }) {
                    Label(L.Menu.quit, systemImage: "power")
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .rotationEffect(.degrees(90))
                    .frame(width: 20, height: 20)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .buttonStyle(.plain)
            .focusable(false)

            if shouldShowUpdateBadge {
                Circle().fill(Color.red).frame(width: 6, height: 6).offset(x: 5, y: -5)
            }
        }
    }

    @ViewBuilder
    private func headerView(provider: ProviderType, showsControls: Bool) -> some View {
        let headerIconSize: CGFloat = 18
        let headerRowHeight: CGFloat = 20
        HStack {
            if provider == .claude {
                if let icon = ImageHelper.createAppIcon(size: headerIconSize) {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: headerIconSize, height: headerIconSize)
                } else {
                    Image(systemName: "chart.pie.fill")
                        .foregroundColor(.blue)
                }
            } else if let icon = ImageHelper.createCodexIcon(size: headerIconSize) {
                Image(nsImage: icon)
                    .resizable()
                    .frame(width: headerIconSize, height: headerIconSize)
            }

            Text(provider == .claude ? L.Usage.title : L.Usage.codexTitle)
                .font(.headline)

            Spacer()

            if showsControls {
                refreshAndMenuButtons
            }
        }
        .frame(height: headerRowHeight, alignment: .center)
        .padding(.horizontal)
        .padding(.top, 18)
    }

    @ViewBuilder
    private var updateNotificationView: some View {
        if showUpdateNotification {
            HStack(spacing: 6) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 14))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [.red, .orange, .yellow, .green, .blue, .purple, .red],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                    )
                rainbowText(L.Update.Notification.available)
                    .font(.system(size: 14))
            }
            .padding(.horizontal, 12)
            .padding(.top, -8)
            .padding(.bottom, 6)
            .transition(.opacity.combined(with: .scale))
        }
    }

    @ViewBuilder
    private func codexOnlyMainContent(codex: CodexUsageData?) -> some View {
        if let codex {
            CodexColumnView(
                codexUsageData: codex,
                showRemainingMode: $showRemainingMode,
                refreshState: refreshState,
                onToggleRemainingMode: toggleRemainingMode
            )
        } else if let error = codexErrorMessage {
            VStack(spacing: 12) {
                Image(systemName: codexNeedsRelogin ? "lock.open.trianglebadge.exclamationmark.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundColor(.orange)
                Text(error)
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundColor(.secondary)

                if codexNeedsRelogin {
                    // 三级刷新均失败：提供一键重新登录入口
                    Button(action: {
                        onMenuAction?(.codexRelogin)
                    }) {
                        Label(L.Usage.codexRelogin, systemImage: "arrow.counterclockwise.circle.fill")
                            .padding(.horizontal, 20)
                            .padding(.vertical, 8)
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                } else {
                    // 同上：两个按钮原本都指向设置，其中一个却写着"运行诊断"
                    HStack(spacing: 10) {
                        Button(L.Usage.refresh) { onMenuAction?(.refreshCodex) }
                        Button(L.Usage.goToSettings) { onMenuAction?(.authSettings) }
                    }
                    .buttonStyle(.bordered)
                }
            }
            .padding()
        } else {
            VStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(1.2)
                Text(L.Usage.loading)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            .frame(height: 100)
        }
    }

    private var singleProviderBody: some View {
        VStack(spacing: contentSpacing) {
            headerView(provider: .claude, showsControls: true)
            claudeMainContent
            updateNotificationView
            Spacer()
        }
    }

    private func codexOnlyBody(codex: CodexUsageData?) -> some View {
        VStack(spacing: contentSpacing) {
            headerView(provider: .codex, showsControls: true)
            codexOnlyMainContent(codex: codex)
            updateNotificationView
            Spacer()
        }
    }

    private func multiProviderBody(codex: CodexUsageData?) -> some View {
        VStack(spacing: contentSpacing) {
            HStack(alignment: .top, spacing: 0) {
                VStack(spacing: contentSpacing) {
                    headerView(provider: .claude, showsControls: false)
                    claudeMainContent
                }
                .frame(width: 290, alignment: .top)

                VStack(spacing: contentSpacing) {
                    headerView(provider: .codex, showsControls: true)
                    codexOnlyMainContent(codex: codex)
                }
                .frame(width: 290, alignment: .top)
            }
            .overlay(alignment: .center) {
                ProviderDivider(height: multiProviderDividerHeight)
                    .allowsHitTesting(false)
            }

            updateNotificationView
            Spacer()
        }
    }

    var body: some View {
        Group {
            if isMultiProviderActive {
                multiProviderBody(codex: codexUsageData)
            } else if isCodexOnlyActive {
                codexOnlyBody(codex: codexUsageData)
            } else {
                singleProviderBody
            }
        }
        .frame(width: contentWidth, height: contentHeight)
        .animation(.easeInOut(duration: 0.25), value: isMultiProviderActive)
        .animation(.easeInOut(duration: 0.25), value: isCodexOnlyActive)
        .id(localization.updateTrigger)  // 语言变化时重新创建视图
        .onAppear {
            var transaction = Transaction(animation: nil)
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                showRemainingMode = savedRemainingMode
            }
            // 如果打开时已经在刷新，启动旋转动画
            if refreshState.isRefreshing {
                startRotationAnimation()
            }
            // 如果有更新通知消息，显示通知
            if refreshState.notificationMessage != nil {
                withAnimation {
                    showUpdateNotification = true
                }
                // 3秒后隐藏通知
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation {
                        showUpdateNotification = false
                    }
                }
            }
        }
        .onChange(of: refreshState.isRefreshing) { newValue in
            if newValue { startRotationAnimation() } else { stopRotationAnimation() }
        }
        .onChange(of: refreshState.notificationMessage) { message in
            // 监听通知消息变化
            if message != nil {
                withAnimation {
                    showUpdateNotification = true
                }
                // 3秒后隐藏通知
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    withAnimation {
                        showUpdateNotification = false
                    }
                }
            } else {
                withAnimation {
                    showUpdateNotification = false
                }
            }
        }
        .onDisappear {
            // 视图消失时清理定时器
            stopRotationAnimation()
        }
        #if DEBUG
        .background(
            UserSettings.shared.debugKeepDetailWindowOpen ? Color.white : Color.clear
        )
        #endif
    }

    private func toggleRemainingMode() {
        withAnimation(.spring(response: 0.42, dampingFraction: 0.78, blendDuration: 0.05)) {
            showRemainingMode.toggle()
        }
        savedRemainingMode = showRemainingMode
    }
}

// 预览
struct UsageDetailView_Previews: PreviewProvider {
    @State static var sampleData: UsageData? = UsageData(
        fiveHour: UsageData.LimitData(
            percentage: 45,
            resetsAt: Date().addingTimeInterval(3600 * 2.5)
        ),
        sevenDay: nil,
        opus: nil,
        sonnet: nil,
        extraUsage: nil
    )

    @State static var errorMsg: String? = nil
    @State static var codexErrorMsg: String? = nil
    @State static var codexData: CodexUsageData? = nil
    @State static var codexNeedsRelogin = false
    @StateObject static var refreshState = RefreshState()
    @State static var hasUpdate = false
    @State static var shouldShowBadge = false

    static var previews: some View {
        UsageDetailView(
            usageData: $sampleData,
            codexUsageData: $codexData,
            errorMessage: $errorMsg,
            codexErrorMessage: $codexErrorMsg,
            codexNeedsRelogin: $codexNeedsRelogin,
            refreshState: refreshState,
            hasAvailableUpdate: $hasUpdate,
            shouldShowUpdateBadge: $shouldShowBadge
        )
    }
}
