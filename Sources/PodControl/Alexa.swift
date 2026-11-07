import Foundation

/// Um nível (0...1) que mora em outro aparelho. Na Alexa a API é não oficial e leva cerca de 1 s por comando,
/// então a tela acompanha o giro na hora e o aparelho recebe no máximo um valor por `intervaloEnvio`, mais o final.
@MainActor
final class NivelRemoto {
    /// Tempo parado que conta como fim do giro.
    private static let esperaFim: Duration = .milliseconds(150)
    /// Depois disso sem usar, lê de novo: o nível pode ter mudado por voz.
    private static let validade: TimeInterval = 300

    private let simbolo: String
    private let texto: String
    /// Nome de quem guarda o nível, para os avisos ("a Alexa", "o Home Assistant").
    private let origem: String
    /// Durante o giro, intervalo mínimo entre comandos, para não abusar da API.
    private let intervaloEnvio: TimeInterval
    private let lerNivel: () async -> Float?
    private let gravarNivel: (Int) async -> Bool

    private var nivel: Float?      // 0...1, o que a tela mostra
    private var enviado: Int?      // 0...100, o que o aparelho já recebeu
    private var giroPendente: Float = 0 // giro feito enquanto o nível não chegou
    private var ultimoUso = Date.distantPast
    private var ultimoEnvio = Date.distantPast
    private var ocupado = false    // um comando por vez
    private var fimDoGiro: Task<Void, Never>?

    init(simbolo: String, texto: String, origem: String = "a Alexa", intervaloEnvio: TimeInterval = 1,
         ler: @escaping () async -> Float?, gravar: @escaping (Int) async -> Bool) {
        self.simbolo = simbolo
        self.texto = texto
        self.origem = origem
        self.intervaloEnvio = intervaloEnvio
        lerNivel = ler
        gravarNivel = gravar
    }

    func mudar(by delta: Float) {
        if Date().timeIntervalSince(ultimoUso) > Self.validade { nivel = nil }
        ultimoUso = Date()
        guard let n = nivel else {
            giroPendente += delta
            HUD.mostrar(simbolo: "hourglass", texto: "Lendo \(origem)…")
            ler()
            return
        }
        aplicar(n + delta)
    }

    private func aplicar(_ valor: Float) {
        let v = min(max(valor, 0), 1)
        nivel = v
        HUD.mostrar(simbolo: simbolo, texto: texto, nivel: v)
        fimDoGiro?.cancel()
        fimDoGiro = Task {
            try? await Task.sleep(for: Self.esperaFim)
            guard !Task.isCancelled else { return }
            fimDoGiro = nil
            enviar()
        }
        if Date().timeIntervalSince(ultimoEnvio) >= intervaloEnvio { enviar() }
    }

    private func ler() {
        guard !ocupado else { return }
        ocupado = true
        Task {
            let lido = await lerNivel()
            ocupado = false
            let giro = giroPendente
            giroPendente = 0
            guard let lido else { return falhou() }
            enviado = Int((lido * 100).rounded())
            aplicar(lido + giro)
        }
    }

    private func enviar() {
        guard !ocupado, let n = nivel else { return }
        let alvo = Int((n * 100).rounded())
        guard alvo != enviado else { return }
        ocupado = true
        ultimoEnvio = Date()
        Task {
            let certo = await gravarNivel(alvo)
            NSLog("[PodControl] %@ -> %d em %.2f s", texto, alvo, Date().timeIntervalSince(ultimoEnvio))
            ocupado = false
            guard certo else { return falhou() }
            enviado = alvo
            if fimDoGiro == nil { enviar() } // parou de girar enquanto o comando andava
        }
    }

    private func falhou() {
        nivel = nil
        enviado = nil
        HUD.mostrar(simbolo: "exclamationmark.triangle.fill", texto: "Sem resposta d\(origem)")
    }
}

/// O que o PodControl controla pela conta da Alexa. As luzes ficam com o Home Assistant (HomeAssistant.swift).
@MainActor
enum Alexa {
    static let volume = NivelRemoto(simbolo: "homepod.fill", texto: "Volume da Alexa", ler: lerVolume, gravar: gravarVolume)

    private nonisolated static let casa = FileManager.default.homeDirectoryForCurrentUser
    /// O alexa-remote-control fica fora do app (ver README).
    nonisolated static let script = casa.appending(path: ".local/share/alexa-remote-control/alexa_remote_control.sh")
    private nonisolated static let cookie = "/tmp/.alexa.cookie" // o script mantém esse arquivo
    /// Nome do Echo, domínio e token vêm da seção Integrações do painel.
    private nonisolated static var aparelho: String { Integracoes.texto("alexa.aparelho") }
    private nonisolated static var dominio: String {
        let d = Integracoes.texto("alexa.dominio")
        return d.isEmpty ? "amazon.com.br" : d
    }
    /// Nos EUA o site da Alexa tem outro nome.
    private nonisolated static var host: String { dominio == "amazon.com" ? "pitangui.amazon.com" : "alexa." + dominio }
    private nonisolated static var site: String { "https://" + host }
    private static var echo: [String: Any]?
    private static var echoDe = ""

    nonisolated static var configurado: Bool {
        !aparelho.isEmpty && !Integracoes.texto("alexa.token").isEmpty
            && FileManager.default.fileExists(atPath: script.path)
    }

    // MARK: Volume

