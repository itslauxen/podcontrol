import XCTest
import simd
@testable import Gestos

final class DetectorTests: XCTestCase {
    let baixoZ = SIMD3<Double>(0, 0, -1)
    let zero = SIMD3<Double>(0, 0, 0)

    func detectorCalibrado() -> DetectorDeGestos {
        let d = DetectorDeGestos()
        d.ladoA = baixoZ
        return d
    }

    /// Simula `segundos` girando a `grausPorSeg` em torno da vertical, a 50 Hz.
    func girar(_ d: DetectorDeGestos, gravidade: SIMD3<Double>, grausPorSeg: Double, segundos: Double, inicio: Double) -> [Evento] {
        var ev: [Evento] = []
        let w = grausPorSeg * .pi / 180
        let n = Int(segundos * 50)
        for i in 0...n {
            ev += d.processar(Amostra(gravidade: gravidade, rotacao: simd_normalize(gravidade) * w, aceleracao: zero, tempo: inicio + Double(i) / 50))
        }
        return ev
    }

    func passos(_ ev: [Evento]) -> [Lado: Int] {
        var r: [Lado: Int] = [:]
        for case let .giro(lado, p) in ev { r[lado, default: 0] += p }
        return r
    }

    func testSemCalibracaoNaoGira() {
        let d = DetectorDeGestos()
        let ev = girar(d, gravidade: baixoZ, grausPorSeg: 90, segundos: 1.05, inicio: 0)
        XCTAssertTrue(passos(ev).isEmpty)
    }

    func testGiroHorarioNoLadoA() {
        let d = detectorCalibrado()
        let ev = girar(d, gravidade: baixoZ, grausPorSeg: 90, segundos: 1.05, inicio: 0)
        XCTAssertTrue(ev.contains(.mudouLado(.a)))
        XCTAssertEqual(passos(ev)[.a], 6) // 90° com passo de 15°
    }

    func testTrocarDeFonteComRelogioMenorNaoTravaOGiro() {
        let d = detectorCalibrado()
        // Chacoalha com o relógio dos AirPods (tempo de sistema, grande)...
        _ = chacoalhar(d, inicio: 150_000)
        // ...e depois gira com o relógio do objeto, que começa perto de zero.
        let ev = girar(d, gravidade: baixoZ, grausPorSeg: 90, segundos: 1.05, inicio: 2000)
        XCTAssertEqual(passos(ev)[.a], 6)
    }

    func testGiroAntiHorarioDiminui() {
        let d = detectorCalibrado()
        let ev = girar(d, gravidade: baixoZ, grausPorSeg: -60, segundos: 1.05, inicio: 0)
        XCTAssertEqual(passos(ev)[.a], -4)
    }

    func testLadoBEhOOpostoDoA() {
        let d = detectorCalibrado()
        let ev = girar(d, gravidade: -baixoZ, grausPorSeg: 90, segundos: 1.05, inicio: 0)
        XCTAssertTrue(ev.contains(.mudouLado(.b)))
        XCTAssertEqual(passos(ev)[.b], 6)
        XCTAssertNil(passos(ev)[.a])
    }

    func testFoneEmPeNaoEhNenhumLado() {
        let d = detectorCalibrado()
        let ev = girar(d, gravidade: SIMD3(1, 0, 0), grausPorSeg: 90, segundos: 1.05, inicio: 0)
        XCTAssertTrue(passos(ev).isEmpty)
        XCTAssertNil(d.ladoAtual)
    }

    func testRuidoLentoNaoGira() {
        let d = detectorCalibrado()
        let ev = girar(d, gravidade: baixoZ, grausPorSeg: 10, segundos: 5, inicio: 0)
        XCTAssertTrue(passos(ev).isEmpty)
    }

    func testInverterSentido() {
        let d = detectorCalibrado()
        d.ajustes.inverterSentido = true
        let ev = girar(d, gravidade: baixoZ, grausPorSeg: 90, segundos: 1.05, inicio: 0)
        XCTAssertEqual(passos(ev)[.a], -6)
    }

    /// Três trancos fortes em 0,6 s.
    func chacoalhar(_ d: DetectorDeGestos, inicio: Double) -> [Evento] {
        var ev: [Evento] = []
        for i in 0..<30 {
            let t = inicio + Double(i) / 50
            let forte = (i % 10) < 3
            let a = forte ? SIMD3<Double>(1.8 * (i % 20 < 10 ? 1 : -1), 0, 0) : zero
            ev += d.processar(Amostra(gravidade: baixoZ, rotacao: SIMD3(0, 0, forte ? -3 : 0), aceleracao: a, tempo: t))
        }
        return ev
    }

    func testChacoalhadaDisparaUmaVez() {
        let d = detectorCalibrado()
        let ev = chacoalhar(d, inicio: 0)
        XCTAssertEqual(ev.filter { $0 == .chacoalhada }.count, 1)
        XCTAssertTrue(passos(ev).isEmpty, "chacoalhar não pode mexer no volume")
    }

    func testDuasSacudidasNaoBastam() {
        let d = detectorCalibrado()
        var ev: [Evento] = []
        for i in 0..<20 {
            let forte = (i % 10) < 3
            ev += d.processar(Amostra(gravidade: baixoZ, rotacao: zero, aceleracao: forte ? SIMD3(1.5, 0, 0) : zero, tempo: Double(i) / 50))
        }
        XCTAssertFalse(ev.contains(.chacoalhada))
    }

    func testIntervaloEntreChacoalhadas() {
        let d = detectorCalibrado()
        let ev = chacoalhar(d, inicio: 0) + chacoalhar(d, inicio: 0.6) + chacoalhar(d, inicio: 3)
        XCTAssertEqual(ev.filter { $0 == .chacoalhada }.count, 2)
    }

    func testAndarNaoChacoalha() {
        let d = detectorCalibrado()
        var ev: [Evento] = []
        for i in 0..<500 { // 10 s de passos com picos de 0,4 g
            let t = Double(i) / 50
            ev += d.processar(Amostra(gravidade: SIMD3(1, 0, 0), rotacao: zero, aceleracao: SIMD3(0.4 * sin(t * 12), 0, 0), tempo: t))
        }
        XCTAssertFalse(ev.contains(.chacoalhada))
    }
}
