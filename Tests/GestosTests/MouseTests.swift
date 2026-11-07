import XCTest
import simd
@testable import Gestos

final class MouseTests: XCTestCase {
    let baixo = SIMD3<Double>(0, 0, -1)
    let haste = SIMD3<Double>(1, 0, 0)

    func mouse() -> MouseDeMovimento {
        let m = MouseDeMovimento()
        m.haste = haste
        return m
    }

    /// Soma o deslocamento de 1 s com giro constante, a 50 Hz.
    func mover(_ m: MouseDeMovimento, gravidade: SIMD3<Double>, giro: SIMD3<Double>) -> (Int, Int) {
        var x = 0, y = 0
        for i in 0...50 {
            let d = m.processar(Amostra(gravidade: gravidade, rotacao: giro, aceleracao: .zero, tempo: Double(i) / 50))
            x += d.dx; y += d.dy
        }
        return (x, y)
    }

    func testGiroHorarioVaiParaADireita() {
        let (x, y) = mover(mouse(), gravidade: baixo, giro: baixo * 1)
        XCTAssertGreaterThan(x, 100)
        XCTAssertEqual(y, 0)
    }

    func testLevantarAPontaSobeOCursor() {
        // Eixo de subir = gravidade × haste.
        let (x, y) = mover(mouse(), gravidade: baixo, giro: simd_cross(baixo, haste))
        XCTAssertEqual(x, 0)
        XCTAssertLessThan(y, -100)
    }

    func testTremorDaMaoNaoMexe() {
        let (x, y) = mover(mouse(), gravidade: baixo, giro: SIMD3(0.03, 0.03, 0.03))
        XCTAssertEqual(x, 0)
        XCTAssertEqual(y, 0)
    }

    func testRapidoRendeMaisQueProporcional() {
        let (lento, _) = mover(mouse(), gravidade: baixo, giro: baixo * 1)
        let (rapido, _) = mover(mouse(), gravidade: baixo, giro: baixo * 3)
        XCTAssertGreaterThan(rapido, lento * 3)
    }

    func testSemCalibrarNaoMexe() {
        let (x, y) = mover(MouseDeMovimento(), gravidade: baixo, giro: baixo * 2)
        XCTAssertEqual(x, 0)
        XCTAssertEqual(y, 0)
    }

    func testRolarOFoneNaMaoNaoMudaOSentido() {
        // Fone rolado 90 graus em torno da haste: a gravidade aparece em outro eixo do corpo.
        let g = SIMD3<Double>(0, 1, 0)
        let (_, y) = mover(mouse(), gravidade: g, giro: simd_cross(g, haste))
        XCTAssertLessThan(y, -100)
    }

    func testCalibracaoAchaAHasteEOSentido() {
        let cal = CalibradorDoMouse()
        let subir = simd_cross(baixo, haste)
        // Primeiro sobe, depois desce: a gangorra pedida na tela.
        for i in 0..<150 {
            let giro = subir * sin(Double(i) / 150 * 2 * .pi * 2) * 2
            cal.adicionar(Amostra(gravidade: baixo, rotacao: giro, aceleracao: .zero, tempo: Double(i) / 50))
        }
        let achada = cal.concluir()
        XCTAssertNotNil(achada)
        XCTAssertEqual(simd_dot(achada ?? .zero, haste), 1, accuracy: 0.01)
    }

    func testCalibracaoSemMovimentoFalha() {
        let cal = CalibradorDoMouse()
        for i in 0..<150 {
            cal.adicionar(Amostra(gravidade: baixo, rotacao: SIMD3(0.01, 0, 0), aceleracao: .zero, tempo: Double(i) / 50))
        }
        XCTAssertNil(cal.concluir())
    }
}
