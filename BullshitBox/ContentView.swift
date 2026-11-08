import SwiftUI

struct ContentView: View {
    private let green = Color(red: 0.42, green: 1.0, blue: 0.35)

    private let modules: [ModuleItem] = [
        .init(title: "MobileGestalt", subtitle: "Inspect capability values", symbol: "slider.horizontal.3", status: "RESEARCH"),
        .init(title: "PosterBoard", subtitle: "Explore appearance resources", symbol: "rectangle.3.group", status: "PLANNED"),
        .init(title: "Card Themer", subtitle: "Theme experiments", symbol: "square.grid.2x2", status: "PLANNED"),
        .init(title: "Passcode Themes", subtitle: "Lock screen concept tests", symbol: "lock", status: "PLANNED")
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("BullshitBox")
                        .font(.system(size: 34, weight: .black, design: .rounded))

                    Text("MOBILEGESTALT EDIT SLOP")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(2.2)
                        .foregroundStyle(green)
                }
                .padding(.top, 12)

                Button {} label: {
                    HStack(spacing: 12) {
                        Image(systemName: "sparkles")

                        Text("Button that does fucking nothing (Siri AI)")
                            .font(.system(size: 14, weight: .bold))

                        Spacer(minLength: 0)

                        Image(systemName: "arrow.up.right")
                    }
                    .foregroundStyle(.black)
                    .padding(17)
                    .frame(maxWidth: .infinity)
                    .background(green, in: RoundedRectangle(cornerRadius: 16))
                }
                .buttonStyle(.plain)

                HStack {
                    Text("TOOLBOX")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .tracking(2)
                        .foregroundStyle(.white.opacity(0.55))

                    Spacer()

                    Text("A13 AND NEWER")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(green)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ],
                    spacing: 12
                ) {
                    ForEach(modules) { item in
                        ModuleCard(item: item, accent: green)
                    }
                }

                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "info.circle.fill")
                        .foregroundStyle(green)

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Research scaffold ready")
                            .font(.system(size: 13, weight: .bold))

                        Text("No exploit backend is integrated. System changes are not applied.")
                            .font(.system(size: 12))
                            .foregroundStyle(.white.opacity(0.58))
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Color.white.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 14)
                )
            }
            .padding(18)
        }
        .background(
            Color(red: 0.035, green: 0.045, blue: 0.055)
                .ignoresSafeArea()
        )
    }
}

private struct ModuleItem: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let symbol: String
    let status: String
}

private struct ModuleCard: View {
    let item: ModuleItem
    let accent: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: item.symbol)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(accent)

                Spacer()

                Text(item.status)
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .foregroundStyle(accent)
            }

            Text(item.title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.white)

            Text(item.subtitle)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 118, alignment: .leading)
        .background(
            Color.white.opacity(0.055),
            in: RoundedRectangle(cornerRadius: 15)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 15)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}
