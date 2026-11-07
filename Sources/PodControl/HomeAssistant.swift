import Foundation

/// O que o PodControl controla pelo Home Assistant. A conversa fica na rede local,
/// então dá para mandar vários valores por segundo durante o giro.
/// Endereço, token e luzes vêm da seção Integrações do painel (Configuracoes).
@MainActor
enum HomeAssistant {
    private static var luzes: [String: NivelRemoto] = [:]

    nonisolated static var configurado: Bool {
        !Integracoes.texto("ha.endereco").isEmpty && !Integracoes.texto("ha.token").isEmpty
    }

    /// A luz 1 ou 2 escolhida no painel, ou nil se ainda não foi configurada.
    static func luz(_ numero: Int) -> NivelRemoto? {
        let entidade = Integracoes.texto("ha.luz\(numero)")
        guard configurado, !entidade.isEmpty else { return nil }
        let texto = Integracoes.nomeDaLuz(numero)
        let chave = entidade + "|" + texto
        if let l = luzes[chave] { return l }
        let l = NivelRemoto(simbolo: "lightbulb.fill", texto: texto, origem: "o Home Assistant", intervaloEnvio: 0.2,
                            ler: { await lerLuz(entidade) }, gravar: { await gravarLuz(entidade, $0) })
        luzes[chave] = l
        return l
    }

    private nonisolated static func lerLuz(_ entidade: String) async -> Float? {
        guard let estado = await chamar("GET", "/api/states/\(entidade)") as? [String: Any] else { return nil }
        if estado["state"] as? String == "off" { return 0 } // apagada guarda o brilho antigo
        let atributos = estado["attributes"] as? [String: Any]
        return (atributos?["brightness"] as? NSNumber).map { $0.floatValue / 255 }
    }

    private nonisolated static func gravarLuz(_ entidade: String, _ alvo: Int) async -> Bool {
        // Com brilho acima de zero, a lâmpada apagada acende sozinha.
        let servico = alvo == 0 ? "turn_off" : "turn_on"
        var corpo: [String: Any] = ["entity_id": entidade]
        if alvo > 0 { corpo["brightness_pct"] = alvo }
        return await chamar("POST", "/api/services/light/\(servico)", corpo) != nil
    }

    /// Chama a API REST do HA. Devolve o JSON da resposta, ou nil se deu erro.
    private nonisolated static func chamar(_ metodo: String, _ caminho: String, _ corpo: [String: Any]? = nil) async -> Any? {
        var endereco = Integracoes.texto("ha.endereco")
        if !endereco.contains("://") { endereco = "http://" + endereco }
        guard let base = URL(string: endereco) else {
            NSLog("[PodControl] ha: endereço inválido %@", endereco)
            return nil
        }
        var pedido = URLRequest(url: base.appending(path: caminho), timeoutInterval: 5)
        pedido.httpMethod = metodo
        pedido.setValue("Bearer \(Integracoes.texto("ha.token"))", forHTTPHeaderField: "Authorization")
        if let corpo {
            pedido.setValue("application/json", forHTTPHeaderField: "Content-Type")
            pedido.httpBody = try? JSONSerialization.data(withJSONObject: corpo)
        }
        do {
            let (dados, resposta) = try await URLSession.shared.data(for: pedido)
            let status = (resposta as? HTTPURLResponse)?.statusCode ?? 0
            guard (200..<300).contains(status) else {
                NSLog("[PodControl] ha: %@ %@ falhou (%d)", metodo, caminho, status)
                return nil
            }
            return try JSONSerialization.jsonObject(with: dados)
        } catch {
            NSLog("[PodControl] ha: %@ %@ falhou: %@", metodo, caminho, error.localizedDescription)
            return nil
        }
    }
}

/// Leitura direta dos campos da seção Integrações, que o painel grava no UserDefaults.
enum Integracoes {
    static func texto(_ chave: String) -> String {
        (UserDefaults.standard.string(forKey: chave) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func nomeDaLuz(_ numero: Int) -> String {
        let nome = texto("ha.nomeLuz\(numero)")
        return nome.isEmpty ? "Luz \(numero)" : nome
    }
}
