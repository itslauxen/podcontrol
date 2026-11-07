import CoreMIDI
import Foundation
import Gestos

/// Controladora MIDI virtual: o Mac passa a ver um aparelho chamado PodControl, e a cabine do Onda escuta por ele.
/// O protocolo é o mesmo de web/booth.html (procurar `MIDI_GIRO`).
@MainActor
enum Controladora {
    /// Quantos graus de giro valem 1/128 do curso de um controle: o curso inteiro cabe em ~150 graus.
    nonisolated static let grausPorPasso = 150.0 / 128

    private static let ccGiro: UInt32 = 20, ccFatia: UInt32 = 21, ccRoda: UInt32 = 22
    /// Quanto girar para andar uma fatia da roda.
    private static let grausPorFatia = 16.0
    private static var cliente = MIDIClientRef()
    private static var fonte = MIDIEndpointRef()
    private static var giroNaRoda: [Mao: Int] = [:]

    static func ligar() {
        guard fonte == 0 else { return }
        var status = MIDIClientCreateWithBlock("PodControl" as CFString, &cliente, nil)
        if status == noErr { status = MIDISourceCreateWithProtocol(cliente, "PodControl" as CFString, ._1_0, &fonte) }
        if status != noErr { NSLog("[PodControl] midi: erro %d", status) }
    }

    /// Relativo: a cabine soma ao valor atual, então o mouse e o objeto nunca brigam.
    static func girar(_ passos: Int, mao: Mao) {
        var falta = passos
        while falta != 0 {
            let parte = min(max(falta, -63), 63)
            enviar(ccGiro, UInt32(64 + parte), mao)
            falta -= parte
        }
    }

    /// Abre ou fecha a roda da cabine.
    static func abrirRoda(_ aberta: Bool, mao: Mao) { enviar(ccRoda, aberta ? 127 : 0, mao) }

    /// Junta o giro e anda uma fatia a cada `grausPorFatia`. Horário vai para a próxima.
    static func andarNaRoda(_ passos: Int, mao: Mao) {
        let giro = giroNaRoda[mao, default: 0] + passos
        let porFatia = Int((grausPorFatia / grausPorPasso).rounded())
        let fatias = giro / porFatia
        giroNaRoda[mao] = giro - fatias * porFatia
        for _ in 0..<abs(fatias) { enviar(ccFatia, fatias > 0 ? 65 : 63, mao) }
    }

    private static func enviar(_ numero: UInt32, _ valor: UInt32, _ mao: Mao) {
        guard fonte != 0 else { return }
        var palavra = palavraMIDI(mao: mao, numero: numero, valor: valor)
        var lista = MIDIEventList()
        let pacote = MIDIEventListInit(&lista, ._1_0)
        MIDIEventListAdd(&lista, MemoryLayout<MIDIEventList>.size, pacote, 0, 1, &palavra)
        MIDIReceivedEventList(fonte, &lista)
    }
}
