import CoreBluetooth
import Foundation
import simd

/// Conecta no objeto de mesa (ESP32 + MPU6050) por Bluetooth LE e entrega as leituras brutas.
/// O formato do pacote está descrito em firmware/podcontrol_objeto/podcontrol_objeto.ino.
final class FonteObjeto: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
    static let servico = CBUUID(string: "7a1e0001-5c3b-4f0e-9a51-0d0c0b0a0901")
    static let leitura = CBUUID(string: "7a1e0002-5c3b-4f0e-9a51-0d0c0b0a0901")
    private static let porG = 4096.0       // acelerômetro em +-8 g
    private static let porGrauSeg = 32.8   // giroscópio em +-1000 graus/s

    /// (aceleração em g, giro em graus/s, tempo em s)
    var aoLer: ((SIMD3<Double>, SIMD3<Double>, TimeInterval) -> Void)?
    /// (conectado, mensagem para a tela)
    var aoMudarEstado: ((Bool, String) -> Void)?

    private var central: CBCentralManager?
    private var objeto: CBPeripheral?
    private var ativo = false
    private var ultimoBruto: UInt32?
    private var tempo: TimeInterval = 0

    func iniciar() {
        NSLog("[PodControl] objeto: iniciar, permissao=%d", CBManager.authorization.rawValue)
        ativo = true
        if central == nil { central = CBCentralManager(delegate: self, queue: .main) } else { procurar() }
    }

    func parar() {
        ativo = false
        central?.stopScan()
        if let o = objeto { central?.cancelPeripheralConnection(o) }
        objeto = nil
    }

    private func procurar() {
        guard ativo, let c = central, c.state == .poweredOn else { return }
        aoMudarEstado?(false, "Procurando o objeto PodControl…")
        if let jaConectado = c.retrieveConnectedPeripherals(withServices: [Self.servico]).first {
            conectar(jaConectado)
        } else {
            // Busca sem filtro: o filtro por serviço falha se o UUID não couber no anúncio.
            c.scanForPeripherals(withServices: nil)
        }
    }

    private func conectar(_ p: CBPeripheral) {
        central?.stopScan()
        objeto = p
        p.delegate = self
        central?.connect(p)
    }

    // MARK: CBCentralManagerDelegate

    func centralManagerDidUpdateState(_ c: CBCentralManager) {
        NSLog("[PodControl] bluetooth estado=%d permissao=%d", c.state.rawValue, CBManager.authorization.rawValue)
        switch c.state {
        case .poweredOn: procurar()
        case .poweredOff: aoMudarEstado?(false, "O Bluetooth do Mac está desligado")
        case .unauthorized: aoMudarEstado?(false, "Sem permissão de Bluetooth")
        default: aoMudarEstado?(false, "Bluetooth indisponível")
        }
    }

    func centralManager(_ c: CBCentralManager, didDiscover p: CBPeripheral, advertisementData: [String: Any], rssi: NSNumber) {
        let nome = p.name ?? advertisementData[CBAdvertisementDataLocalNameKey] as? String ?? ""
        let servicos = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] ?? []
        guard servicos.contains(Self.servico) || nome == "PodControl" else { return }
        NSLog("[PodControl] achou o objeto (sinal %@)", rssi)
        conectar(p)
    }

    func centralManager(_ c: CBCentralManager, didConnect p: CBPeripheral) {
        NSLog("[PodControl] conectou no objeto")
        p.discoverServices([Self.servico])
    }

    func centralManager(_ c: CBCentralManager, didFailToConnect p: CBPeripheral, error: Error?) {
        reconectarDepois()
    }

    func centralManager(_ c: CBCentralManager, didDisconnectPeripheral p: CBPeripheral, error: Error?) {
        reconectarDepois()
    }

    private func reconectarDepois() {
        objeto = nil
        ultimoBruto = nil
        aoMudarEstado?(false, "Objeto desconectado, procurando de novo…")
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.procurar() }
    }

    // MARK: CBPeripheralDelegate

    func peripheral(_ p: CBPeripheral, didDiscoverServices error: Error?) {
        NSLog("[PodControl] servicos=%@ erro=%@", p.services?.map(\.uuid.uuidString).description ?? "nil", error?.localizedDescription ?? "-")
        guard let s = p.services?.first(where: { $0.uuid == Self.servico }) else { return }
        p.discoverCharacteristics([Self.leitura], for: s)
    }

    func peripheral(_ p: CBPeripheral, didDiscoverCharacteristicsFor s: CBService, error: Error?) {
        NSLog("[PodControl] caracteristicas=%@ erro=%@", s.characteristics?.map(\.uuid.uuidString).description ?? "nil", error?.localizedDescription ?? "-")
        guard let c = s.characteristics?.first(where: { $0.uuid == Self.leitura }) else { return }
        p.setNotifyValue(true, for: c)
    }

    func peripheral(_ p: CBPeripheral, didUpdateNotificationStateFor c: CBCharacteristic, error: Error?) {
        NSLog("[PodControl] inscricao=%d erro=%@", c.isNotifying ? 1 : 0, error?.localizedDescription ?? "-")
        if c.isNotifying { aoMudarEstado?(true, "") }
    }

    func peripheral(_ p: CBPeripheral, didUpdateValueFor c: CBCharacteristic, error: Error?) {
        guard let d = c.value, d.count >= 16 else { return }
        let bruto = d.withUnsafeBytes { b -> (UInt32, [Int16]) in
            let t = UInt32(littleEndian: b.loadUnaligned(fromByteOffset: 0, as: UInt32.self))
            let v = (0..<6).map { Int16(littleEndian: b.loadUnaligned(fromByteOffset: 4 + $0 * 2, as: Int16.self)) }
            return (t, v)
        }
        // O relógio do ESP32 (micros) volta a zero a cada ~71 min; soma só a diferença.
        if let u = ultimoBruto { tempo += Double(bruto.0 &- u) / 1_000_000 }
        ultimoBruto = bruto.0
        let v = bruto.1.map(Double.init)
        aoLer?(SIMD3(v[0], v[1], v[2]) / Self.porG, SIMD3(v[3], v[4], v[5]) / Self.porGrauSeg, tempo)
    }
}
