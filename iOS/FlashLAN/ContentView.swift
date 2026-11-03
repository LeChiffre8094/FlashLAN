import SwiftUI
import QuickLook
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var engine = DownloadEngine.shared
    @StateObject private var servers = ServerStore()
    @State private var tab = 0
    
    var body: some View {
        ZStack {
            TabView(selection: $tab) {
                FilesView(servers: servers, engine: engine, showServers: { tab = 2 })
                    .tabItem {
                        Label("文件库", systemImage: "folder")
                    }
                    .tag(0)
                
                DownloadsView(engine: engine)
                    .tabItem {
                        Label("传输", systemImage: "arrow.triangle.swap")
                    }
                    .tag(1)
                
                ServersView(store: servers)
                    .tabItem {
                        Label("主机", systemImage: "macbook.and.iphone")
                    }
                    .tag(2)
            }
            .tint(Color(red: 0.00, green: 0.48, blue: 1.00))
            
            // OLED StandBy Zen Screen (Pure #000000, 0 burn-in risk, Apple Nightstand aesthetic)
            if engine.isZenModeActive {
                ZenScreenView(engine: engine) {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        engine.isZenModeActive = false
                    }
                }
                .transition(.opacity)
                .zIndex(999)
            }
        }
        .alert("提示", isPresented: Binding(get: { engine.notice != nil }, set: { if !$0 { engine.notice = nil } })) {
            Button("好") { engine.notice = nil }
        } message: { Text(engine.notice ?? "") }
    }
}

// MARK: - Apple StandBy Inspired Zen Screen (极简息屏挂机)

struct ZenScreenView: View {
    @ObservedObject var engine: DownloadEngine
    let onDismiss: () -> Void
    
    @State private var offset: CGSize = .zero
    @State private var timer = Timer.publish(every: 30, on: .main, in: .common).autoconnect()
    @State private var timeString: String = ""
    
    private var activeRecord: DownloadRecord? {
        engine.records.first { ["downloading", "scheduled"].contains($0.status) }
    }
    private var queuedCount: Int {
        engine.records.filter { ["queued", "scheduled"].contains($0.status) }.count
    }
    private var completedCount: Int {
        engine.records.filter { $0.status == "completed" }.count
    }
    
    var body: some View {
        ZStack {
            // Absolute Pure Black (#000000) - All OLED pixels fully powered down
            Color.black
                .ignoresSafeArea()
            
            VStack(spacing: 28) {
                // Top Subtle Clock
                Text(timeString)
                    .font(.system(size: 15, weight: .regular, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                
                // Minimalist Speed & Indicator
                VStack(spacing: 6) {
                    Text(!engine.speedString.isEmpty ? engine.speedString : (activeRecord != nil ? "连接中" : "就绪"))
                        .font(.system(size: 44, weight: .light, design: .rounded))
                        .foregroundStyle(.white.opacity(0.85))
                    
                    HStack(spacing: 6) {
                        Circle()
                            .fill(activeRecord != nil ? Color.green.opacity(0.8) : Color.gray.opacity(0.4))
                            .frame(width: 5, height: 5)
                        Text(activeRecord != nil ? "局域网高速传输" : "任务已就绪")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.white.opacity(0.4))
                    }
                }
                
                // Clean Minimalist Progress Ring / Line
                if let record = activeRecord {
                    VStack(spacing: 10) {
                        Text(record.name)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                            .frame(maxWidth: 260)
                        
                        if record.size > 0 {
                            GeometryReader { geo in
                                ZStack(alignment: .leading) {
                                    Capsule()
                                        .fill(Color.white.opacity(0.1))
                                        .frame(height: 3)
                                    Capsule()
                                        .fill(Color.white.opacity(0.65))
                                        .frame(width: geo.size.width * CGFloat(record.progress), height: 3)
                                }
                            }
                            .frame(width: 200, height: 3)
                        }
                    }
                }
                
                // Queue Summary
                HStack(spacing: 16) {
                    Text("剩余 \(queuedCount) 项")
                    Text("·")
                    Text("已完成 \(completedCount) 项")
                }
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.3))
                
                // Subtle Touch-to-wake hint
                Text("轻触任意处唤醒")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.2))
                    .padding(.top, 16)
            }
            .offset(offset)
            .onReceive(timer) { _ in
                // Gentle 30s pixel drift to prevent OLED burn-in
                updateTime()
                withAnimation(.easeInOut(duration: 3.0)) {
                    offset = CGSize(
                        width: CGFloat.random(in: -18...18),
                        height: CGFloat.random(in: -28...28)
                    )
                }
            }
            .onAppear {
                updateTime()
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onDismiss()
        }
    }
    
    private func updateTime() {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        timeString = formatter.string(from: Date())
    }
}

