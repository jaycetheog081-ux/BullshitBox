import SwiftUI
import Foundation
import CoreFoundation
import Darwin

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
                found.append(
                    GestaltResult(
                        key: key,
                        value: "Unavailable / not returned"
                    )
                )
                continue
            }

            let value = unmanagedValue.takeRetainedValue()

            found.append(
                GestaltResult(
                    key: key,
                    value: String(describing: value)
                )
            )
        }

        results = found

        let availableCount = found.filter {
            $0.value != "Unavailable / not returned"
        }.count

        status = "Inspection finished"
        detail = "Received values for \(availableCount) of \(keys.count) queried keys. No system files were changed."
    }
}

struct MobileGestaltInspectorView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var model = MobileGestaltInspectorModel()

    private let green = Color(red: 0.42, green: 1.0, blue: 0.35)
    private let background = Color(red: 0.035, green: 0.045, blue: 0.055)

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

                        Text("Queries a limited set of device and capability keys.")
                            .font(.system(size: 13))
                            .foregroundStyle(.white.opacity(0.6))
                    }

                    Button {
                        model.inspect()
                    } label: {
                        HStack {
                            Image(systemName: "arrow.clockwise")

                            Text("Refresh MobileGestalt")
                                .fontWeight(.bold)

                            Spacer()

                            Image(systemName: "chevron.right")
                        }
                        .foregroundStyle(.black)
                        .padding(15)
                        .background(
                            green,
                            in: RoundedRectangle(cornerRadius: 13)
                        )
                    }
                    .buttonStyle(.plain)

                    statusCard

                    VStack(alignment: .leading, spacing: 10) {
                        Text("RETURNED VALUES")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .tracking(1.8)
                            .foregroundStyle(.white.opacity(0.5))

                        if model.results.isEmpty {
                            Text("No results yet.")
                                .font(.system(size: 13))
                                .foregroundStyle(.white.opacity(0.5))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(15)
                                .background(
                                    Color.white.opacity(0.055),
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
                        } else {
                            ForEach(model.results) { result in
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(result.key)
                                        .font(.system(size: 12, weight: .bold, design: .monospaced))
                                        .foregroundStyle(green)

                                    Text(result.value)
                                        .font(.system(size: 13))
                                        .foregroundStyle(.white)
                                        .textSelection(.enabled)
                                }
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(13)
                                .background(
                                    Color.white.opacity(0.055),
                                    in: RoundedRectangle(cornerRadius: 12)
                                )
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 7) {
                        Text("WORSE_QUERY STATUS")
                            .font(.system(size: 10, weight: .heavy, design: .monospaced))
                            .tracking(1.8)
                            .foregroundStyle(green)

                        Text("Not integrated. Upstream lists iOS 26.0–26.7.2 and iOS 27.2. Your iOS 27.0 build is not listed as supported.")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        Color.white.opacity(0.055),
                        in: RoundedRectangle(cornerRadius: 12)
                    )

                    Text("This screen performs read-only queries. It does not edit MobileGestalt.plist or attempt a sandbox escape.")
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
            Text(model.status.uppercased())
                .font(.system(size: 10, weight: .heavy, design: .monospaced))
                .tracking(1.5)
                .foregroundStyle(green)

            Text(model.detail)
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            Color.white.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 12)
        )
    }
}
