import SwiftUI
import Foundation
import CoreFoundation
import Darwin
import UIKit
import UniformTypeIdentifiers

private typealias MGCopyAnswerFunction = @convention(c) (CFString) -> Unmanaged<CFTypeRef>?

private struct GestaltResult: Identifiable, Codable {
    let key: String
    let value: String
    var id: String { key }
}

private struct GestaltField: Identifiable {
    let key: String
    let description: String
    var id: String { key }
}

private struct GestaltPreset: Identifiable {
    let name: String
    let symbol: String
    let description: String
    let fields: [String]
    var id: String { name }
}

private struct InspectionSnapshot: Identifiable, Codable {
    let id: UUID
    let date: Date
    let device: String
    let version: String
    let build: String
    let results: [GestaltResult]

    var title: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

private struct JSONExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data

    init(data: Data) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}

@MainActor
private final class MobileGestaltInspectorModel: ObservableObject {
    @Published private(set) var results: [GestaltResult] = []
    @Published private(set) var status = "Not inspected"
    @Published private(set) var detail = "Tap Refresh to query the read-only MobileGestalt interface."
    @Published private(set) var appGroupAvailable = false
    @Published private(set) var appGroupDetail = "Checking App Group access…"
    @Published private(set) var favorites: Set<String> = []
    @Published private(set) var snapshots: [InspectionSnapshot] = []

    private let appGroupIdentifier = "group.com.bullshitbox.shared"
    private var libraryHandle: UnsafeMutableRawPointer?

    let fields: [GestaltField] = [
        .init(key: "ProductType", description: "Hardware product identifier, such as iPhone14,5."),
        .init(key: "ProductVersion", description: "Installed iOS version string."),
        .init(key: "BuildVersion", description: "Operating system build identifier."),
        .init(key: "DeviceClass", description: "Broad device family classification."),
        .init(key: "MarketingName", description: "Marketing-facing device name, when exposed."),
        .init(key: "HasBaseband", description: "Whether the device reports a cellular baseband."),
        .init(key: "HasNFC", description: "Whether the device reports NFC capability."),
        .init(key: "HasAppleNeuralEngine", description: "Whether the device reports a Neural Engine."),
        .init(key: "IsSimulator", description: "Whether the environment reports itself as a simulator."),
        .init(key: "ProductName", description: "Product family name."),
        .init(key: "CPUArchitecture", description: "Reported CPU architecture identifier."),
        .init(key: "DeviceSupports3DTouch", description: "Reported 3D Touch capability flag."),
        .init(key: "DisplayIsRounded", description: "Reported rounded-display capability flag."),
        .init(key: "HasAOD", description: "Always-On Display capability key; availability varies by OS."),
        .init(key: "DynamicIsland", description: "Dynamic Island capability key; availability varies by OS."),
        .init(key: "PearlIDCapability", description: "Face authentication capability metadata."),
        .init(key: "HasSEP", description: "Secure Enclave capability metadata."),
        .init(key: "HasSiri", description: "Siri capability metadata."),
        .init(key: "SiriIsEnabled", description: "Siri enabled-state metadata, if exposed."),
        .init(key: "InternalBuild", description: "Whether the OS reports an internal build."),
        .init(key: "ReleaseType", description: "OS release channel metadata."),
        .init(key: "RegionCode", description: "Device region metadata."),
        .init(key: "RegionInfo", description: "Additional region metadata."),
        .init(key: "Language", description: "Primary language metadata."),
        .init(key: "SupportsForceTouch", description: "Force Touch support metadata."),
        .init(key: "DisplayZoomEnabled", description: "Display zoom metadata, if exposed."),
        .init(key: "HasCameraFlash", description: "Camera flash capability metadata."),
        .init(key: "RearCameraCount", description: "Reported rear camera count."),
        .init(key: "FrontCameraCount", description: "Reported front camera count."),
        .init(key: "HasLiDAR", description: "LiDAR capability metadata."),
        .init(key: "HasSatellite", description: "Satellite feature capability metadata."),
        .init(key: "HasUSBHost", description: "USB host capability metadata."),
        .init(key: "HasWirelessCharging", description: "Wireless charging capability metadata.")
    ]

