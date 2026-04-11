import SwiftUI

enum SidebarItem: String, CaseIterable, Identifiable {
    case home = "Home"
    case dictionary = "Dictionary"
    case snippets = "Snippets"
    case style = "Style"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: "house"
        case .dictionary: "book.closed"
        case .snippets: "text.badge.plus"
        case .style: "paintbrush"
        case .settings: "gearshape"
        }
    }

    var isBottom: Bool { self == .settings }
}

struct MainWindowView: View {
    @ObservedObject var appState: AppState
    @State private var selectedItem: SidebarItem? = .home

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                List(SidebarItem.allCases.filter { !$0.isBottom }, selection: $selectedItem) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .tag(item)
                }
                .listStyle(.sidebar)

                Spacer(minLength: 0)

                Divider()

                // Settings at the bottom of sidebar
                List(selection: $selectedItem) {
                    Label("Settings", systemImage: "gearshape")
                        .tag(SidebarItem.settings)
                }
                .listStyle(.sidebar)
                .frame(height: 40)
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
            case .settings:
                SettingsDetailView(appState: appState)
            case nil:
                ContentUnavailableView(
                    "Select a Section",
                    systemImage: "sidebar.left",
                    description: Text("Choose an item from the sidebar.")
                )
            }
        }
        .frame(minWidth: 700, minHeight: 500)
    }
}
