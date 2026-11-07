import AppKit
import AudioToolbox
import CoreAudio
import CoreGraphics
import ApplicationServices
import MediaPlayer

/// Ações contínuas: cada passo de giro mexe um pouco.
enum AcaoGiro: String, CaseIterable, Codable, Identifiable {
    // As luzes guardam o nome antigo no rawValue para não perder o que já estava salvo.
    case nenhuma, volume, volumeAlexa, luz1 = "luzDaSala", luz2 = "luzDoEscritorio", brilho, rolagem, abas, faixas, crossfader, filtroOnda
    var id: String { rawValue }
    var nome: String {
        switch self {
        case .nenhuma: "Nada"
        case .volume: "Volume"
        case .volumeAlexa: "Volume da Alexa"
        case .luz1: Integracoes.nomeDaLuz(1)
        case .luz2: Integracoes.nomeDaLuz(2)
        case .brilho: "Brilho da tela"
        case .rolagem: "Rolar a página"
        case .abas: "Trocar de aba"
        case .faixas: "Passar de música"
        case .crossfader: "Crossfader do Onda"
        case .filtroOnda: "Filtro do Onda"
        }
    }
    var precisaAcessibilidade: Bool { [.rolagem, .abas, .faixas, .crossfader, .filtroOnda].contains(self) }
}

/// Ações de disparo único.
enum AcaoGatilho: String, CaseIterable, Codable, Identifiable {
    case nenhuma, abrirApp, playPause, proximaFaixa, faixaAnterior, mudo, missionControl
    var id: String { rawValue }
    var nome: String {
        switch self {
        case .nenhuma: "Nada"
        case .abrirApp: "Abrir um app"
        case .playPause: "Tocar / pausar"
        case .proximaFaixa: "Próxima faixa"
        case .faixaAnterior: "Faixa anterior"
        case .mudo: "Mudo liga/desliga"
        case .missionControl: "Mission Control"
        }
    }
    var precisaAcessibilidade: Bool { [.playPause, .proximaFaixa, .faixaAnterior].contains(self) }
}

enum Acessibilidade {
    static var liberada: Bool { AXIsProcessTrusted() }
    static func pedir() {
        let op = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(op)
    }
}

/// Executa as ações no Mac. Volume e brilho não pedem permissão nenhuma.
@MainActor
enum Executor {
    static let degrau: Float = 1.0 / 16 // mesmo degrau das teclas do Mac
    /// Cada degrau chega dividido em tantos passos finos, para o giro ficar suave.
    nonisolated static let finura = 4
    private static var passosDeAba = 0
    private static var passosDeFaixa = 0
    /// Pular de música pede um giro maior que o degrau normal, para não pular sem querer.
    private static let degrausPorFaixa = 2

