import CoreMotion
import Foundation
import simd
import Gestos

/// De onde vem o movimento.
enum Fonte: String, CaseIterable, Codable, Identifiable {
    case objeto, airpods
    var id: String { rawValue }
    var nome: String { self == .objeto ? "Objeto de mesa" : "AirPods" }
}

/// Lê o movimento (do objeto ESP32 ou dos AirPods) e entrega gestos já reconhecidos.
final class Sensor: NSObject, ObservableObject, CMHeadphoneMotionManagerDelegate {
    let detector = DetectorDeGestos()
    /// Com um fone em cada deck, o direito tem detector próprio: cada fone gira e vira por conta dele.
    let detectorDireito = DetectorDeGestos()
    var doisFones = false
    var aoReconhecer: ((Evento, Mao) -> Void)?
    /// Cada leitura crua, antes de virar gesto (o mouse usa).
    var aoReceber: ((Amostra) -> Void)?

    // Estado para a tela (atualizado no máximo 10x por segundo).
    @Published private(set) var conectado = false
    @Published private(set) var recebendo = false
    @Published private(set) var autorizacao = CMHeadphoneMotionManager.authorizationStatus()
    @Published private(set) var lado: Lado?
    @Published private(set) var giro: Double = 0
    @Published private(set) var agitacao: Double = 0
    @Published private(set) var qualFone = ""
    /// Quais fones mandaram movimento agora há pouco ("fone direito", "fone direito e fone esquerdo").
    @Published private(set) var fonesAtivos = ""
    @Published private(set) var fonte: Fonte = .objeto
    /// Situação do Bluetooth do objeto, para a tela.
    @Published private(set) var mensagemObjeto = ""

    private let gerente = CMHeadphoneMotionManager()
    private let objeto = FonteObjeto()
    private let fusao = FusaoIMU()
    private var iniciado = false
    private var ultimaAmostra = Date.distantPast
    private var ultimaPublicacao = Date.distantPast
    /// O que o fone direito (true) e o resto (false) mandaram por último. Não pode misturar: os sensores estão em posições diferentes.
    private var gravidadesRecentes: [Bool: [SIMD3<Double>]] = [:]
    private var ultimaDoLado: [Bool: Date] = [:]
    private var ultimaDoFone: [String: Date] = [:]
    private var relogio: Timer?
    /// Com `--diagnostico <arquivo>`, grava cada leitura em CSV para análise.
    private lazy var diagnostico: FileHandle? = {
        let args = CommandLine.arguments
        guard let i = args.firstIndex(of: "--diagnostico"), i + 1 < args.count else { return nil }
        FileManager.default.createFile(atPath: args[i + 1], contents: Data("t,fonte,gx,gy,gz,rx,ry,rz,ax,ay,az,lado,evento\n".utf8))
        return FileHandle(forWritingAtPath: args[i + 1]).map { $0.seekToEndOfFile(); return $0 }
    }()

    var disponivel: Bool { gerente.isDeviceMotionAvailable }

