import AppKit
import Combine
import Gestos

/// Liga o sensor às ações escolhidas na configuração.
final class Controlador: ObservableObject {
    let config = Configuracoes()
    let sensor = Sensor()
    @Published private(set) var ultimoGesto = "—"
    /// Segundos que faltam na calibração do mouse; nil fora dela.
    @Published private(set) var calibrandoMouse: Int?
    private let mouse = MouseDeMovimento()
    private var calibrador: CalibradorDoMouse?
    private var assinaturas: Set<AnyCancellable> = []

    init() {
        aplicarAjustes()
        // Qualquer mudança na configuração vai para o detector.
        config.objectWillChange
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.aplicarAjustes() }
            .store(in: &assinaturas)

        // O sensor entrega na fila principal.
        sensor.aoReconhecer = { [weak self] evento, mao in MainActor.assumeIsolated { self?.tratar(evento, mao: mao) } }
        sensor.aoReceber = { [weak self] amostra in MainActor.assumeIsolated { self?.moverMouse(amostra) } }
        sensor.iniciar(com: config.fonte)
        // Só funciona com o app aberto: o aviso de troca de saída morre junto com ele.
        Audio.aoMudarSaida { [weak self] in self?.manterSom() }
    }

    private func manterSom() {
        // Só tira o som do fone que serve de controle. Outra saída escolhida pelo usuário
        // (uma Alexa por Bluetooth, um monitor) fica como está.
        guard config.manterSomNoMac && config.fonte == .airpods else { return }
        if Audio.saidaPadraoEhFone(sensor.qualFone) {
            NSLog("[PodControl] som foi para %@; voltando para o alto-falante do Mac", Audio.nomeDaSaidaPadrao())
            Audio.usarSaidaInterna()
        }
    }

    private func aplicarAjustes() {
        for d in [sensor.detector, sensor.detectorDireito] {
            // O detector trabalha em passos finos; o Executor junta de volta onde precisa de degrau inteiro.
            d.ajustes.grausPorPasso = config.modoControladora ? Controladora.grausPorPasso : config.grausPorPasso / Double(Executor.finura)
            // Na mixagem o giro lento conta: uma virada longa é devagar.
            d.ajustes.zonaMorta = config.modoControladora ? 0.15 : AjustesDoDetector().zonaMorta
            d.ajustes.limiarChacoalhada = config.forcaChacoalhada
            d.ajustes.inverterSentido = config.inverterSentido
        }
        sensor.detector.ladoA = config.ladoA
        sensor.detector.ladoB = config.ladoB
        // Sem gravação própria, o direito tenta com a do outro fone.
        sensor.detectorDireito.ladoA = config.ladoADireito ?? config.ladoA
        sensor.detectorDireito.ladoB = config.ladoBDireito ?? config.ladoB
        sensor.doisFones = config.modoControladora && config.doisFones && config.fonte == .airpods
        sensor.usar(config.fonte)
        manterSom()
        if config.modoControladora { MainActor.assumeIsolated { Controladora.ligar() } }
        mouse.haste = config.hasteMouse
        mouse.ajustes.velocidade = 900 * config.velocidadeMouse
        BotaoDoFone.ligar(mouseLigado, aoClicar: { Cursor.clicar(.left) }, aoClicarDireito: { Cursor.clicar(.right) })
    }

    /// Com o mouse ligado, o fone só serve de mouse: giro e chacoalhada não disparam ações.
    private var mouseLigado: Bool { config.modoMouse && config.fonte == .airpods }

    @MainActor
    private func moverMouse(_ amostra: Amostra) {
        calibrador?.adicionar(amostra)
        guard mouseLigado, calibrador == nil else { return }
        let d = mouse.processar(amostra)
        if d.dx != 0 || d.dy != 0 { Cursor.mover(dx: d.dx, dy: d.dy) }
    }

    /// Três segundos de gangorra com a ponta da haste. Devolve o resultado em `aoTerminar`.
    @MainActor
    func calibrarMouse(aoTerminar: @escaping (Bool) -> Void) {
        guard calibrador == nil else { return }
        calibrador = CalibradorDoMouse()
        calibrandoMouse = 3
        Task {
            for falta in [2, 1, 0] {
                try? await Task.sleep(for: .seconds(1))
                calibrandoMouse = falta > 0 ? falta : nil
            }
            let haste = calibrador?.concluir()
            calibrador = nil
            if let haste { config.hasteMouse = haste }
            aoTerminar(haste != nil)
        }
    }

    @MainActor
    private func tratar(_ evento: Evento, mao: Mao) {
        if mouseLigado { return }
        switch evento {
        case .giro(let lado, let passos):
            guard config.ativo else { return }
            if config.modoControladora {
                // Lado A mexe no controle aceso; Lado B anda pela roda.
                if lado == .a { Controladora.girar(passos, mao: mao) } else { Controladora.andarNaRoda(passos, mao: mao) }
                let deck = mao == .unica ? "" : mao == .esquerda ? " do Deck 1" : " do Deck 2"
                ultimoGesto = (lado == .a ? "Girou o controle" : "Girou a roda") + deck
                return
            }
            let acao = config.acaoDeGiro(lado)
            Executor.girar(acao, passos: passos)
            ultimoGesto = "Girou \(passos > 0 ? "horário" : "anti-horário") no \(lado.nome) → \(acao.nome)"
        case .chacoalhada:
            guard config.ativo else { return }
            if config.modoControladora { return }
            Executor.disparar(config.chacoalhar, app: config.app)
            ultimoGesto = "Chacoalhou → \(config.chacoalhar.nome)"
        case .mudouLado(let lado):
            guard config.ativo, config.modoControladora, let lado else { return }
            Controladora.abrirRoda(lado == .b, mao: mao)
        }
    }

    /// Grava a posição atual como lado A ou B, em cada fone que estiver mandando. Devolve false se não há leitura.
    func gravar(_ lado: Lado) -> Bool {
        let g = sensor.posicaoAtual(), direito = sensor.posicaoAtual(direito: true)
        if let g { if lado == .a { config.ladoA = g } else { config.ladoB = g } }
        if let direito { if lado == .a { config.ladoADireito = direito } else { config.ladoBDireito = direito } }
        return g != nil || direito != nil
    }
}
