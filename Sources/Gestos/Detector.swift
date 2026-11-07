import Foundation
import simd

/// Uma leitura do sensor do fone, já no referencial do próprio fone.
public struct Amostra {
    /// Vetor da gravidade (em g). Aponta para o chão.
    public var gravidade: SIMD3<Double>
    /// Velocidade de rotação (rad/s).
    public var rotacao: SIMD3<Double>
    /// Aceleração do usuário, sem a gravidade (em g).
    public var aceleracao: SIMD3<Double>
    /// Instante da leitura (s).
    public var tempo: TimeInterval

    public init(gravidade: SIMD3<Double>, rotacao: SIMD3<Double>, aceleracao: SIMD3<Double>, tempo: TimeInterval) {
        self.gravidade = gravidade
        self.rotacao = rotacao
        self.aceleracao = aceleracao
        self.tempo = tempo
    }
}

/// Lado em que o fone está deitado na mesa.
public enum Lado: String, Codable, CaseIterable {
    case a, b
    public var nome: String { self == .a ? "Lado A" : "Lado B" }
}

public enum Evento: Equatable {
    /// Girou na mesa. `passos` > 0 é sentido horário (visto de cima).
    case giro(lado: Lado, passos: Int)
    case chacoalhada
    case mudouLado(Lado?)
}

public struct AjustesDoDetector {
    /// Quantos graus de giro valem um passo (ex.: um degrau de volume).
    public var grausPorPasso: Double = 15
    /// Pico de aceleração (em g) que conta como uma sacudida.
    public var limiarChacoalhada: Double = 1.0
    /// Quantas sacudidas dentro da janela disparam a chacoalhada.
    public var picosParaChacoalhar = 3
    public var janelaChacoalhada: TimeInterval = 1.0
    public var intervaloEntreChacoalhadas: TimeInterval = 1.5
    /// Giro mais lento que isso (rad/s) é ignorado, para matar ruído e deriva.
    public var zonaMorta: Double = 0.35
    /// Quão alinhada com o lado gravado a gravidade precisa estar (cosseno).
    public var toleranciaLado: Double = 0.9
    public var inverterSentido = false
    public init() {}
}

/// Transforma o fluxo de amostras em gestos. Não sabe nada de AirPods nem de ações.
public final class DetectorDeGestos {
    public var ajustes = AjustesDoDetector()
    /// Gravidade gravada com o fone deitado em cada lado (vetor unitário).
    public var ladoA: SIMD3<Double>?
    public var ladoB: SIMD3<Double>?

    public private(set) var ladoAtual: Lado?
    /// Velocidade de giro em torno do eixo vertical (graus/s), para mostrar na tela.
    public private(set) var giroAtual: Double = 0
    /// Intensidade da aceleração (g), para mostrar na tela.
    public private(set) var agitacao: Double = 0

    private var ultimoTempo: TimeInterval?
    private var anguloAcumulado: Double = 0
    private var omegaAnterior: Double = 0
    private var picos: [TimeInterval] = []
    private var acimaDoLimiar = false
    private var ultimaChacoalhada: TimeInterval = -.infinity
    private var giroBloqueadoAte: TimeInterval = -.infinity

    public init() {}

    /// Lado B, se não foi gravado, é o oposto do lado A.
    private var referenciaB: SIMD3<Double>? { ladoB ?? ladoA.map { -$0 } }

    public func processar(_ s: Amostra) -> [Evento] {
        var eventos: [Evento] = []
        // Relógio voltou para trás: trocou de fonte (AirPods e objeto contam o tempo de jeitos diferentes)
        // ou a placa reiniciou. Bloqueios marcados no relógio antigo ficariam no futuro e travariam o giro.
        if let u = ultimoTempo, s.tempo < u {
            ultimoTempo = nil
            giroBloqueadoAte = -.infinity
            ultimaChacoalhada = -.infinity
            picos.removeAll()
        }
        // Até meio segundo sem leitura (buraco no Bluetooth) ainda conta: o giro feito nesse tempo não se perde.
        let dt = ultimoTempo.map { min(max(s.tempo - $0, 0), 0.5) } ?? 0
        ultimoTempo = s.tempo

        // Chacoalhada: conta subidas da aceleração acima do limiar dentro da janela.
        agitacao = simd_length(s.aceleracao)
        if agitacao > ajustes.limiarChacoalhada {
            if !acimaDoLimiar { picos.append(s.tempo) }
            acimaDoLimiar = true
        } else if agitacao < ajustes.limiarChacoalhada * 0.6 {
            acimaDoLimiar = false
        }
        picos.removeAll { s.tempo - $0 > ajustes.janelaChacoalhada }
        if picos.count >= 2 {
            // Sacudindo: giro não vale até acalmar. Um tranco só da mão girando não bloqueia.
            giroBloqueadoAte = max(giroBloqueadoAte, s.tempo + 0.4)
        }
        if picos.count >= ajustes.picosParaChacoalhar,
           s.tempo - ultimaChacoalhada > ajustes.intervaloEntreChacoalhadas {
            ultimaChacoalhada = s.tempo
            picos.removeAll()
            giroBloqueadoAte = s.tempo + 0.8
            anguloAcumulado = 0
            eventos.append(.chacoalhada)
        }

        // Em que lado o fone está deitado.
        let g = simd_length(s.gravidade) > 0.01 ? simd_normalize(s.gravidade) : SIMD3<Double>(0, 0, 0)
        let novoLado = classificar(g)
        if novoLado != ladoAtual {
            ladoAtual = novoLado
            anguloAcumulado = 0
            eventos.append(.mudouLado(novoLado))
        }

        // Giro em torno do eixo vertical: projeta a rotação na direção da gravidade.
        // Com a gravidade apontando para baixo, positivo = horário visto de cima.
        let omega = simd_dot(s.rotacao, g)
        // Média com a leitura anterior: num buraco, supõe que a velocidade mudou aos poucos.
        let omegaMedio = (omega + omegaAnterior) / 2
        omegaAnterior = omega
        giroAtual = omega * 180 / .pi
        guard let lado = ladoAtual, s.tempo >= giroBloqueadoAte else { return eventos }
        if abs(omega) < ajustes.zonaMorta { return eventos }

        anguloAcumulado += omegaMedio * dt * 180 / .pi * (ajustes.inverterSentido ? -1 : 1)
        var passos = 0
        while anguloAcumulado >= ajustes.grausPorPasso { passos += 1; anguloAcumulado -= ajustes.grausPorPasso }
        while anguloAcumulado <= -ajustes.grausPorPasso { passos -= 1; anguloAcumulado += ajustes.grausPorPasso }
        if passos != 0 { eventos.append(.giro(lado: lado, passos: passos)) }
        return eventos
    }

    private func classificar(_ g: SIMD3<Double>) -> Lado? {
        guard let a = ladoA else { return nil }
        let da = simd_dot(g, a)
        let db = referenciaB.map { simd_dot(g, $0) } ?? -1
        // Histerese: para continuar no lado atual basta um alinhamento um pouco menor.
        let tol = ajustes.toleranciaLado
        let tolA = ladoAtual == .a ? tol - 0.05 : tol
        let tolB = ladoAtual == .b ? tol - 0.05 : tol
        if da >= tolA && da >= db { return .a }
        if db >= tolB && db > da { return .b }
        return nil
    }
}
