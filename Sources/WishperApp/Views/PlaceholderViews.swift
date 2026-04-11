import SwiftUI

struct DictionaryView: View {
    var body: some View {
        ContentUnavailableView(
            "Dictionary",
            systemImage: "book.closed",
            description: Text("Coming soon")
        )
    }
}

struct SnippetsView: View {
    var body: some View {
        ContentUnavailableView(
            "Snippets",
            systemImage: "text.badge.plus",
            description: Text("Coming soon")
        )
    }
}

struct StyleView: View {
    var body: some View {
        ContentUnavailableView(
            "Style",
            systemImage: "paintbrush",
            description: Text("Coming soon")
        )
    }
}