    let presets: [GestaltPreset] = [
        .init(
            name: "Dynamic Island",
            symbol: "capsule.portrait",
            description: "Inspect device identity and display-related capability metadata. This preset does not enable the feature.",
            fields: ["ProductType", "ProductVersion", "BuildVersion", "DisplayIsRounded", "DynamicIsland"]
        ),
        .init(
            name: "Always-On Display",
            symbol: "sun.max",
            description: "Review display and device capability fields. A returned value is informational, not an activation switch.",
            fields: ["ProductType", "DisplayIsRounded", "HasAOD"]
        ),
        .init(
            name: "Action Button",
            symbol: "button.horizontal",
            description: "A research grouping for hardware identity and related capability metadata.",
            fields: ["ProductType", "DeviceClass", "ProductName"]
        ),
        .init(
            name: "Siri AI",
            symbol: "sparkles",
            description: "Inspect Siri-related metadata and device identity. This cannot add unsupported AI features.",
            fields: ["ProductType", "ProductVersion", "HasSiri", "SiriIsEnabled", "HasAppleNeuralEngine"]
        ),
        .init(
            name: "Boot Chime",
            symbol: "speaker.wave.2",
            description: "A saved research grouping for hardware and OS metadata; it does not change startup audio.",
            fields: ["ProductType", "ProductVersion", "BuildVersion", "DeviceClass"]
        )
    ]

    init() {
        favorites = Set(UserDefaults.standard.stringArray(forKey: "bb.mg.favorites") ?? [])
        loadSnapshots()
    }

    func inspect() {
        results = []
        status = "Inspecting"
        detail = "Looking for the MobileGestalt read interface…"
        checkAppGroup()

        guard let handle = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_NOW) else {
            status = "Unavailable"
            detail = "Could not load MobileGestalt. The library may not be accessible to this app."
            return
        }

        libraryHandle = handle

        guard let symbol = dlsym(handle, "MGCopyAnswer") else {
            status = "Unavailable"
            detail = "The library loaded, but MGCopyAnswer was not found."
            return
        }

        let copyAnswer = unsafeBitCast(symbol, to: MGCopyAnswerFunction.self)
        var found: [GestaltResult] = []

        for field in fields {
            guard let unmanagedValue = copyAnswer(field.key as CFString) else {
                continue
            }

            let value = unmanagedValue.takeRetainedValue()
            found.append(
                GestaltResult(
                    key: field.key,
                    value: String(describing: value)
                )
            )
        }

        results = found
        status = "Inspection finished"
        detail = "Received values for \(found.count) of \(fields.count) catalog fields. No system files were changed."
    }

    func checkAppGroup() {
        if let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) {
            appGroupAvailable = true
            appGroupDetail = "App Group container is available at: \(container.lastPathComponent)"
        } else {
            appGroupAvailable = false
            appGroupDetail = "No container access for \(appGroupIdentifier). This build does not have a usable matching App Group entitlement."
        }
    }

    func toggleFavorite(_ key: String) {
        if favorites.contains(key) {
            favorites.remove(key)
        } else {
            favorites.insert(key)
        }

        UserDefaults.standard.set(
            Array(favorites).sorted(),
            forKey: "bb.mg.favorites"
        )
    }

    func saveSnapshot() {
        let snapshot = InspectionSnapshot(
            id: UUID(),
            date: Date(),
            device: value(for: "ProductType"),
            version: value(for: "ProductVersion"),
            build: value(for: "BuildVersion"),
            results: results
        )

        snapshots.insert(snapshot, at: 0)
        persistSnapshots()
    }

    func restoreSnapshot(_ snapshot: InspectionSnapshot) {
        results = snapshot.results
        status = "Snapshot loaded"
        detail = "Showing saved inspection data from \(snapshot.title). This only restores the on-screen snapshot; it does not change device settings."
    }

    func deleteSnapshot(_ snapshot: InspectionSnapshot) {
        snapshots.removeAll { $0.id == snapshot.id }
        persistSnapshots()
    }

    func exportData() -> Data? {
        let payload: [String: Any] = [
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "device": value(for: "ProductType"),
            "productVersion": value(for: "ProductVersion"),
            "buildVersion": value(for: "BuildVersion"),
            "readOnly": true,
            "results": results.map {
                ["key": $0.key, "value": $0.value]
            }
        ]

        return try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    func copy(_ result: GestaltResult) {
        UIPasteboard.general.string = result.value
    }

    func copyAll() {
        UIPasteboard.general.string = results
            .map { "\($0.key): \($0.value)" }
            .joined(separator: "\n")
    }

    func value(for key: String) -> String {
        results.first(where: { $0.key == key })?.value ?? "Not returned"
    }

    private func persistSnapshots() {
        guard let data = try? JSONEncoder().encode(snapshots) else {
            return
        }

        UserDefaults.standard.set(data, forKey: "bb.mg.snapshots")
    }

    private func loadSnapshots() {
        guard
            let data = UserDefaults.standard.data(forKey: "bb.mg.snapshots"),
            let decoded = try? JSONDecoder().decode([InspectionSnapshot].self, from: data)
        else {
            return
        }

        snapshots = decoded
    }
}