    private static func lerVolume() async -> Float? {
        // A saída traz um "volume": null antes do volume de verdade.
        let resposta = await rodarScript(["-d", aparelho, "-q"])
        return resposta?.matches(of: #/"volume": (\d+)/#).last.flatMap { Float($0.1) }.map { $0 / 100 }
    }

    /// Série, tipo e dono do Echo, que a API pede em todo comando.
    private static func dadosDoEcho() async -> [String: Any]? {
        if let echo, echoDe == aparelho { return echo }
        guard let resposta = await chamar("GET", "/api/devices-v2/device?cached=true"),
              let lista = resposta["devices"] as? [[String: Any]],
              let d = lista.first(where: { $0["accountName"] as? String == aparelho }) else { return nil }
        echo = ["deviceSerialNumber": d["serialNumber"] ?? "", "deviceType": d["deviceType"] ?? "",
                "customerId": d["deviceOwnerCustomerId"] ?? "", "locale": Locale.current.identifier(.bcp47)]
        echoDe = aparelho
        return echo
    }

    /// Chama a Amazon direto: pelo script, cada comando ainda confere login e lista de aparelhos.
    private static func gravarVolume(_ alvo: Int) async -> Bool {
        guard var carga = await dadosDoEcho() else { return false }
        carga["value"] = String(alvo)
        let passo: [String: Any] = ["@type": "com.amazon.alexa.behaviors.model.OpaquePayloadOperationNode",
                                    "type": "Alexa.DeviceControls.Volume", "operationPayload": carga]
        let sequencia: [String: Any] = ["@type": "com.amazon.alexa.behaviors.model.Sequence", "startNode": passo]
        guard let dados = try? JSONSerialization.data(withJSONObject: sequencia) else { return false }
        let pedido = ["behaviorId": "PREVIEW", "sequenceJson": String(decoding: dados, as: UTF8.self), "status": "ENABLED"]
        return await chamar("POST", "/api/behaviors/preview", pedido) != nil
    }

    // MARK: Comandos

    /// Chama a API da Alexa. Com o cookie vencido, o script renova e tenta mais uma vez.
    private nonisolated static func chamar(_ metodo: String, _ caminho: String, _ corpo: [String: Any]? = nil) async -> [String: Any]? {
        if let r = await curl(metodo, caminho, corpo) { return r }
        guard await rodarScript(["-a"]) != nil else { return nil }
        return await curl(metodo, caminho, corpo)
    }

    private nonisolated static func curl(_ metodo: String, _ caminho: String, _ corpo: [String: Any]?) async -> [String: Any]? {
        guard let linhas = try? String(contentsOfFile: cookie, encoding: .utf8),
              let csrf = linhas.split(separator: "\n").map({ $0.split(separator: "\t") }).first(where: { $0.count >= 7 && $0[5] == "csrf" })?[6]
        else { return nil }
        var argumentos = ["-s", "-f", "-m", "15", "-b", cookie, "-X", metodo, site + caminho,
                          "-H", "Accept: application/json", "-H", "User-Agent: Mozilla/5.0",
                          "-H", "Content-Type: application/json", "-H", "csrf: \(csrf)"]
        if let corpo, let dados = try? JSONSerialization.data(withJSONObject: corpo) {
            argumentos += ["-d", String(decoding: dados, as: UTF8.self)]
        }
        let (status, texto) = await executar("/usr/bin/curl", argumentos, ambiente: [:])
        // Alguns comandos dão certo e não devolvem nada.
        if status == 0 && texto.isEmpty { return [:] }
        guard status == 0, let objeto = try? JSONSerialization.jsonObject(with: Data(texto.utf8)) as? [String: Any] else {
            NSLog("[PodControl] alexa: %@ %@ falhou (%d)", metodo, caminho, status)
            return nil
        }
        return objeto
    }

    /// Devolve a saída do alexa-remote-control, ou nil se deu erro.
    private nonisolated static func rodarScript(_ argumentos: [String]) async -> String? {
        let token = Integracoes.texto("alexa.token")
        guard !token.isEmpty else {
            NSLog("[PodControl] alexa: sem token no painel")
            return nil
        }
        let ambiente = ["REFRESH_TOKEN": token, "AMAZON": dominio, "ALEXA": host,
                        "HOME": casa.path, "PATH": "/usr/bin:/bin:/opt/homebrew/bin:/usr/local/bin"]
        let (status, texto) = await executar("/bin/bash", [script.path] + argumentos, ambiente: ambiente)
        guard status == 0, !texto.contains("ERROR") else {
            NSLog("[PodControl] alexa: script falhou (%d) %@", status, String(texto.suffix(200)))
            return nil
        }
        return texto
    }

    /// Roda um programa fora da fila principal.
    private nonisolated static func executar(_ programa: String, _ argumentos: [String], ambiente: [String: String]) async -> (Int32, String) {
        await withCheckedContinuation { fim in
            DispatchQueue.global().async {
                let p = Process()
                let saida = Pipe()
                p.executableURL = URL(fileURLWithPath: programa)
                p.arguments = argumentos
                if !ambiente.isEmpty { p.environment = ambiente }
                p.standardOutput = saida
                p.standardError = saida
                do { try p.run() } catch {
                    NSLog("[PodControl] alexa: %@", error.localizedDescription)
                    return fim.resume(returning: (-1, ""))
                }
                DispatchQueue.global().asyncAfter(deadline: .now() + 20) { if p.isRunning { p.terminate() } }
                let dados = saida.fileHandleForReading.readDataToEndOfFile()
                p.waitUntilExit()
                fim.resume(returning: (p.terminationStatus, String(decoding: dados, as: UTF8.self)))
            }
        }
    }
}
