/// Quem manda na cabine do Onda. O valor é o canal MIDI, contado do zero.
public enum Mao: UInt32 {
    /// Uma mão só, que segue o crossfader: o objeto de mesa, ou um fone.
    case unica = 0
    /// Fone esquerdo, no Deck 1.
    case esquerda = 1
    /// Fone direito, no Deck 2.
    case direita = 2
}

/// Mensagem de controle no formato de 32 bits do MIDI 1.0.
public func palavraMIDI(mao: Mao, numero: UInt32, valor: UInt32) -> UInt32 {
    0x20B0_0000 | mao.rawValue << 16 | numero << 8 | valor
}
