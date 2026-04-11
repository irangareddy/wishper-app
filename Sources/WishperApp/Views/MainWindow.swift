import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case home = "Home"
    case dictionary = "Dictionary"
    case snippets = "Snippets"
    case style = "Style"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home:
            "house"
        case .dictionary:
            "book.closed"
        case .snippets:
            "text.badge.plus"
        case .style:
            "paintbrush"
        }
    }
}

struct MainWindowView: View {
    @ObservedObject var appState: AppState
    @State private var selectedItem: SidebarItem? = .home

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(SidebarItem.allCases, selection: $selectedItem) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .tag(item)
                }
                .listStyle(.sidebar)

                Spacer(minLength: 0)

                SettingsLink {
                    Label("Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .padding(8)
            }
            .navigationSplitViewColumnWidth(min: 180, ideal: 200, max: 240)
        } detail: {
            switch selectedItem {
            case .home:
                HomeView(appState: appState)
            case .dictionary:
                DictionaryView()
            case .snippets:
                SnippetsView()
            case .style:
                StyleView()
            case nil:
                ContentUnavailableView(
                    "Select a Section",
                    systemImage: "sidebar.left",
                    description: Text("Choose an item from the sidebar to continue.")
                )
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}
