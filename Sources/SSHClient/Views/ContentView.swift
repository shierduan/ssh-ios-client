import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HostsListView()
                .tabItem { Label("主机", systemImage: "server.rack") }

            KeyManagementView()
                .tabItem { Label("密钥", systemImage: "key") }

            SnippetsView()
                .tabItem { Label("片段", systemImage: "text.and.command") }

            SettingsView()
                .tabItem { Label("设置", systemImage: "gearshape") }
        }
    }
}
