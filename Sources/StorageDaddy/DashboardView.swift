import SwiftUI
import AppKit
import DiskCore

@MainActor final class DashboardModel: ObservableObject {
    @Published var report: SystemStorageReport?
    @Published var health: [NVMeHealthInfo] = []
    @Published var loading = false

    func loadIfNeeded() {
        if report == nil { refresh() }
    }

    func refresh() {
        guard !loading else { return }
        loading = true
        Task.detached(priority: .userInitiated) {
            let report = SystemInventory.collect()
            let health = NVMeHealthReader.collect()
            await MainActor.run {
                self.report = report
                self.health = health
                self.loading = false
            }
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject var m: ExplorerModel
    @ObservedObject var dashboard: DashboardModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Dashboard").font(.largeTitle.weight(.semibold))
                DoodleArt(topic: .overview).frame(width: 72, height: 72)
                Spacer()
                if let report = dashboard.report {
                    Text("Checked \(report.collectedAt, format: .dateTime.hour().minute().second())")
                        .font(.caption).foregroundStyle(Tints.secondaryText)
                }
                Button("Refresh", action: dashboard.refresh).disabled(dashboard.loading || m.busy)
                if dashboard.loading { ProgressView().controlSize(.small) }
            }
            Text("Mounted volumes, shared APFS container space, and what the drive reports about itself. Read-only — nothing is cleaned up from here.")
                .foregroundStyle(Tints.secondaryText)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let report = dashboard.report {
                        ForEach(report.containers) { container in
                            ContainerCard(container: container)
                        }
                        volumesSection(report.volumes)
                        healthSection
                        pressureSection(report.pressure)
                    } else {
                        StorageEmptyView("Reading system storage…", systemImage: "internaldrive", description: Text("Collecting volume, device and pressure information."))
                    }
                }
            }
        }
        .padding(24)
        .background(Color.black)
        .buttonStyle(StorageButtonStyle())
        .task { dashboard.loadIfNeeded() }
    }

    // MARK: - Volumes

    private func volumesSection(_ volumes: [MountedVolumeInfo]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("MOUNTED VOLUMES").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(Tints.secondaryText)
            ForEach(volumes, id: \.mountPoint) { volume in
                HStack(spacing: 12) {
                    Image(systemName: volumeIcon(volume))
                        .foregroundStyle(volume.isSystem ? Tints.secondaryText : Tints.electricBlue)
                        .frame(width: 22)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(volume.name).font(.callout.weight(.medium))
                            Text(volume.fsDisplayName).font(.caption2)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Tints.secondaryText.opacity(0.12), in: Capsule())
                            ForEach(volumeBadges(volume), id: \.self) { badge in
                                Text(badge).font(.caption2).foregroundStyle(Tints.yellow)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(Tints.yellow.opacity(0.12), in: Capsule())
                            }
                        }
                        Text(StorageLabels.location(volume.mountPoint))
                            .font(.caption).foregroundStyle(Tints.secondaryText)
                            .lineLimit(1).truncationMode(.middle).help(volume.mountPoint)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 2) {
                        if let total = volume.totalCapacity, let free = volume.availableCapacity {
                            Text("\(DiskFormat.bytes(free)) free of \(DiskFormat.bytes(total))")
                                .font(.callout).monospacedDigit()
                            if let purgeable = volume.purgeableCapacity, purgeable > 0 {
                                Text("\(DiskFormat.bytes(purgeable)) purgeable")
                                    .font(.caption2).foregroundStyle(Tints.cyan)
                                    .help("Space macOS can reclaim on demand — local snapshots, caches and cloud-only copies. Counted as used, not as free.")
                            }
                        } else {
                            Text("Capacity unavailable").font(.caption).foregroundStyle(Tints.secondaryText)
                        }
                    }
                }
                .padding(.vertical, 7).padding(.horizontal, 10)
                .background(Tints.secondaryText.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }

    private func volumeIcon(_ volume: MountedVolumeInfo) -> String {
        if volume.isStartupData { return "internaldrive.fill" }
        if volume.isNetwork { return "network" }
        if volume.isDiskImage { return "doc.zipper" }
        if volume.isSystem { return "gearshape.2" }
        return volume.isRemovable || !volume.isInternal ? "externaldrive.fill" : "internaldrive"
    }

    private func volumeBadges(_ volume: MountedVolumeInfo) -> [String] {
        var badges: [String] = []
        if volume.isEncrypted == true { badges.append("Encrypted") }
        if volume.isReadOnly { badges.append("Read-only") }
        if volume.isDiskImage { badges.append("Disk image") }
        if volume.isSystem { badges.append("System") }
        return badges
    }

    // MARK: - Drive health

    private var healthSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("DRIVES").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(Tints.secondaryText)
            let physical = dashboard.report?.devices.filter { !$0.isDiskImage } ?? []
            ForEach(Array(physical.enumerated()), id: \.offset) { _, device in
                let health = dashboard.health.first { $0.deviceName == device.productName }
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "memorychip").foregroundStyle(Tints.mint).frame(width: 22)
                        Text(device.productName).font(.callout.weight(.medium))
                        if device.isSolidState {
                            Text("SSD").font(.caption2)
                                .padding(.horizontal, 5).padding(.vertical, 1)
                                .background(Tints.mint.opacity(0.12), in: Capsule())
                        }
                        Spacer()
                        if let health {
                            Text(health.statusLabel)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(health.isHealthy ? Tints.mint : Tints.coral)
                        } else {
                            Text(device.smartCapable ? "SMART read unavailable" : "No SMART interface")
                                .font(.caption).foregroundStyle(Tints.secondaryText)
                        }
                    }
                    if let health {
                        Divider().overlay(Tints.secondaryText.opacity(0.15))
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 10) {
                            healthMetric("Wear used", "\(health.percentUsed)%", help: "The drive's own endurance estimate. 100% means the rated write endurance is consumed; warranty guidance, not a failure prediction.")
                            healthMetric("Spare blocks", "\(health.availableSparePercent)%", help: "Reserve flash remaining for remapping worn cells. The drive warns at \(health.availableSpareThreshold)%.")
                            if let temp = health.temperatureCelsius {
                                healthMetric("Temperature", String(format: "%.0f °C", temp))
                            }
                            if let written = health.dataWrittenBytes {
                                healthMetric("Lifetime written", DiskFormat.bytes(Int64(clamping: written)))
                            }
                            if let read = health.dataReadBytes {
                                healthMetric("Lifetime read", DiskFormat.bytes(Int64(clamping: read)))
                            }
                            healthMetric("Power on", "\(health.powerOnHours.formatted()) h")
                            healthMetric("Unsafe shutdowns", health.unsafeShutdowns.formatted(), help: "Power losses without a clean flush. High counts can age the drive.")
                            healthMetric("Media errors", health.mediaErrors.formatted())
                        }
                        ForEach(health.warningDescriptions, id: \.self) { warning in
                            Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Tints.coral)
                        }
                    }
                }
                .padding(12)
                .background(Tints.secondaryText.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            }
            if physical.isEmpty {
                Text("No physical storage devices were found in the I/O registry.")
                    .font(.caption).foregroundStyle(Tints.secondaryText)
            }
        }
    }

    private func healthMetric(_ label: String, _ value: String, help: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.callout.monospacedDigit())
            Text(label).font(.caption2).foregroundStyle(Tints.secondaryText)
        }
        .ifHelp(help)
    }

    // MARK: - Pressure

    private func pressureSection(_ pressure: PressureInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PRESSURE").font(.system(size: 10, weight: .semibold)).tracking(1).foregroundStyle(Tints.secondaryText)
            VStack(alignment: .leading, spacing: 10) {
                if let total = pressure.swapTotalBytes {
                    HStack {
                        Label("Swap", systemImage: "arrow.triangle.swap").foregroundStyle(Tints.electricBlue)
                        Spacer()
                        Text(pressure.swapIsActive
                             ? "\(DiskFormat.bytes(Int64(clamping: pressure.swapUsedBytes ?? 0))) used of \(DiskFormat.bytes(Int64(clamping: total)))"
                             : "Not in use · \(DiskFormat.bytes(Int64(clamping: total))) reserved")
                            .font(.callout).monospacedDigit()
                    }
                    Text("Swap writes reach the SSD; sustained swap use adds wear.")
                        .font(.caption2).foregroundStyle(Tints.secondaryText)
                }
                if let headroom = pressure.memoryHeadroomPercent {
                    HStack {
                        Label("Memory headroom", systemImage: "memorychip").foregroundStyle(Tints.cyan)
                        Spacer()
                        Text("\(headroom)%").font(.callout).monospacedDigit()
                    }
                    Text("Kernel estimate of remaining memory capacity (kern.memorystatus_level). Higher means more headroom.")
                        .font(.caption2).foregroundStyle(Tints.secondaryText)
                }
                if let snapshots = pressure.localSnapshotNames {
                    HStack {
                        Label("Local snapshots", systemImage: "camera.aperture").foregroundStyle(Tints.yellow)
                        Spacer()
                        Text("\(snapshots.count)").font(.callout).monospacedDigit()
                    }
                    Text("APFS snapshots share blocks with live data and count as purgeable space, not as free.")
                        .font(.caption2).foregroundStyle(Tints.secondaryText)
                }
                if let read = pressure.ioReadBytesSinceBoot, let written = pressure.ioWriteBytesSinceBoot {
                    HStack {
                        Label("Disk I/O since boot", systemImage: "arrow.up.arrow.down").foregroundStyle(Tints.secondaryText)
                        Spacer()
                        Text("\(DiskFormat.bytes(Int64(clamping: read))) read · \(DiskFormat.bytes(Int64(clamping: written))) written")
                            .font(.callout).monospacedDigit()
                    }
                }
                if let boot = pressure.bootTime {
                    HStack {
                        Label("Booted", systemImage: "power").foregroundStyle(Tints.secondaryText)
                        Spacer()
                        Text(boot.formatted(.relative(presentation: .named))).font(.callout)
                    }
                }
            }
            .padding(12)
            .background(Tints.secondaryText.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

private struct ContainerCard: View {
    let container: APFSContainerInfo
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(container.volumeNames.first ?? container.name).font(.headline)
                Text("APFS container \(container.name)").font(.caption).foregroundStyle(Tints.secondaryText)
                Spacer()
            }
            if let total = container.totalCapacity, let free = container.freeCapacity {
                let used = max(0, total - free)
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        RoundedRectangle(cornerRadius: 5).fill(Tints.secondaryText.opacity(0.12))
                        RoundedRectangle(cornerRadius: 5).fill(Tints.mint)
                            .frame(width: max(2, g.size.width * Double(used) / Double(max(1, total))))
                    }
                }.frame(height: 14)
                HStack {
                    Text("\(DiskFormat.bytes(used)) used of \(DiskFormat.bytes(total))").font(.callout).monospacedDigit()
                    Spacer()
                    Text("\(DiskFormat.bytes(free)) free").font(.callout).monospacedDigit().foregroundStyle(Tints.mint)
                }
                if let purgeable = container.purgeableCapacity, purgeable > 0 {
                    Text("+ \(DiskFormat.bytes(purgeable)) purgeable — macOS reclaims it when space is needed")
                        .font(.caption).foregroundStyle(Tints.cyan)
                }
                if container.volumeNames.count > 1 {
                    Text("Shared by \(container.volumeNames.joined(separator: ", ")) — APFS volumes in one container share the same pool, so this space is counted once.")
                        .font(.caption2).foregroundStyle(Tints.secondaryText)
                }
            } else {
                Text("Capacity unavailable").font(.caption).foregroundStyle(Tints.secondaryText)
            }
        }
        .padding(14)
        .background(Tints.mint.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Tints.mint.opacity(0.3), lineWidth: 1))
    }
}

private extension View {
    @ViewBuilder func ifHelp(_ text: String?) -> some View {
        if let text { self.help(text) } else { self }
    }
}

extension APFSContainerInfo: Identifiable { public var id: String { name } }
