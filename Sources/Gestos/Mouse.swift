import Foundation
import simd

public struct AjustesDoMouse {
    /// Pixels por radiano girado, em movimento lento.
    public var velocidade: Double = 900
    /// Giro mais lento que isso (rad/s) é ignorado, para o tremor da mão não mexer o cursor.
    public var zonaMorta: Double = 0.06
    /// Quanto o movimento rápido rende a mais: lento dá precisão, rápido atravessa a tela.
    public var aceleracao: Double = 1.0
    public init() {}
}

/// Transforma o giro do fone apontado para a tela em movimento de cursor.
public final class MouseDeMovimento {
    public var ajustes = AjustesDoMouse()
    /// Direção da haste no corpo do fone (vetor unitário), vinda da calibração.
    public var haste: SIMD3<Double>?

    private var ultimoTempo: TimeInterval?
    private var restoX = 0.0, restoY = 0.0

    public init() {}

    /// Devolve quantos pixels mover. dx > 0 é direita, dy > 0 é para baixo, como na tela.
    public func processar(_ s: Amostra) -> (dx: Int, dy: Int) {
        let dt = ultimoTempo.map { min(max(s.tempo - $0, 0), 0.1) } ?? 0
        ultimoTempo = s.tempo
        guard let p = haste, simd_length(s.gravidade) > 0.01 else { return (0, 0) }
        let g = simd_normalize(s.gravidade)
        // Lado a lado: giro em torno da vertical. Com a gravidade para baixo, positivo = horário = direita.
        let lateral = simd_dot(s.rotacao, g)
        // Cima e baixo: eixo deitado, perpendicular à haste. Sai da gravidade atual, então
        // girar o fone em torno da própria haste na mão não muda o sentido.
        let eixo = simd_cross(g, p)
        let vertical = simd_length(eixo) > 0.2 ? simd_dot(s.rotacao, simd_normalize(eixo)) : 0

        restoX += deslocamento(lateral, dt)
        restoY -= deslocamento(vertical, dt)
        let dx = Int(restoX), dy = Int(restoY)
        restoX -= Double(dx)
        restoY -= Double(dy)
        return (dx, dy)
    }

    private func deslocamento(_ omega: Double, _ dt: Double) -> Double {
        let v = abs(omega) - ajustes.zonaMorta
        guard v > 0 else { return 0 }
        return (omega < 0 ? -1 : 1) * v * (1 + ajustes.aceleracao * v) * ajustes.velocidade * dt
    }
}

/// Descobre a haste: com ela apontada para a tela, a pessoa sobe e desce a ponta.
/// O eixo dessa gangorra, deitado e perpendicular à haste, é o maior giro fora da vertical.
public final class CalibradorDoMouse {
    private var giros: [SIMD3<Double>] = []
    private var somaGravidade = SIMD3<Double>(0, 0, 0)

    public init() {}

    public func adicionar(_ s: Amostra) {
        guard simd_length(s.gravidade) > 0.01 else { return }
        let g = simd_normalize(s.gravidade)
        somaGravidade += g
        giros.append(s.rotacao - g * simd_dot(s.rotacao, g))
    }

    /// Devolve a direção da haste, ou nil se quase não houve movimento.
    public func concluir() -> SIMD3<Double>? {
        guard giros.count >= 20, simd_length(somaGravidade) > 0.01 else { return nil }
        let media = giros.reduce(0) { $0 + simd_length_squared($1) } / Double(giros.count)
        guard media > 0.09 else { return nil } // menos de ~17 graus/s: não foi um movimento de verdade
        // A primeira subida define o sentido: a instrução manda começar levantando a ponta.
        guard let primeiro = giros.first(where: { simd_length($0) > 0.5 }) else { return nil }
        // Direção principal dos giros, por iteração de potência.
        var a = simd_normalize(primeiro)
        for _ in 0..<30 {
            let proximo = giros.reduce(SIMD3<Double>(0, 0, 0)) { $0 + $1 * simd_dot($1, a) }
            guard simd_length(proximo) > 0 else { return nil }
            a = simd_normalize(proximo)
        }
        if simd_dot(a, primeiro) < 0 { a = -a }
        let g = simd_normalize(somaGravidade)
        let haste = simd_cross(a, g)
        return simd_length(haste) > 0.1 ? simd_normalize(haste) : nil
    }
}
