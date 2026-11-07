import Foundation
import simd
import Gestos

/// O que o usuário escolheu no painel. Salvo no UserDefaults a cada mudança.
final class Configuracoes: ObservableObject {
    private let ud = UserDefaults.standard

    @Published var ativo: Bool { didSet { ud.set(ativo, forKey: "ativo") } }
    /// Cada fonte tem seus próprios lados gravados.
    @Published var fonte: Fonte {
        didSet {
            ud.set(fonte.rawValue, forKey: "fonte")
            ladoA = Self.vetor(ud.array(forKey: "ladoA.\(fonte.rawValue)"))
            ladoB = Self.vetor(ud.array(forKey: "ladoB.\(fonte.rawValue)"))
        }
    }
    @Published var giroA: AcaoGiro { didSet { ud.set(giroA.rawValue, forKey: "giroA") } }
    @Published var giroB: AcaoGiro { didSet { ud.set(giroB.rawValue, forKey: "giroB") } }
    @Published var chacoalhar: AcaoGatilho { didSet { ud.set(chacoalhar.rawValue, forKey: "chacoalhar") } }
    @Published var app: URL? { didSet { ud.set(app?.path, forKey: "app") } }
    @Published var grausPorPasso: Double { didSet { ud.set(grausPorPasso, forKey: "grausPorPasso") } }
    @Published var forcaChacoalhada: Double { didSet { ud.set(forcaChacoalhada, forKey: "forcaChacoalhada") } }
    @Published var inverterSentido: Bool { didSet { ud.set(inverterSentido, forKey: "inverterSentido") } }
    /// Com os AirPods como controle, o som volta para o alto-falante do Mac se o macOS jogar para o fone.
    @Published var manterSomNoMac: Bool { didSet { ud.set(manterSomNoMac, forKey: "manterSomNoMac") } }
    /// Fone apontado para a tela vira mouse; o aperto na haste vira clique.
    @Published var modoMouse: Bool { didSet { ud.set(modoMouse, forKey: "modoMouse") } }
    @Published var velocidadeMouse: Double { didSet { ud.set(velocidadeMouse, forKey: "velocidadeMouse") } }
    @Published var hasteMouse: SIMD3<Double>? { didSet { ud.set(hasteMouse.map { [$0.x, $0.y, $0.z] }, forKey: "hasteMouse") } }
    /// O giro e a inclinação viram uma controladora MIDI para a cabine do Onda.
    @Published var modoControladora: Bool { didSet { ud.set(modoControladora, forKey: "modoControladora") } }
    /// Na controladora, cada fone comanda um deck.
    @Published var doisFones: Bool { didSet { ud.set(doisFones, forKey: "doisFones") } }
    /// Lados do fone direito, usados só com um fone em cada deck.
    @Published var ladoADireito: SIMD3<Double>? { didSet { ud.set(ladoADireito.map { [$0.x, $0.y, $0.z] }, forKey: "ladoA.airpods.direito") } }
    @Published var ladoBDireito: SIMD3<Double>? { didSet { ud.set(ladoBDireito.map { [$0.x, $0.y, $0.z] }, forKey: "ladoB.airpods.direito") } }
    // Integrações (lidas direto do UserDefaults por HomeAssistant e Alexa).
    @Published var haEndereco: String { didSet { ud.set(haEndereco, forKey: "ha.endereco") } }
    @Published var haToken: String { didSet { ud.set(haToken, forKey: "ha.token") } }
    @Published var haLuz1: String { didSet { ud.set(haLuz1, forKey: "ha.luz1") } }
    @Published var haNomeLuz1: String { didSet { ud.set(haNomeLuz1, forKey: "ha.nomeLuz1") } }
    @Published var haLuz2: String { didSet { ud.set(haLuz2, forKey: "ha.luz2") } }
    @Published var haNomeLuz2: String { didSet { ud.set(haNomeLuz2, forKey: "ha.nomeLuz2") } }
    @Published var alexaAparelho: String { didSet { ud.set(alexaAparelho, forKey: "alexa.aparelho") } }
    @Published var alexaDominio: String { didSet { ud.set(alexaDominio, forKey: "alexa.dominio") } }
    @Published var alexaToken: String { didSet { ud.set(alexaToken, forKey: "alexa.token") } }
    @Published var ladoA: SIMD3<Double>? { didSet { ud.set(ladoA.map { [$0.x, $0.y, $0.z] }, forKey: "ladoA.\(fonte.rawValue)") } }
    @Published var ladoB: SIMD3<Double>? { didSet { ud.set(ladoB.map { [$0.x, $0.y, $0.z] }, forKey: "ladoB.\(fonte.rawValue)") } }

