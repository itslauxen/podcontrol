import AppKit
import SwiftUI

/// Aviso flutuante no rodapé da tela, como o do volume do macOS.
@MainActor
enum HUD {
    private static var painel: NSPanel?
    private static var esconder: DispatchWorkItem?

    static func mostrar(simbolo: String, texto: String, nivel: Float? = nil) {
        let p = painel ?? criar()
        painel = p
        let host = NSHostingView(rootView: HUDView(simbolo: simbolo, texto: texto, nivel: nivel))
        host.frame = NSRect(x: 0, y: 0, width: 240, height: 64)
        p.contentView = host
        if let tela = NSScreen.main?.visibleFrame {
            p.setFrameOrigin(NSPoint(x: tela.midX - 120, y: tela.minY + 90))
        }
        p.alphaValue = 1
        p.orderFrontRegardless()

        esconder?.cancel()
        let tarefa = DispatchWorkItem {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; p.animator().alphaValue = 0 }) { p.orderOut(nil) }
        }
        esconder = tarefa
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: tarefa)
    }

    private static func criar() -> NSPanel {
        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 240, height: 64),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: true)
        p.level = .statusBar
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.ignoresMouseEvents = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        return p
    }
}

private struct HUDView: View {
    let simbolo: String
    let texto: String
    let nivel: Float?

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: simbolo)
                .font(.system(size: 20, weight: .medium))
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 6) {
                Text(texto).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                if let nivel {
                    ProgressView(value: Double(nivel)).progressViewStyle(.linear)
                }
            }
        }
        .padding(.horizontal, 16)
        .frame(width: 240, height: 64)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
