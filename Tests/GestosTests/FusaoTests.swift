import XCTest
import simd
@testable import Gestos

final class FusaoTests: XCTestCase {
    func testParadoNaMesa() {
        let f = FusaoIMU()
        var a: Amostra!
        for i in 0..<100 { a = f.processar(acel: SIMD3(0, 0, 1), giro: SIMD3(3.5, -3.2, 2.3), tempo: Double(i) / 50) }
        XCTAssertEqual(a.gravidade.z, -1, accuracy: 0.01)
        XCTAssertLessThan(simd_length(a.aceleracao), 0.01)
        // O desvio de 3,5 graus/s precisa sumir sozinho.
        XCTAssertLessThan(simd_length(a.rotacao) * 180 / .pi, 0.5)
    }

    func testDeCabecaParaBaixo() {
        let f = FusaoIMU()
        var a: Amostra!
        for i in 0..<50 { a = f.processar(acel: SIMD3(0, 0, -1), giro: .zero, tempo: Double(i) / 50) }
        XCTAssertEqual(a.gravidade.z, 1, accuracy: 0.01)
    }

    func testGravidadeAcompanhaAVirada() {
        // Começa deitado e tomba 90 graus em torno de X em 0,5 s; o acelerômetro acompanha.
        let f = FusaoIMU()
        var a: Amostra!
        for i in 0..<50 { a = f.processar(acel: SIMD3(0, 0, 1), giro: .zero, tempo: Double(i) / 50) }
        for i in 0...25 {
            let ang = Double(i) / 25 * .pi / 2
            a = f.processar(acel: SIMD3(0, sin(ang), cos(ang)), giro: SIMD3(180, 0, 0), tempo: 1 + Double(i) / 50)
        }
        for i in 0..<25 { a = f.processar(acel: SIMD3(0, 1, 0), giro: .zero, tempo: 1.6 + Double(i) / 50) }
        XCTAssertEqual(a.gravidade.y, -1, accuracy: 0.05)
    }

    func testGiroNaMesaViraPassos() {
        // Fusão + detector: girar 90 graus/s por 1 s na mesa dá 6 passos de 15 graus.
        let f = FusaoIMU(), d = DetectorDeGestos()
        for i in 0..<100 { _ = f.processar(acel: SIMD3(0, 0, 1), giro: .zero, tempo: Double(i) / 50) }
        d.ladoA = SIMD3(0, 0, -1)
        var passos = 0
        for i in 0...53 {
            let s = f.processar(acel: SIMD3(0, 0, 1), giro: SIMD3(0, 0, -90), tempo: 2 + Double(i) / 50)
            for case let .giro(_, p) in d.processar(s) { passos += p }
        }
        // Vista de cima, girar no sentido horário é rotação negativa em Z (Z para cima).
        XCTAssertEqual(passos, 6)
    }

    func testChacoalharNaoEstragaGravidade() {
        let f = FusaoIMU()
        var a: Amostra!
        for i in 0..<50 { a = f.processar(acel: SIMD3(0, 0, 1), giro: .zero, tempo: Double(i) / 50) }
        for i in 0..<30 { a = f.processar(acel: SIMD3(i % 2 == 0 ? 3 : -3, 0, 1), giro: .zero, tempo: 1 + Double(i) / 50) }
        XCTAssertEqual(a.gravidade.z, -1, accuracy: 0.05)
        XCTAssertGreaterThan(simd_length(a.aceleracao), 2)
    }
}
