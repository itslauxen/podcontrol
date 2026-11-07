import SwiftUI

@main
struct PodControlApp: App {
    @StateObject private var controlador = Controlador()

    var body: some Scene {
        Window("PodControl", id: "painel") {
            PainelView(controlador: controlador)
        }
        .windowResizability(.contentSize)

        MenuBarExtra("PodControl", systemImage: "airpods.gen3") {
            MenuDaBarra(config: controlador.config)
        }
    }
}

private struct MenuDaBarra: View {
    @ObservedObject var config: Configuracoes
    @Environment(\.openWindow) private var abrirJanela

    var body: some View {
        Toggle("Ativo", isOn: $config.ativo)
        Button("Abrir painel") {
            abrirJanela(id: "painel")
            NSApp.activate(ignoringOtherApps: true)
        }
        Divider()
        Button("Sair do PodControl") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
