import Combine
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
}

struct MainWindowView: View {
    @ObservedObject var appState: AppState
    @State private var selectedItem: SidebarItem? = .home

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItem) {
                Section {
                    ForEach(SidebarItem.allCases.filter { $0 != .settings }) { item in
                        Label(item.rawValue, systemImage: item.icon)
                            .tag(item)
                    }
                }

                Section {
                    Label("Settings", systemImage: "gearshape")
                        .tag(SidebarItem.settings)
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 160, max: 170)
        } detail: {
            Group {
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
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 660, minHeight: 500)
    }
}
