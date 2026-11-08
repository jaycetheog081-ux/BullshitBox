import SwiftUI
import Foundation
import CoreFoundation
import Darwin
import UIKit

private typealias MGCopyAnswerFunction = @convention(c) (CFString) -> Unmanaged<CFTypeRef>?

private struct GestaltResult: Identifiable {
    let key: String
    let value: String
    var id: String { key }
}

@MainActor
private final class MobileGestaltInspectorModel: ObservableObject {
    @Published private(set) var results: [GestaltResult] = []
    @Published private(set) var status = "Not inspected"
    @Published private(set) var detail = "Tap Refresh to query the read-only MobileGestalt interface."
    @Published private(set) var appGroupAvailable = false
    @Published private(set) var appGroupDetail = "Checking App Group access…"

    private let appGroupIdentifier = "group.com.bullshitbox.shared"
    private var libraryHandle: UnsafeMutableRawPointer?

    private let keys = [
        "ProductType",
        "ProductVersion",
        "BuildVersion",
        "DeviceClass",
        "MarketingName",
        "HasBaseband",
        "HasNFC",
        "HasAppleNeuralEngine",
        "IsSimulator"
    ]

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

        for key in keys {
            guard let unmanagedValue = copyAnswer(key as CFString) else {
                found.append(GestaltResult(key: key, value: "Unavailable / not returned"))
                continue
            }

            let value = unmanagedValue.takeRetainedValue()
            found.append(GestaltResult(key: key, value: String(describing: value)))
        }

        results = found

        let availableCount = found.filter {
            $0.value != "Unavailable / not returned"
        }.count

        status = "Inspection finished"
        detail = "Received values for \(availableCount) of \(keys.count) queried keys. No system files were changed."
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

    func copy(_ result: GestaltResult) {
        UIPasteboard.general.string = result.value
    }

    func copyAll() {
        let text = results.map { "\($0.key): \($0.value)" }.joined(separator: "\n")
        UIPasteboard.general.string = text
    }

    func value(for key: String) -> String {
        results.first(where: { $0.key == key })?.value ?? "Not returned"
    }
}

struct MobileGestaltInspectorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = MobileGestaltInspectorModel()
    @State private var searchText = ""
    @State private var copiedMessage = ""

    private let green = Color(red: 0.42, green: 1.0, blue: 0.35)
    private let background = Color(red: 0.035, green: 0.045, blue: 0.055)

    private var filteredResults: [GestaltResult] {
        guard !searchText.isEmpty else { return model.results }
        return model.results.filter {
            $0.key.localizedCaseInsensitiveContains(searchText) ||
            $0.value.localizedCaseInsensitiveContains(searchText)
        }
    }

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("MOBILEGESTALT")
                            .font(.system(size: 11, weight: .heavy, design: .monospaced))
                            .tracking(2)
                            .foregroundStyle(green)

                        Text("Read-only inspector")
                            .font(.system(size: 25, weight: .black, design: .rounded))
                            .foregroundStyle(.white)

                        Text("Inspect device capability values and check the current App Group signing setup.")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    Button {
                        model.inspect()
                        copiedMessage = ""
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")
                            Text("Refresh MobileGestalt").fontWeight(.bold)
                            Spacer()
                            Image(systemName: "chevron.right")
                        }
                        .foregroundStyle(.black)
                        .padding(15)
                        .background(green, in: RoundedRectangle(cornerRadius: 13))
                    }
                    .buttonStyle(.plain)

                    statusCard

                    VStack(alignment: .leading, spacing: 8) {
                        sectionLabel("DEVICE / BUILD SUMMARY")
                        summaryRow("Product", model.value(for: "ProductType"))
                        summaryRow("iOS version", model.value(for: "ProductVersion"))
                        summaryRow("Build", model.value(for: "BuildVersion"))
                        summaryRow("Device class", model.value(for: "DeviceClass"))
                    }
                    .padding(14)
                    .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))

                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            sectionLabel("RETURNED VALUES")
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

                        TextField("Search keys or values", text: $searchText)
                            .font(.system(size: 13))
                            .padding(11)
                            .background(Color.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 10))

                        if !copiedMessage.isEmpty {
                            Text(copiedMessage)
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(green)
                        }

                        if filteredResults.isEmpty {
                            Text(model.results.isEmpty ? "No results yet." : "No matching fields.")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.5))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(15)
                                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                        } else {
                            ForEach(filteredResults) { result in
                                HStack(alignment: .center, spacing: 12) {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(result.key)
                                            .font(.system(size: 12, weight: .bold, design: .monospaced))
                                            .foregroundStyle(green)

                                        Text(result.value)
                                            .font(.system(size: 13))
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
                                            .background(Color.white.opacity(0.07), in: Circle())
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel("Copy \(result.key)")
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(13)
                                .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }

                    appGroupCard

                    VStack(alignment: .leading, spacing: 7) {
                        sectionLabel("WORSE_QUERY STATUS")

                        Text("Maintainer-reported compatibility: iOS 26.0 through latest. Runtime compatibility on this exact device/build has not yet been independently verified.")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.7))

                        Text("The App Group requirement is not satisfied in this build, so the worse_query backend is not initialized.")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))

                    Text("This screen performs read-only MobileGestalt queries and a non-mutating App Group container check. It does not edit MobileGestalt, access protected system paths, or claim root/kernel access.")
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
    }

    private var statusCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            sectionLabel(model.status.uppercased())

            Text(model.detail)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
    }

    private var appGroupCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("APP GROUP ENTITLEMENT")

            HStack(spacing: 8) {
                Image(systemName: model.appGroupAvailable ? "checkmark.circle.fill" : "xmark.circle.fill")
                    .foregroundStyle(model.appGroupAvailable ? green : .orange)

                Text(model.appGroupAvailable ? "Container available" : "Not configured")
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
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