    static func girar(_ acao: AcaoGiro, passos: Int) {
        let fino = degrau / Float(finura)
        switch acao {
        case .nenhuma: break
        case .volume:
            let v = Audio.mudarVolume(by: fino * Float(passos))
            HUD.mostrar(simbolo: v == 0 ? "speaker.slash.fill" : "speaker.wave.2.fill", texto: "Volume", nivel: v)
        case .volumeAlexa:
            guard Alexa.configurado else { return pedirConfiguracao("a Alexa") }
            Alexa.volume.mudar(by: fino * Float(passos))
        case .luz1, .luz2:
            guard let luz = HomeAssistant.luz(acao == .luz1 ? 1 : 2) else { return pedirConfiguracao("o Home Assistant") }
            luz.mudar(by: fino * Float(passos))
        case .brilho:
            if let b = Brilho.mudar(by: fino * Float(passos)) {
                HUD.mostrar(simbolo: "sun.max.fill", texto: "Brilho", nivel: b)
            }
        case .rolagem:
            // Horário rola para baixo.
            CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: Int32(-passos), wheel2: 0, wheel3: 0)?
                .post(tap: .cghidEventTap)
        case .abas:
            // Trocar de aba continua sendo um degrau inteiro.
            passosDeAba += passos
            let abas = passosDeAba / finura
            passosDeAba -= abas * finura
            for _ in 0..<abs(abas) { atalho(tecla: 0x30, flags: abas > 0 ? .maskControl : [.maskControl, .maskShift]) }
        case .faixas:
            // Horário vai para a próxima música, anti-horário volta.
            passosDeFaixa += passos
            let porFaixa = finura * degrausPorFaixa
            let faixas = passosDeFaixa / porFaixa
            passosDeFaixa -= faixas * porFaixa
            for _ in 0..<abs(faixas) { teclaDeMidia(faixas > 0 ? 17 : 18) }
            if faixas != 0 { HUD.mostrar(simbolo: faixas > 0 ? "forward.fill" : "backward.fill", texto: faixas > 0 ? "Próxima" : "Anterior") }
        case .crossfader:
            teclaNoOnda(passos > 0 ? 0x7C : 0x7B, vezes: abs(passos)) // setas
        case .filtroOnda:
            teclaNoOnda(passos > 0 ? 0x07 : 0x06, vezes: abs(passos)) // X e Z
        }
    }

    static func disparar(_ acao: AcaoGatilho, app: URL?) {
        switch acao {
        case .nenhuma: break
        case .abrirApp:
            guard let app else { HUD.mostrar(simbolo: "questionmark.app", texto: "Escolha o app no painel"); return }
            NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
            HUD.mostrar(simbolo: "arrow.up.forward.app", texto: app.deletingPathExtension().lastPathComponent)
        case .playPause: teclaDeMidia(16); HUD.mostrar(simbolo: "playpause.fill", texto: "Tocar / pausar")
        case .proximaFaixa: teclaDeMidia(17); HUD.mostrar(simbolo: "forward.fill", texto: "Próxima")
        case .faixaAnterior: teclaDeMidia(18); HUD.mostrar(simbolo: "backward.fill", texto: "Anterior")
        case .mudo:
            let mudo = Audio.alternarMudo()
            HUD.mostrar(simbolo: mudo ? "speaker.slash.fill" : "speaker.wave.2.fill", texto: mudo ? "Mudo" : "Som ligado")
        case .missionControl:
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Mission Control.app"))
        }
    }

    private static func pedirConfiguracao(_ quem: String) {
        HUD.mostrar(simbolo: "gearshape.fill", texto: "Configure \(quem) no painel")
    }

    /// A cabine do Onda tem atalhos de teclado. Em outro app, essas teclas fariam outra coisa.
    private static func teclaNoOnda(_ tecla: CGKeyCode, vezes: Int) {
        guard NSWorkspace.shared.frontmostApplication?.bundleIdentifier == "com.google.Chrome" else {
            HUD.mostrar(simbolo: "slider.horizontal.3", texto: "Abra a cabine no Chrome")
            return
        }
        for _ in 0..<vezes { atalho(tecla: tecla, flags: []) }
    }

    /// Simula as teclas de mídia do teclado (NX_KEYTYPE_*). Exige Acessibilidade.
    private static func teclaDeMidia(_ tecla: Int) {
        for desce in [true, false] {
            let estado = desce ? 0xA : 0xB
            let ev = NSEvent.otherEvent(with: .systemDefined, location: .zero,
                                        modifierFlags: NSEvent.ModifierFlags(rawValue: UInt(estado << 8)),
                                        timestamp: 0, windowNumber: 0, context: nil,
                                        subtype: 8, data1: (tecla << 16) | (estado << 8), data2: -1)
            ev?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    private static func atalho(tecla: CGKeyCode, flags: CGEventFlags) {
        for desce in [true, false] {
            let ev = CGEvent(keyboardEventSource: nil, virtualKey: tecla, keyDown: desce)
            ev?.flags = flags
            ev?.post(tap: .cghidEventTap)
        }
    }
}

/// Move e clica o cursor. Exige Acessibilidade.
enum Cursor {
    static func mover(dx: Int, dy: Int) {
        guard let atual = CGEvent(source: nil)?.location else { return }
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        var n: UInt32 = 0
        CGGetActiveDisplayList(8, &ids, &n)
        let tela = ids.prefix(Int(n)).reduce(CGRect.null) { $0.union(CGDisplayBounds($1)) }
        guard !tela.isNull else { return }
        let p = CGPoint(x: min(max(atual.x + CGFloat(dx), tela.minX), tela.maxX - 1),
                        y: min(max(atual.y + CGFloat(dy), tela.minY), tela.maxY - 1))
        CGEvent(mouseEventSource: nil, mouseType: .mouseMoved, mouseCursorPosition: p, mouseButton: .left)?
            .post(tap: .cghidEventTap)
    }

    static func clicar(_ botao: CGMouseButton) {
        guard let p = CGEvent(source: nil)?.location else { return }
        let tipos: [CGEventType] = botao == .left ? [.leftMouseDown, .leftMouseUp] : [.rightMouseDown, .rightMouseUp]
        for tipo in tipos {
            CGEvent(mouseEventSource: nil, mouseType: tipo, mouseCursorPosition: p, mouseButton: botao)?
                .post(tap: .cghidEventTap)
        }
    }
}

/// O aperto na haste chega como comando de mídia, e só para o app "tocando agora".
/// Por isso, com o mouse ligado, o fone deixa de controlar a música.
enum BotaoDoFone {
    private static var alvos: [(MPRemoteCommand, Any)] = []

    static func ligar(_ ligar: Bool, aoClicar: @escaping () -> Void, aoClicarDireito: @escaping () -> Void) {
        guard ligar != !alvos.isEmpty else { return }
        let centro = MPRemoteCommandCenter.shared()
        if ligar {
            let simples = [centro.playCommand, centro.pauseCommand, centro.togglePlayPauseCommand]
            alvos = simples.map { c in (c, c.addTarget { _ in
                NSLog("[PodControl] botao do fone: clique")
                aoClicar()
                return .success
            }) }
            let c = centro.nextTrackCommand // dois apertos
            alvos.append((c, c.addTarget { _ in
                NSLog("[PodControl] botao do fone: clique direito")
                aoClicarDireito()
                return .success
            }))
            MPNowPlayingInfoCenter.default().nowPlayingInfo = [MPMediaItemPropertyTitle: "PodControl"]
            MPNowPlayingInfoCenter.default().playbackState = .playing
            NSLog("[PodControl] botao do fone: ligado")
        } else {
            for (c, alvo) in alvos { c.removeTarget(alvo) }
            alvos = []
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            MPNowPlayingInfoCenter.default().playbackState = .stopped
        }
    }
}

/// Volume da saída de som atual (pode ser o próprio AirPods) via CoreAudio.
enum Audio {
    private static func saidaPadrao() -> AudioObjectID? {
        var dev = AudioObjectID(0)
        var tam = UInt32(MemoryLayout<AudioObjectID>.size)
        var end = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                             mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        let r = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &end, 0, nil, &tam, &dev)
        return r == noErr && dev != 0 ? dev : nil
    }

    private static var enderecoSaidaPadrao = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)

    /// Alto-falante embutido do Mac (o aparelho de saída com transporte "built-in").
    private static func saidaInterna() -> AudioObjectID? {
        var end = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDevices,
                                             mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var tam: UInt32 = 0
        let sistema = AudioObjectID(kAudioObjectSystemObject)
        guard AudioObjectGetPropertyDataSize(sistema, &end, 0, nil, &tam) == noErr else { return nil }
        var aparelhos = [AudioObjectID](repeating: 0, count: Int(tam) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(sistema, &end, 0, nil, &tam, &aparelhos) == noErr else { return nil }
        return aparelhos.first { dev in
            var transporte: UInt32 = 0
            var t = UInt32(MemoryLayout<UInt32>.size)
            var endT = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyTransportType,
                                                  mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            var endS = endereco(kAudioDevicePropertyStreams)
            var tamS: UInt32 = 0
            return AudioObjectGetPropertyData(dev, &endT, 0, nil, &t, &transporte) == noErr
                && transporte == kAudioDeviceTransportTypeBuiltIn
                && AudioObjectGetPropertyDataSize(dev, &endS, 0, nil, &tamS) == noErr && tamS > 0
        }
    }

    /// Nome da saída de som atual ("AirPods do Gabriel", "Echo Dot"…).
    static func nomeDaSaidaPadrao() -> String {
        guard let dev = saidaPadrao() else { return "" }
        var end = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                             mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var nome: Unmanaged<CFString>?
        var tam = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(dev, &end, 0, nil, &tam, &nome) == noErr, let n = nome else { return "" }
        return n.takeRetainedValue() as String
    }

    /// True se o som está indo para o fone que serve de controle (e não para outra saída, como uma Alexa por Bluetooth).
    static func saidaPadraoEhFone(_ fone: String) -> Bool {
        let nome = nomeDaSaidaPadrao()
        if nome.isEmpty { return false }
        if !fone.isEmpty && (nome == fone || nome.contains(fone) || fone.contains(nome)) { return true }
        return nome.localizedCaseInsensitiveContains("AirPods")
    }

    /// Passa o som para o alto-falante do Mac, se ainda não estiver nele.
    static func usarSaidaInterna() {
        guard var interna = saidaInterna(), saidaPadrao() != interna else { return }
        AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &enderecoSaidaPadrao, 0, nil,
                                   UInt32(MemoryLayout<AudioObjectID>.size), &interna)
    }

    /// Avisa (na fila principal) sempre que a saída de som do Mac muda.
    static func aoMudarSaida(_ bloco: @escaping () -> Void) {
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &enderecoSaidaPadrao, .main) { _, _ in bloco() }
    }

    private static func endereco(_ seletor: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: seletor, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }

    /// Devolve o novo volume (0...1).
    @discardableResult
    static func mudarVolume(by delta: Float) -> Float {
        guard let dev = saidaPadrao() else { return 0 }
        var end = endereco(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var vol: Float32 = 0
        var tam = UInt32(MemoryLayout<Float32>.size)
        AudioObjectGetPropertyData(dev, &end, 0, nil, &tam, &vol)
        vol = min(max(vol + delta, 0), 1)
        AudioObjectSetPropertyData(dev, &end, 0, nil, tam, &vol)
        if delta > 0 && estaMudo(dev) { definirMudo(dev, false) }
        return vol
    }

    /// Devolve true se ficou mudo.
    static func alternarMudo() -> Bool {
        guard let dev = saidaPadrao() else { return false }
        let novo = !estaMudo(dev)
        definirMudo(dev, novo)
        return novo
    }

    private static func estaMudo(_ dev: AudioObjectID) -> Bool {
        var end = endereco(kAudioDevicePropertyMute)
        var v: UInt32 = 0
        var tam = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(dev, &end, 0, nil, &tam, &v) == noErr && v != 0
    }

    private static func definirMudo(_ dev: AudioObjectID, _ mudo: Bool) {
        var end = endereco(kAudioDevicePropertyMute)
        var v: UInt32 = mudo ? 1 : 0
        AudioObjectSetPropertyData(dev, &end, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
    }
}

/// Brilho da tela interna pelo DisplayServices (framework privado da Apple, sem API pública).
enum Brilho {
    private typealias Ler = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias Gravar = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private static let funcoes: (Ler, Gravar)? = {
        guard let h = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW),
              let l = dlsym(h, "DisplayServicesGetBrightness"),
              let g = dlsym(h, "DisplayServicesSetBrightness") else { return nil }
        return (unsafeBitCast(l, to: Ler.self), unsafeBitCast(g, to: Gravar.self))
    }()

    private static var telaInterna: CGDirectDisplayID {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var n: UInt32 = 0
        CGGetOnlineDisplayList(16, &ids, &n)
        return ids.prefix(Int(n)).first { CGDisplayIsBuiltin($0) != 0 } ?? CGMainDisplayID()
    }

    /// Devolve o novo brilho (0...1), ou nil se não deu para controlar.
    static func mudar(by delta: Float) -> Float? {
        guard let (ler, gravar) = funcoes else { return nil }
        let tela = telaInterna
        var b: Float = 0
        guard ler(tela, &b) == 0 else { return nil }
        b = min(max(b + delta, 0), 1)
        return gravar(tela, b) == 0 ? b : nil
    }
}