// MARK: - Downloads View (Apple Health / Watch Inspired Dashboard)

struct DownloadsView: View {
    @ObservedObject var engine: DownloadEngine
    @State private var video: FloatingVideoSession?
    @State private var completed = false
    @State private var panel: FilePanel?
    @State private var pendingAction: PendingFileAction?
    @State private var renaming: DownloadRecord?
    @State private var newName = ""
    @State private var deletion: PendingFileAction?
    @State private var selecting = false
    @State private var selectedIDs = Set<String>()
    @State private var batchDeleteFiles = false
    @State private var showingBatchDeletion = false
    @State private var deletionIDs = Set<String>()
    
    private var activeRecord: DownloadRecord? {
        engine.records.first { ["downloading", "scheduled"].contains($0.status) }
    }
    
    private var shown: [DownloadRecord] {
        if completed { return Array(engine.records.filter { $0.status == "completed" }.reversed()) }
        let active = engine.records.filter { ["downloading", "pausing", "cancelling"].contains($0.status) }
        let queued = engine.records.filter { ["queued", "scheduled"].contains($0.status) }
        let other = engine.records.filter { !["completed", "downloading", "pausing", "cancelling", "queued", "scheduled"].contains($0.status) }
        return active + queued + other
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !completed {
                    appleDashboardCard
                        .padding(.horizontal)
                        .padding(.top, 6)
                        .padding(.bottom, 12)
                }
                
                Picker("状态", selection: $completed) {
                    Text("下载队列 (\(engine.records.filter { $0.status != \"completed\" }.count))").tag(false)
                    Text("已完成 (\(engine.records.filter { $0.status == \"completed\" }.count))").tag(true)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)
                
                List(shown) { record in
                    if record.status == "completed" {
                        completedRow(record)
                    } else {
                        taskRow(record)
                    }
                }
                .listStyle(.insetGrouped)
                .overlay {
                    if shown.isEmpty {
                        VStack(spacing: 12) {
                            Image(systemName: completed ? "tray" : "arrow.down.circle")
                                .font(.system(size: 36, weight: .light))
                                .foregroundStyle(.secondary.opacity(0.6))
                            Text(completed ? "暂无已完成文件" : "传输队列为空")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("闪传").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    if completed && selecting {
                        Button(selectedIDs == Set(shown.map(\.id)) && !shown.isEmpty ? "取消全选" : "全选") {
                            let all = Set(shown.map(\.id))
                            selectedIDs = selectedIDs == all ? [] : all
                        }
                        .disabled(shown.isEmpty || engine.fileOperationID != nil)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    if completed {
                        Button(selecting ? "完成" : "选择") {
                            video?.close(); video = nil
                            selecting.toggle(); selectedIDs.removeAll()
                        }
                        .disabled(engine.fileOperationID != nil)
                    } else {
                        Button {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                engine.isZenModeActive = true
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "moon.fill").font(.caption)
                                Text("息屏挂机").font(.caption.weight(.medium))
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color(uiColor: .secondarySystemFill), in: Capsule())
                        }
                        .foregroundStyle(.primary)
                        .accessibilityLabel("进入防烧屏息屏挂机模式")
                    }
                }
            }
            .safeAreaInset(edge: .bottom) {
                if completed && selecting {
                    VStack(spacing: 12) {
                        HStack {
                            Spacer()
                            Text("已选 \(selectedIDs.count) 项").font(.subheadline.weight(.medium))
                        }
                        HStack(spacing: 14) {
                            Button(role: .destructive) {
                                deletionIDs = selectedIDs; batchDeleteFiles = true; showingBatchDeletion = true
                            } label: {
                                Label("删除本地文件", systemImage: "trash")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)
                            
                            Button(role: .destructive) {
                                deletionIDs = selectedIDs; batchDeleteFiles = false; showingBatchDeletion = true
                            } label: {
                                Label("仅清理记录", systemImage: "xmark.bin")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        .disabled(selectedIDs.isEmpty)
                        if engine.fileOperationID != nil { ProgressView("正在处理…") }
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .disabled(engine.fileOperationID != nil)
                }
            }
            .alert(batchDeleteFiles ? "删除文件与记录？" : "仅清理记录？", isPresented: $showingBatchDeletion) {
                Button("取消", role: .cancel) { showingBatchDeletion = false }
                Button("删除", role: .destructive) {
                    engine.deleteCompleted(ids: deletionIDs, includingFiles: batchDeleteFiles)
                    showingBatchDeletion = false
                    selectedIDs.removeAll()
                }
            } message: {
                Text(batchDeleteFiles ? "将从手机存储空间永久删除所选 \(deletionIDs.count) 个文件并清理记录。" : "仅从列表移除 \(deletionIDs.count) 条记录，已保存的文件依然保留在文件 App 中。")
            }
            .sheet(item: $panel, onDismiss: performPendingAction) { item in
                switch item.kind {
                case .menu:
                    CompletedFileMenu(name: item.record.localName ?? item.record.name) { action in
                        pendingAction = PendingFileAction(record: item.record, action: action)
                        panel = nil
                    } onCancel: { panel = nil }
                    .presentationDetents([.height(520), .large])
                    .presentationDragIndicator(.visible)
                case .preview:
                    if let access = item.access { FilePreviewSheet(url: access.url) { panel = nil } }
                case .share:
                    if let access = item.access { FileShareView(access: access) }
                case .move, .copy:
                    DestinationFolderPicker { folder in
                        if let folder { engine.transferFile(item.record, to: folder, moving: item.kind == .move) }
                        panel = nil
                    }
                }
            }
            .alert("重命名文件", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
                TextField("新文件名", text: $newName).textInputAutocapitalization(.never).autocorrectionDisabled()
                Button("取消", role: .cancel) { renaming = nil }
                Button("保存") { if let record = renaming { engine.renameFile(record, to: newName) }; renaming = nil }
            } message: { Text("请保留正确的扩展名；重名时不会覆盖旧文件。") }
            .alert(deletion?.action == .deleteFile ? "删除本地文件？" : "清理记录？", isPresented: Binding(get: { deletion != nil }, set: { if !$0 { deletion = nil } })) {
                Button("取消", role: .cancel) { deletion = nil }
                Button("删除", role: .destructive) {
                    if let request = deletion {
                        if request.action == .deleteFile { engine.deleteFile(request.record) }
                        else { engine.remove(request.record) }
                    }
                    deletion = nil
                }
            } message: {
                Text(deletion?.action == .deleteFile ? "将从设备删除文件及下载记录。" : "仅从列表移除此条记录，原文件保留。")
            }
        }
    }
    
    // Pristine Apple Card
    private var appleDashboardCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                HStack(spacing: 6) {
                    Circle()
                        .fill(activeRecord != nil ? Color.green : Color.gray.opacity(0.5))
                        .frame(width: 6, height: 6)
                    Text(activeRecord != nil ? "局域网极速直连" : "等待传输")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if let active = activeRecord, active.size > 0 {
                    Text("\(Int(active.progress * 100))%")
                        .font(.caption.weight(.semibold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(!engine.speedString.isEmpty ? engine.speedString : "0 KB/s")
                    .font(.system(size: 34, weight: .light, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer()
            }
            
            if let active = activeRecord {
                VStack(alignment: .leading, spacing: 6) {
                    Text(active.name)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if active.size > 0 {
                        ProgressView(value: active.progress)
                            .tint(Color.blue)
                    } else {
                        ProgressView()
                    }
                }
            }
        }
        .padding(18)
        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 18))
    }
    
    private func taskRow(_ record: DownloadRecord) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 12) {
                FileBadge(name: record.name)
                VStack(alignment: .leading, spacing: 4) {
                    Text(record.name).font(.subheadline.weight(.medium)).lineLimit(2)
                    if record.size > 0 { ProgressView(value: record.progress).tint(.blue) }
                    else if record.status == "downloading" { ProgressView() }
                    Text(status(record.status)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                if ["downloading", "queued", "scheduled"].contains(record.status) {
                    Button { engine.pause(record) } label: { Image(systemName: "pause.circle.fill").font(.title2).foregroundStyle(.secondary) }.buttonStyle(.borderless)
                } else if record.status == "paused" {
                    Button { engine.retry(record) } label: { Image(systemName: "play.circle.fill").font(.title2).foregroundStyle(.blue) }.buttonStyle(.borderless)
                }
            }
            if let error = record.error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                if ["failed", "interrupted", "cancelled"].contains(record.status) { Button("重试") { engine.retry(record) }.buttonStyle(.bordered) }
                Spacer()
                Menu {
                    if ["downloading", "queued", "scheduled", "paused"].contains(record.status) { Button("取消下载", role: .destructive) { engine.cancel(record) } }
                    if ["paused", "failed", "interrupted", "cancelled"].contains(record.status) { Button("从头下载") { engine.retry(record, fromBeginning: true) } }
                    if !["downloading", "pausing", "cancelling"].contains(record.status) { Button("删除记录", role: .destructive) { engine.remove(record) } }
                } label: { Image(systemName: "ellipsis").font(.subheadline).foregroundStyle(.secondary).frame(width: 32, height: 32) }
                .disabled(["pausing", "cancelling"].contains(record.status))
            }.font(.caption)
        }.padding(.vertical, 3)
    }
    
    private func completedRow(_ record: DownloadRecord) -> some View {
        HStack(spacing: 8) {
            Button {
                if selecting {
                    if !selectedIDs.insert(record.id).inserted { selectedIDs.remove(record.id) }
                } else { open(record, kind: .preview) }
            } label: {
                HStack(spacing: 12) {
                    if selecting {
                        Image(systemName: selectedIDs.contains(record.id) ? "checkmark.circle.fill" : "circle")
                            .font(.title3).foregroundStyle(.blue)
                    }
                    FileBadge(name: record.name)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(record.localName ?? record.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                        Text(sizeString(record.size)).font(.caption).foregroundStyle(.secondary)
                        if let error = record.error { Text(error).font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer(minLength: 0)
                }.frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
            if !selecting {
                Button { video?.close(); video = nil; panel = FilePanel(kind: .menu, record: record) } label: {
                    Image(systemName: "ellipsis").font(.system(size: 18)).foregroundStyle(.secondary).frame(width: 32, height: 32)
                }.buttonStyle(.borderless)
            }
        }.padding(.vertical, 3)
    }
    
    private func open(_ record: DownloadRecord, kind: FilePanel.Kind) {
        do {
            let access = try engine.accessibleFile(record)
            if kind == .preview && FileCategory.classify(access.url.lastPathComponent) == .video {
                video?.close()
                video = FloatingVideoSession(access: access)
            } else {
                video?.close(); video = nil
                panel = FilePanel(kind: kind, record: record, access: access)
            }
        }
        catch { engine.notice = error.localizedDescription }
    }
    
    private func performPendingAction() {
        guard let request = pendingAction else { return }
        pendingAction = nil
        switch request.action {
        case .share: open(request.record, kind: .share)
        case .move: open(request.record, kind: .move)
        case .copy: open(request.record, kind: .copy)
        case .rename:
            newName = request.record.localName ?? request.record.name
            renaming = request.record
        case .deleteFile, .deleteRecord: deletion = request
        }
    }
    
    private func status(_ status: String) -> String {
        ["queued": "等待队列", "scheduled": "已排队 · 传输中", "downloading": "高速传输中", "failed": "传输失败", "interrupted": "已中断", "paused": "已暂停", "pausing": "正在暂停…", "cancelling": "正在取消…", "cancelled": "已取消"][status] ?? status
    }
}

// MARK: - Files View

struct FilesView: View {
    @ObservedObject var servers: ServerStore
    @ObservedObject var engine: DownloadEngine
    let showServers: () -> Void
    
    @State private var files: [VideoFile] = []
    @State private var selected = Set<String>()
    @State private var path: [String] = []
    @State private var search = ""
    @State private var category = FileCategory.all
    @State private var includeSubfolders = true
    @State private var showFilter = false
    @State private var loading = false
    @State private var error: String?
    @State private var requestID = UUID()
    
    private var directory: URL? {
        guard var url = servers.selected?.rootURL else { return nil }
        for component in path { url.appendPathComponent(component, isDirectory: true) }
        return url
    }
    private var recursiveSearch: Bool { category != .all && includeSubfolders }
    private var filtered: [VideoFile] {
        files.filter { (category == .all || (!$0.isDirectory && $0.category == category)) && (search.isEmpty || ($0.name.localizedCaseInsensitiveContains(search) || (recursiveSearch && $0.path.localizedCaseInsensitiveContains(search)))) }
    }
    private var selectable: [VideoFile] { filtered.filter { !$0.isDirectory } }
    private var selectedFiles: [VideoFile] { files.filter { selected.contains($0.id) && !$0.isDirectory } }
    private var selectedSummary: String {
        let known = selectedFiles.reduce(Int64(0)) { value, file in
            let result = value.addingReportingOverflow(max(0, file.size))
            return result.overflow ? Int64.max : result.partialValue
        }
        return "已选 \(selectedFiles.count) 项 · \(sizeString(known))"
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    // Minimalist Host Switcher
                    Menu {
                        ForEach(servers.servers) { server in Button(server.name) { path = []; servers.select(server) } }
                        Button("管理共享主机…", action: showServers)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "macbook.and.iphone").font(.subheadline).foregroundStyle(.secondary)
                            Text(servers.selected?.name ?? "选择共享电脑").font(.subheadline.weight(.medium))
                            Spacer()
                            Image(systemName: "chevron.up.chevron.down").font(.caption2).foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .background(Color(uiColor: .secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                    
                    // Search Bar
                    HStack {
                        Image(systemName: "magnifyingglass").font(.caption).foregroundStyle(.secondary)
                        TextField(recursiveSearch ? "搜索文件名或子路径" : "搜索文件", text: $search).font(.subheadline).autocorrectionDisabled()
                        if !search.isEmpty { Button { search = "" } label: { Image(systemName: "xmark.circle.fill").font(.caption) } }
                    }
                    .padding(8)
                    .background(Color(uiColor: .tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                    
                    // Category Chips (Frosted Pills)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(FileCategory.allCases) { item in
                                Button { category = item } label: {
                                    HStack(spacing: 4) {
                                        Image(systemName: item.symbol).font(.caption2)
                                        Text(item.rawValue).font(.caption.weight(.medium))
                                    }
                                    .padding(.horizontal, 11).padding(.vertical, 6)
                                    .background(category == item ? Color.primary : Color(uiColor: .secondarySystemGroupedBackground), in: Capsule())
                                    .foregroundStyle(category == item ? Color(uiColor: .systemBackground) : Color.primary)
                                }
                            }
                        }
                    }
                    
                    if category != .all {
                        Toggle("包含所有层级子文件", isOn: $includeSubfolders).font(.caption)
                    }
                    
                    // Breadcrumbs & Select All
                    HStack {
                        if !path.isEmpty { Button { path.removeLast() } label: { Image(systemName: "chevron.left") }.accessibilityLabel("上一级") }
                        Button { path = [] } label: { Image(systemName: "house") }.accessibilityLabel("根目录")
                        Text(path.isEmpty ? "共享根目录" : path.joined(separator: " / ")).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
                        Spacer()
                        Button(selected.isSuperset(of: Set(selectable.map(\.id))) && !selectable.isEmpty ? "取消全选" : "全选") {
                            let ids = Set(selectable.map(\.id))
                            if selected.isSuperset(of: ids) { selected.subtract(ids) } else { selected.formUnion(ids) }
                        }.font(.caption.weight(.medium)).disabled(selectable.isEmpty)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 6)
                
                if let error {
                    VStack(spacing: 12) {
                        Image(systemName: "wifi.exclamationmark").font(.title).foregroundStyle(.orange)
                        Text(error).font(.subheadline).multilineTextAlignment(.center)
                        Button("重新连接") { Task { await load() } }.buttonStyle(.borderedProminent)
                    }.padding()
                }
                
                List {
                    ForEach(filtered) { file in
                        Button {
                            if file.isDirectory { path.append(file.name) }
                            else if !selected.insert(file.id).inserted { selected.remove(file.id) }
                        } label: {
                            HStack(spacing: 12) {
                                if !file.isDirectory {
                                    Image(systemName: selected.contains(file.id) ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selected.contains(file.id) ? Color.blue : Color.gray.opacity(0.4)).font(.subheadline)
                                }
                                FileBadge(name: file.name, directory: file.isDirectory)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(file.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary).lineLimit(2)
                                    if recursiveSearch, let directory {
                                        Text(relativeFolder(file, from: directory)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    HStack {
                                        Text(file.isDirectory ? "文件夹" : file.category.rawValue)
                                        Spacer()
                                        if !file.isDirectory { Text(sizeString(file.size)) }
                                    }.font(.caption2).foregroundStyle(.secondary)
                                }
                                if file.isDirectory { Image(systemName: "chevron.right").foregroundStyle(.secondary).font(.caption2) }
                            }.padding(.vertical, 3)
                        }.listRowBackground(Color(uiColor: .secondarySystemGroupedBackground))
                    }
                }
                .listStyle(.plain)
                .refreshable { if !loading { await load() } }
                .overlay {
                    if loading { ProgressView().padding().background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12)) }
                    else if filtered.isEmpty && error == nil {
                        VStack(spacing: 10) {
                            Image(systemName: servers.selected == nil ? "network" : "folder")
                                .font(.title)
                            Text(servers.selected == nil ? "请先添加共享电脑" : "当前目录没有文件")
                                .font(.subheadline)
                            if servers.selected == nil { Button("添加电脑", action: showServers).buttonStyle(.borderedProminent) }
                        }.foregroundStyle(.secondary)
                    }
                }
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("文件库").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) { Button(action: showServers) { Image(systemName: "macbook.and.iphone") }.accessibilityLabel("主机设置") }
                ToolbarItem(placement: .navigationBarLeading) { Button { Task { await load() } } label: { Image(systemName: "arrow.clockwise") }.disabled(loading || directory == nil).accessibilityLabel("刷新") }
            }
            .safeAreaInset(edge: .bottom) {
                if !selectedFiles.isEmpty {
                    HStack {
                        Text(selectedSummary).font(.caption.weight(.semibold)).foregroundStyle(.blue)
                        Spacer()
                        Button("加入传输队列") {
                            if engine.enqueue(selectedFiles) > 0 { selected.removeAll() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.blue)
                        .disabled(selectedFiles.isEmpty || engine.restoring)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                }
            }
        }
        .task(id: directory?.absoluteString) { await load() }
        .onChange(of: recursiveSearch) { _ in Task { await load() } }
    }
    
    private func relativeFolder(_ file: VideoFile, from: URL) -> String {
        guard let url = URL(string: file.url), DirectoryParser.sameOrigin(url, from) else { return "" }
        let rootCount = from.pathComponents.count
        let fileCount = url.pathComponents.count
        guard fileCount > rootCount + 1 else { return "" }
        return url.pathComponents[rootCount..<(fileCount - 1)].joined(separator: "/")
    }
    
    private func load() async {
        guard let directory, let root = servers.selected?.rootURL else {
            files = []; loading = false; return
        }
        let currentID = UUID()
        requestID = currentID
        loading = true
        error = nil
        do {
            let loaded: [VideoFile]
            if recursiveSearch {
                loaded = try await DirectoryBrowser().loadRecursively(directory: directory, root: root)
            } else {
                loaded = try await DirectoryBrowser().load(directory: directory, root: root)
            }
            guard requestID == currentID else { return }
            files = loaded
            loading = false
        } catch {
            guard requestID == currentID else { return }
            self.error = error.localizedDescription
            loading = false
        }
    }
}

// MARK: - Servers View

struct ServersView: View {
    @ObservedObject var store: ServerStore
    @State private var name = ""
    @State private var address = ""
    @State private var port = "8080"
    @State private var editing: Server?
    @State private var deleting: Server?
    @State private var error: String?
    
    var body: some View {
        NavigationStack {
            Form {
                Section("已添加的主机") {
                    ForEach(store.servers) { server in
                        Button { store.select(server) } label: {
                            HStack {
                                Image(systemName: "macbook.and.iphone")
                                    .foregroundStyle(store.selectedID == server.id ? .blue : .secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(server.name).font(.subheadline.weight(.medium)).foregroundStyle(.primary)
                                    Text(server.address).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if store.selectedID == server.id {
                                    Image(systemName: "checkmark").font(.subheadline.weight(.semibold)).foregroundStyle(.blue)
                                }
                            }
                        }
                        .swipeActions {
                            Button("编辑") { edit(server) }.tint(.orange)
                            Button("删除", role: .destructive) { deleting = server }
                        }
                    }
                }
                
                Section(editing == nil ? "添加主机" : "编辑主机") {
                    TextField("主机名称", text: $name)
                    TextField("IP 地址，例如 192.168.1.100", text: $address)
                        .keyboardType(.URL).textInputAutocapitalization(.never).autocorrectionDisabled()
                    TextField("端口号", text: $port).keyboardType(.numberPad)
                    if let error { Text(error).font(.caption).foregroundStyle(.red) }
                    Button { save() } label: {
                        Text(editing == nil ? "保存并连接" : "保存修改").frame(maxWidth: .infinity).padding(4)
                    }
                    .buttonStyle(.borderedProminent)
                    if editing != nil { Button("取消编辑") { reset() } }
                }
                
                Section("关于 闪传") {
                    LabeledContent("版本", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0")
                    LabeledContent("构建", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1")
                    LabeledContent("传输架构", value: "双核自适应 (前台Turbo 60MB/s + 锁屏保活)")
                }
                
                Section("使用说明") {
                    Text("1. 在电脑端将 Start-FlashLAN.bat 放入待共享文件夹运行。")
                    Text("2. 确保 iPhone 与电脑连接同一 Wi-Fi，输入电脑提示的 IP 与端口。")
                    Text("3. 开启【息屏挂机】可在屏幕纯黑零功耗下以 55–60 MB/s 满速持续传输。")
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .navigationTitle("共享主机").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button { reset() } label: { Image(systemName: "plus") }
                }
            }
            .alert("确认删除该主机？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("删除", role: .destructive) { if let deleting { store.delete(deleting) }; deleting = nil }
                Button("取消", role: .cancel) { deleting = nil }
            }
        }
    }
    
    private func edit(_ server: Server) {
        editing = server
        name = server.name
        if let parts = URLComponents(string: server.address) {
            address = parts.host ?? ""
            port = parts.port.map(String.init) ?? "8080"
        }
    }
    private func reset() { editing = nil; name = ""; address = ""; port = "8080"; error = nil }
    private func save() {
        error = nil
        let host = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let portInt = Int(port.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 8080
        guard !host.isEmpty else { error = "请输入电脑 IP 地址"; return }
        let full = "http://\(host):\(portInt)/"
        do {
            let normalized = try Server.normalizedAddress(full)
            let serverName = name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "我的电脑" : name
            let newServer = Server(id: editing?.id ?? UUID(), name: serverName, address: normalized)
            store.save(newServer)
            reset()
        } catch { self.error = error.localizedDescription }
    }
}

// MARK: - Supporting Views

struct FileBadge: View {
    let name: String
    var directory: Bool = false
    
    private var category: FileCategory { FileCategory.classify(name) }
    
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(directory ? Color.orange.opacity(0.12) : category.color.opacity(0.12))
                .frame(width: 38, height: 38)
            Image(systemName: directory ? "folder.fill" : category.symbol)
                .font(.system(size: 17))
                .foregroundStyle(directory ? Color.orange : category.color)
        }
    }
}

struct FilePanel: Identifiable {
    enum Kind { case menu, preview, share, move, copy }
    let id = UUID()
    let kind: Kind
    let record: DownloadRecord
    var access: LocalFileAccess? = nil
}

struct PendingFileAction {
    enum Action { case share, move, copy, rename, deleteFile, deleteRecord }
    let record: DownloadRecord
    let action: Action
}

struct CompletedFileMenu: View {
    let name: String
    let onSelect: (PendingFileAction.Action) -> Void
    let onCancel: () -> Void
    
    var body: some View {
        NavigationStack {
            List {
                Section(name) {
                    Button { onSelect(.share) } label: { Label("分享到其他应用", systemImage: "square.and.arrow.up") }
                    Button { onSelect(.copy) } label: { Label("复制到文件夹…", systemImage: "doc.on.doc") }
                    Button { onSelect(.move) } label: { Label("移动到文件夹…", systemImage: "folder") }
                    Button { onSelect(.rename) } label: { Label("重命名…", systemImage: "pencil") }
                }
                Section {
                    Button(role: .destructive) { onSelect(.deleteFile) } label: { Label("删除本地文件", systemImage: "trash") }
                    Button(role: .destructive) { onSelect(.deleteRecord) } label: { Label("仅清理记录", systemImage: "xmark.bin") }
                }
            }
            .navigationTitle("文件操作")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("关闭", action: onCancel) } }
        }
    }
}

struct FilePreviewSheet: UIViewControllerRepresentable {
    let url: URL
    let onDismiss: () -> Void
    
    func makeCoordinator() -> Coordinator { Coordinator(url: url, onDismiss: onDismiss) }
    func makeUIViewController(context: Context) -> UINavigationController {
        let preview = QLPreviewController()
        preview.dataSource = context.coordinator
        let nav = UINavigationController(rootViewController: preview)
        preview.navigationItem.leftBarButtonItem = UIBarButtonItem(title: "完成", style: .done, target: context.coordinator, action: #selector(Coordinator.done))
        return nav
    }
    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}
    
    final class Coordinator: NSObject, QLPreviewControllerDataSource {
        let url: URL
        let onDismiss: () -> Void
        init(url: URL, onDismiss: @escaping () -> Void) { self.url = url; self.onDismiss = onDismiss }
        func numberOfPreviewItems(in controller: QLPreviewController) -> Int { 1 }
        func previewController(_ controller: QLPreviewController, previewItemAt index: Int) -> QLPreviewItem { url as NSURL }
        @objc func done() { onDismiss() }
    }
}

struct FileShareView: UIViewControllerRepresentable {
    let access: LocalFileAccess
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [access.url], applicationActivities: nil)
    }
    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

struct DestinationFolderPicker: UIViewControllerRepresentable {
    let onPick: (URL?) -> Void
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.delegate = context.coordinator
        picker.allowsMultipleSelection = false
        return picker
    }
    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}
    
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let onPick: (URL?) -> Void
        init(onPick: @escaping (URL?) -> Void) { self.onPick = onPick }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            onPick(urls.first)
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            onPick(nil)
        }
    }
}