struct MobileGestaltInspectorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = MobileGestaltInspectorModel()

    @State private var searchText = ""
    @State private var copiedMessage = ""
    @State private var selectedPreset: GestaltPreset?
    @State private var showingSnapshots = false
    @State private var exportDocument: JSONExportDocument?
    @State private var showingExporter = false
    @State private var exportError = ""

    private let green = Color(red: 0.42, green: 1.0, blue: 0.35)
    private let background = Color(red: 0.035, green: 0.045, blue: 0.055)

    private var filteredResults: [GestaltResult] {
        let searched = searchText.isEmpty
            ? model.results
            : model.results.filter {
                $0.key.localizedCaseInsensitiveContains(searchText) ||
                $0.value.localizedCaseInsensitiveContains(searchText)
            }

        return searched.sorted {
            let firstFavorite = model.favorites.contains($0.key)
            let secondFavorite = model.favorites.contains($1.key)

            if firstFavorite == secondFavorite {
                return $0.key < $1.key
            }

            return firstFavorite && !secondFavorite
        }
    }

    private var filteredCatalog: [GestaltField] {
        guard !searchText.isEmpty else {
            return model.fields
        }

        return model.fields.filter {
            $0.key.localizedCaseInsensitiveContains(searchText) ||
            $0.description.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header

                    HStack(spacing: 10) {
                        actionButton("Refresh", symbol: "arrow.clockwise") {
                            model.inspect()
                            copiedMessage = ""
                        }

                        actionButton("Save backup", symbol: "archivebox") {
                            guard !model.results.isEmpty else {
                                copiedMessage = "Inspect the device before saving a snapshot."
                                return
                            }

                            model.saveSnapshot()
                            copiedMessage = "Inspection snapshot saved."
                        }

                        actionButton("Export JSON", symbol: "square.and.arrow.up") {
                            guard let data = model.exportData() else {
                                exportError = "Could not create the JSON export."
                                return
                            }

                            exportDocument = JSONExportDocument(data: data)
                            showingExporter = true
                        }
                    }

                    statusCard
                    deviceSummary
                    presetLibrary
                    fieldBrowser
                    returnedValues
                    backupCard
                    appGroupCard
                    worseQueryCard

                    Text("Read-only research interface. Presets are informational groupings; loading a snapshot only changes the data displayed in this app. No system MobileGestalt values or protected files are modified.")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.42))
                }
                .padding(18)
            }
            .background(background.ignoresSafeArea())
            .navigationBarTitle("Inspector", displayMode: .inline)
            .navigationBarItems(
                trailing: Button("Done") {
                    dismiss()
                }
                .foregroundColor(green)
            )
        }
        .preferredColorScheme(.dark)
        .onAppear {
            model.inspect()
        }
        .sheet(isPresented: $showingSnapshots) {
            snapshotSheet
        }
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .json,
            defaultFilename: "BullshitBox-MobileGestalt-Inspection",
            onCompletion: { result in
                if case .failure(let error) = result {
                    exportError = error.localizedDescription
                }
            }
        )
        .alert(
            "Export",
            isPresented: Binding(
                get: { !exportError.isEmpty },
                set: { if !$0 { exportError = "" } }
            )
        ) {
            Button("OK", role: .cancel) {
                exportError = ""
            }
        } message: {
            Text(exportError)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("MOBILEGESTALT")
                .font(.system(size: 11, weight: .heavy, design: .monospaced))
                .tracking(2)
                .foregroundStyle(green)

            Text("Research workspace")
                .font(.system(size: 25, weight: .black, design: .rounded))
                .foregroundStyle(.white)

            Text("Browse capability metadata, organize fields, and save local inspection snapshots.")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var deviceSummary: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("DEVICE / BUILD SUMMARY")
            summaryRow("Product", model.value(for: "ProductType"))
            summaryRow("iOS version", model.value(for: "ProductVersion"))
            summaryRow("Build", model.value(for: "BuildVersion"))
            summaryRow("Device class", model.value(for: "DeviceClass"))
        }
        .padding(14)
        .background(cardBackground)
    }

    private var presetLibrary: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("PRESET LIBRARY")

            ForEach(model.presets) { preset in
                Button {
                    selectedPreset = preset
                    searchText = ""
                } label: {
                    HStack(spacing: 11) {
                        Image(systemName: preset.symbol)
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(green)
                            .frame(width: 28)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(preset.name)
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(.white)

                            Text("\(preset.fields.count) research fields")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.white.opacity(0.48))
                        }

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(green)
                    }
                    .padding(12)
                    .background(
                        Color.white.opacity(0.055),
                        in: RoundedRectangle(cornerRadius: 11)
                    )
                }
                .buttonStyle(.plain)
            }

            if let preset = selectedPreset {
                VStack(alignment: .leading, spacing: 7) {
                    HStack {
                        Text(preset.name.uppercased())
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .foregroundStyle(green)

                        Spacer()

                        Button("Clear") {
                            selectedPreset = nil
                        }
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(green)
                    }

                    Text(preset.description)
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.72))

                    Text(preset.fields.joined(separator: "  ·  "))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.48))
                        .textSelection(.enabled)
                }
                .padding(12)
                .background(
                    Color.white.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 11)
                )
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    private var fieldBrowser: some View {
        VStack(alignment: .leading, spacing: 9) {
            sectionLabel("FIELD CATALOG · \(model.fields.count)")

            TextField("Search field names or descriptions", text: $searchText)
                .font(.system(size: 13))
                .padding(11)
                .background(
                    Color.white.opacity(0.07),
                    in: RoundedRectangle(cornerRadius: 10)
                )

            ForEach(filteredCatalog) { field in
                HStack(alignment: .top, spacing: 9) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(field.key)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(green)

                        Text(field.description)
                            .font(.system(size: 10))
                            .foregroundStyle(.white.opacity(0.53))
                    }

                    Spacer(minLength: 4)

                    Button {
                        model.toggleFavorite(field.key)
                    } label: {
                        Image(
                            systemName: model.favorites.contains(field.key)
                                ? "star.fill"
                                : "star"
                        )
                        .foregroundStyle(
                            model.favorites.contains(field.key)
                                ? green
                                : .white.opacity(0.35)
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(
                        model.favorites.contains(field.key)
                            ? "Remove favorite"
                            : "Add favorite"
                    )
                }
                .padding(.vertical, 7)

                if field.id != filteredCatalog.last?.id {
                    Divider()
                        .overlay(Color.white.opacity(0.08))
                }
            }

            if filteredCatalog.isEmpty {
                Text("No catalog fields match this search.")
                    .font(.system(size: 12))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    private var returnedValues: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                sectionLabel("RETURNED VALUES · \(filteredResults.count)")

                Spacer()

                Button {
                    model.copyAll()
                    copiedMessage = "All returned values copied."
                } label: {
                    Label("Copy all", systemImage: "doc.on.doc")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(green)
                }
                .disabled(model.results.isEmpty)
            }

            if !copiedMessage.isEmpty {
                Text(copiedMessage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(green)
            }

            if filteredResults.isEmpty {
                Text(
                    model.results.isEmpty
                        ? "No results yet. Tap Refresh."
                        : "No matching fields."
                )
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.5))
            } else {
                ForEach(filteredResults) { result in
                    HStack(alignment: .center, spacing: 10) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(result.key)
                                .font(.system(size: 11, weight: .bold, design: .monospaced))
                                .foregroundStyle(green)

                            Text(result.value)
                                .font(.system(size: 12))
                                .foregroundStyle(.white)
                                .textSelection(.enabled)
                        }

                        Spacer(minLength: 4)

                        Button {
                            model.copy(result)
                            copiedMessage = "\(result.key) copied."
                        } label: {
                            Image(systemName: "doc.on.doc")
                                .foregroundStyle(green)
                                .padding(8)
                                .background(
                                    Color.white.opacity(0.07),
                                    in: Circle()
                                )
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(11)
                    .background(
                        Color.white.opacity(0.055),
                        in: RoundedRectangle(cornerRadius: 10)
                    )
                }
            }
        }
        .padding(14)
        .background(cardBackground)
    }

    private var backupCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("LOCAL SNAPSHOTS · \(model.snapshots.count)")

            Text("Snapshots preserve inspection output inside BullshitBox. Loading one restores the displayed data only.")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.58))

            Button {
                showingSnapshots = true
            } label: {
                Label("Manage saved snapshots", systemImage: "archivebox")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(green)
            }
            .disabled(model.snapshots.isEmpty)
        }
        .padding(14)
        .background(cardBackground)
    }

    private var snapshotSheet: some View {
        NavigationView {
            List {
                if model.snapshots.isEmpty {
                    Text("No saved snapshots.")
                        .foregroundColor(.secondary)
                }

                ForEach(model.snapshots) { snapshot in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(snapshot.title)
                            .font(.headline)

                        Text("\(snapshot.device) · iOS \(snapshot.version) · \(snapshot.results.count) values")
                            .font(.caption)
                            .foregroundColor(.secondary)

                        HStack {
                            Button("Load snapshot") {
                                model.restoreSnapshot(snapshot)
                            }

                            Spacer()

                            Button("Delete", role: .destructive) {
                                model.deleteSnapshot(snapshot)
                            }
                        }
                        .font(.caption.weight(.semibold))
                    }
                    .padding(.vertical, 5)
                    .listRowBackground(Color(UIColor.secondarySystemBackground))
                }
            }
            .navigationTitle("Inspection Backups")
            .navigationBarItems(
                trailing: Button("Done") {
                    showingSnapshots = false
                }
            )
        }
        .preferredColorScheme(.dark)
    }

    private var appGroupCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("APP GROUP ENTITLEMENT")

            HStack(spacing: 8) {
                Image(
                    systemName: model.appGroupAvailable
                        ? "checkmark.circle.fill"
                        : "xmark.circle.fill"
                )
                .foregroundStyle(model.appGroupAvailable ? green : .orange)

                Text(
                    model.appGroupAvailable
                        ? "Container available"
                        : "Not configured"
                )
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
            }

            Text(model.appGroupDetail)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.65))

            Text("Expected identifier: group.com.bullshitbox.shared")
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.45))
        }
        .padding(14)
        .background(cardBackground)
    }

    private var worseQueryCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            sectionLabel("WORSE_QUERY STATUS")

            Text("Maintainer-reported compatibility: iOS 26.0 through latest. Runtime compatibility on this exact device/build has not been independently verified.")
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.7))

            Text("No matching App Group entitlement is configured in this build. The worse_query backend remains uninitialized.")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.orange)
        }
        .padding(14)
        .background(cardBackground)
    }

    private func actionButton(
        _ title: String,
        symbol: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .bold))

                Text(title)
                    .font(.system(size: 10, weight: .bold))
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(
                green,
                in: RoundedRectangle(cornerRadius: 11)
            )
        }
        .buttonStyle(.plain)
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionLabel(model.status.uppercased())

            Text(model.detail)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.65))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(Color.white.opacity(0.055))
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 10, weight: .heavy, design: .monospaced))
            .tracking(1.5)
            .foregroundStyle(green)
    }

    private func summaryRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.55))

            Spacer()

            Text(value)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(.white)
                .lineLimit(1)
                .textSelection(.enabled)
        }
    }
}
