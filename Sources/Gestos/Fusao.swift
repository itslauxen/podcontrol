import Foundation
import simd

/// Junta acelerômetro e giroscópio brutos (ex.: MPU6050) numa `Amostra` igual à do Core Motion:
/// gravidade separada do movimento e giro sem o desvio de fábrica.
public final class FusaoIMU {
    /// "Para cima" estimado, no referencial do sensor (unitário).
    private var cima: SIMD3<Double>?
    /// Desvio do giroscópio parado (graus/s), aprendido sozinho quando o objeto está quieto.
    public private(set) var desvioGiro = SIMD3<Double>(0, 0, 0)
    private var ultimoTempo: TimeInterval?
    private var paradoDesde: TimeInterval?
    private var aprendeuDesvio = false
    private var somaGiro = SIMD3<Double>(0, 0, 0)
    private var contagem = 0

    /// Quanto confiar no acelerômetro a cada leitura para corrigir a direção da gravidade.
    public var ganhoAcel = 0.02

    public init() {}

    /// - Parameters:
    ///   - acel: leitura do acelerômetro em g (parado na mesa, aponta para cima com ~1 g).
    ///   - giro: leitura do giroscópio em graus/s.
    ///   - tempo: instante da leitura em segundos.
    public func processar(acel: SIMD3<Double>, giro: SIMD3<Double>, tempo: TimeInterval) -> Amostra {
        let dt = ultimoTempo.map { min(max(tempo - $0, 0), 0.1) } ?? 0
        ultimoTempo = tempo
        let normaAcel = simd_length(acel)

        // Aprende o desvio do giroscópio enquanto o objeto está parado.
        if !aprendeuDesvio {
            // Calibração inicial: média do primeiro meio segundo parado.
            if abs(normaAcel - 1) < 0.05 && simd_length(giro) < 15 {
                if paradoDesde == nil { paradoDesde = tempo; somaGiro = .zero; contagem = 0 }
                somaGiro += giro
                contagem += 1
                if tempo - (paradoDesde ?? tempo) >= 0.5 {
                    desvioGiro = somaGiro / Double(contagem)
                    aprendeuDesvio = true
                    paradoDesde = nil
                }
            } else {
                paradoDesde = nil
            }
        } else if abs(normaAcel - 1) < 0.05 && simd_length(giro - desvioGiro) < 4 {
            // Depois, acompanha devagar a variação com a temperatura.
            paradoDesde = paradoDesde ?? tempo
            if tempo - (paradoDesde ?? tempo) > 0.5 { desvioGiro += (giro - desvioGiro) * 0.01 }
        } else {
            paradoDesde = nil
        }
        let w = (giro - desvioGiro) * .pi / 180 // rad/s

        // Filtro complementar: gira a estimativa junto com o objeto e puxa devagar para o acelerômetro.
        if var c = cima {
            c -= simd_cross(w, c) * dt
            // Durante trancos o acelerômetro mente; confia nele só perto de 1 g.
            let confianca = max(0, 1 - abs(normaAcel - 1) / 0.3)
            if normaAcel > 0.1 { c += (simd_normalize(acel) - c) * ganhoAcel * confianca }
            cima = simd_normalize(c)
        } else if normaAcel > 0.1 {
            cima = simd_normalize(acel)
        }
        let gravidade = -(cima ?? SIMD3(0, 0, 1))
        // Acel medida = movimento - gravidade, então movimento = medida + gravidade.
        let movimento = acel + gravidade
        return Amostra(gravidade: gravidade, rotacao: w, aceleracao: movimento, tempo: tempo)
    }
}