    init() {
        ativo = ud.object(forKey: "ativo") as? Bool ?? true
        let f = Fonte(rawValue: ud.string(forKey: "fonte") ?? "") ?? .airpods
        fonte = f
        giroA = AcaoGiro(rawValue: ud.string(forKey: "giroA") ?? "") ?? .volume
        giroB = AcaoGiro(rawValue: ud.string(forKey: "giroB") ?? "") ?? .brilho
        chacoalhar = AcaoGatilho(rawValue: ud.string(forKey: "chacoalhar") ?? "") ?? .abrirApp
        app = ud.string(forKey: "app").map { URL(fileURLWithPath: $0) }
        grausPorPasso = ud.object(forKey: "grausPorPasso") as? Double ?? 15
        forcaChacoalhada = ud.object(forKey: "forcaChacoalhada") as? Double ?? 1.0
        inverterSentido = ud.bool(forKey: "inverterSentido")
        manterSomNoMac = ud.bool(forKey: "manterSomNoMac")
        modoMouse = ud.bool(forKey: "modoMouse")
        velocidadeMouse = ud.object(forKey: "velocidadeMouse") as? Double ?? 1
        hasteMouse = Self.vetor(ud.array(forKey: "hasteMouse"))
        modoControladora = ud.bool(forKey: "modoControladora")
        doisFones = ud.object(forKey: "doisFones") as? Bool ?? true
        ladoADireito = Self.vetor(ud.array(forKey: "ladoA.airpods.direito"))
        ladoBDireito = Self.vetor(ud.array(forKey: "ladoB.airpods.direito"))
        haEndereco = ud.string(forKey: "ha.endereco") ?? ""
        haToken = ud.string(forKey: "ha.token") ?? ""
        haLuz1 = ud.string(forKey: "ha.luz1") ?? ""
        haNomeLuz1 = ud.string(forKey: "ha.nomeLuz1") ?? ""
        haLuz2 = ud.string(forKey: "ha.luz2") ?? ""
        haNomeLuz2 = ud.string(forKey: "ha.nomeLuz2") ?? ""
        alexaAparelho = ud.string(forKey: "alexa.aparelho") ?? ""
        alexaDominio = ud.string(forKey: "alexa.dominio") ?? "amazon.com.br"
        alexaToken = ud.string(forKey: "alexa.token") ?? ""
        // Sobras do joystick, que saiu do app.
        for chave in ["posicaoC", "pontosJoystick", "frenteRadial", "frenteJoystick"] { ud.removeObject(forKey: "\(chave).\(f.rawValue)") }
        ud.removeObject(forKey: "sensibilidadeJoystick")
        ladoA = Self.vetor(ud.array(forKey: "ladoA.\(f.rawValue)"))
        ladoB = Self.vetor(ud.array(forKey: "ladoB.\(f.rawValue)"))
        // Lados gravados antes de existir mais de uma fonte não servem mais.
        ud.removeObject(forKey: "ladoA")
        ud.removeObject(forKey: "ladoB")
    }

    private static func vetor(_ a: [Any]?) -> SIMD3<Double>? {
        guard let d = a as? [Double], d.count == 3 else { return nil }
        return SIMD3(d[0], d[1], d[2])
    }

    func acaoDeGiro(_ lado: Lado) -> AcaoGiro { lado == .a ? giroA : giroB }

    var precisaAcessibilidade: Bool {
        giroA.precisaAcessibilidade || giroB.precisaAcessibilidade || chacoalhar.precisaAcessibilidade || modoMouse
    }
}