    func iniciar(com fonte: Fonte) {
        gerente.delegate = self
        objeto.aoLer = { [weak self] acel, giro, tempo in
            guard let self, self.fonte == .objeto else { return }
            self.receber(self.fusao.processar(acel: acel, giro: giro, tempo: tempo), nome: "objeto")
        }
        objeto.aoMudarEstado = { [weak self] conectado, mensagem in
            guard let self, self.fonte == .objeto else { return }
            self.conectado = conectado
            self.mensagemObjeto = mensagem
            if !conectado { self.recebendo = false; self.lado = nil }
        }
        relogio = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            guard let self else { return }
            let r = Date().timeIntervalSince(self.ultimaAmostra) < 1.5
            if r != self.recebendo { self.recebendo = r }
            let a = CMHeadphoneMotionManager.authorizationStatus()
            if a != self.autorizacao { self.autorizacao = a }
            let fones = self.ultimaDoFone.filter { Date().timeIntervalSince($0.value) < 1.5 }.keys.sorted().joined(separator: " e ")
            if fones != self.fonesAtivos {
                self.fonesAtivos = fones
                NSLog("[PodControl] movimento vindo de: %@", fones)
            }
        }
        iniciado = true
        usar(fonte, forcar: true)
    }

    /// Troca a fonte de movimento, desligando a outra.
    func usar(_ nova: Fonte, forcar: Bool = false) {
        guard iniciado, forcar || nova != fonte else { return }
        fonte = nova
        conectado = false
        recebendo = false
        lado = nil
        qualFone = ""
        gravidadesRecentes.removeAll()
        ultimaDoLado.removeAll()
        ultimaDoFone.removeAll()
        switch nova {
        case .objeto:
            gerente.stopDeviceMotionUpdates()
            objeto.iniciar()
        case .airpods:
            objeto.parar()
            reiniciarLeitura()
        }
    }

    private func reiniciarLeitura() {
        gerente.stopDeviceMotionUpdates()
        gerente.startDeviceMotionUpdates(to: .main) { [weak self] movimento, erro in
            guard let self, self.fonte == .airpods, let m = movimento, erro == nil else { return }
            self.processar(m)
        }
    }

    private func processar(_ m: CMDeviceMotion) {
        let amostra = Amostra(gravidade: SIMD3(m.gravity.x, m.gravity.y, m.gravity.z),
                              rotacao: SIMD3(m.rotationRate.x, m.rotationRate.y, m.rotationRate.z),
                              aceleracao: SIMD3(m.userAcceleration.x, m.userAcceleration.y, m.userAcceleration.z),
                              tempo: m.timestamp)
        let (nome, fone): (String, Mao) = switch m.sensorLocation {
            case .headphoneLeft: ("fone esquerdo", .esquerda)
            case .headphoneRight: ("fone direito", .direita)
            default: ("", .unica)
        }
        receber(amostra, nome: nome, fone: fone)
    }

    /// Caminho comum das duas fontes: detector, diagnóstico e tela.
    private func receber(_ amostra: Amostra, nome: String, fone: Mao = .unica) {
        ultimaAmostra = Date()
        let mao = doisFones ? fone : .unica
        let direito = mao == .direita
        let atual = direito ? detectorDireito : detector
        ultimaDoLado[direito] = ultimaAmostra
        if !nome.isEmpty { ultimaDoFone[nome] = ultimaAmostra }
        gravidadesRecentes[direito, default: []].append(amostra.gravidade)
        if gravidadesRecentes[direito, default: []].count > 15 { gravidadesRecentes[direito]?.removeFirst() }

        aoReceber?(amostra)
        let eventos = atual.processar(amostra)
        for evento in eventos { aoReconhecer?(evento, mao) }
        if let d = diagnostico {
            let g = amostra.gravidade, r = amostra.rotacao, a = amostra.aceleracao
            let v = [amostra.tempo, g.x, g.y, g.z, r.x, r.y, r.z, a.x, a.y, a.z]
            let numeros = v.map { String(format: "%.4f", $0) }
            let linha = ([numeros[0], fonte.rawValue] + numeros.dropFirst()).joined(separator: ",")
                + ",\(atual.ladoAtual?.rawValue ?? "-"),\(eventos.map { "\($0)" }.joined(separator: " "))\n"
            d.write(Data(linha.utf8))
        }

        if Date().timeIntervalSince(ultimaPublicacao) > 0.1 {
            ultimaPublicacao = Date()
            if !recebendo { recebendo = true }
            lado = atual.ladoAtual
            giro = atual.giroAtual
            agitacao = atual.agitacao
            if nome != qualFone { qualFone = nome }
        }
    }

    /// Média da gravidade dos últimos instantes, com o objeto parado. Nil se esse fone não mandou nada agora.
    func posicaoAtual(direito: Bool = false) -> SIMD3<Double>? {
        let recentes = gravidadesRecentes[direito, default: []]
        guard recentes.count >= 5, let ultima = ultimaDoLado[direito], Date().timeIntervalSince(ultima) < 1.5 else { return nil }
        let soma = recentes.reduce(SIMD3<Double>(0, 0, 0), +)
        return simd_length(soma) > 0.01 ? simd_normalize(soma) : nil
    }

    // MARK: CMHeadphoneMotionManagerDelegate (chega fora da main thread)

    func headphoneMotionManagerDidConnect(_ manager: CMHeadphoneMotionManager) {
        NSLog("[PodControl] conectou")
        DispatchQueue.main.async {
            guard self.fonte == .airpods else { return }
            self.conectado = true
            // Normalmente a leitura volta sozinha; se não voltar, reinicia.
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                if self.conectado && !self.recebendo { self.reiniciarLeitura() }
            }
        }
    }

    func headphoneMotionManagerDidDisconnect(_ manager: CMHeadphoneMotionManager) {
        NSLog("[PodControl] desconectou")
        DispatchQueue.main.async {
            guard self.fonte == .airpods else { return }
            self.conectado = false
            self.recebendo = false
            self.lado = nil
        }
    }
}
