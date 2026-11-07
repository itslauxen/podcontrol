import XCTest
@testable import Gestos

final class MaoTests: XCTestCase {
    func testCadaMaoVaiNoSeuCanalMIDI() {
        // Tipo 2 (MIDI 1.0), grupo 0, controle no canal 1, 2 ou 3, CC 20, valor 65.
        XCTAssertEqual(palavraMIDI(mao: .unica, numero: 20, valor: 65), 0x20B0_1441)
        XCTAssertEqual(palavraMIDI(mao: .esquerda, numero: 20, valor: 65), 0x20B1_1441)
        XCTAssertEqual(palavraMIDI(mao: .direita, numero: 20, valor: 65), 0x20B2_1441)
    }
}
