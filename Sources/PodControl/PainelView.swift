import AppKit
import Combine
import CoreMotion
import SwiftUI
import UniformTypeIdentifiers
import Gestos

struct PainelView: View {
    @ObservedObject var controlador: Controlador
    @ObservedObject var config: Configuracoes
    @ObservedObject var sensor: Sensor
    @State private var aviso: String?
    @State private var avisoMouse: String?
    @State private var acessibilidade = Acessibilidade.liberada
    private let relogio = Timer.publish(every: 2, on: .main, in: .common).autoconnect()

    init(controlador: Controlador) {
        self.controlador = controlador
        config = controlador.config
        sensor = controlador.sensor
    }

    var body: some View {
        Form {
            secaoStatus
            secaoCalibracao
            secaoGestos
            secaoSensibilidade
            secaoIntegracoes
            if config.precisaAcessibilidade && !acessibilidade { secaoAcessibilidade }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 760)
        .onReceive(relogio) { _ in acessibilidade = Acessibilidade.liberada }
    }

    // MARK: Status

    private var corStatus: Color {
        if sensor.recebendo { return config.ativo ? .green : .yellow }
        return sensor.conectado ? .orange : .red
    }

    private var textoStatus: String {
        if sensor.fonte == .objeto {
            if sensor.recebendo { return "Recebendo movimento do objeto" }
            if !sensor.mensagemObjeto.isEmpty { return sensor.mensagemObjeto }
            return sensor.conectado ? "Objeto conectado, esperando dados" : "Esperando o Bluetooth do Mac…"
        }
        if sensor.autorizacao == .denied || sensor.autorizacao == .restricted { return "Sem permissão de movimento" }
        if sensor.recebendo { return "Recebendo movimento" + (sensor.qualFone.isEmpty ? "" : " do \(sensor.qualFone)") }
        if sensor.conectado { return "AirPods conectado, mas sem dados de movimento" }
        return "AirPods com sensor não conectado"
    }

    private var secaoStatus: some View {
        Section {
            HStack {
                Circle().fill(corStatus).frame(width: 10, height: 10)
                Text(textoStatus).font(.headline)
                Spacer()
                Toggle("Ativo", isOn: $config.ativo).toggleStyle(.switch).labelsHidden()
            }
            Picker("Controle", selection: $config.fonte) {
                ForEach(Fonte.allCases) { Text($0.nome).tag($0) }
            }
            .pickerStyle(.segmented)
            if sensor.fonte == .objeto {
                if sensor.mensagemObjeto == "Sem permissão de Bluetooth" {
                    Text("Libere o PodControl em Ajustes do Sistema › Privacidade e Segurança › Bluetooth.")
                        .font(.callout).foregroundStyle(.secondary)
                } else if !sensor.recebendo {
                    Text("Ligue o ESP32 no USB ou na bateria. Ele aparece no Bluetooth como PodControl e conecta sozinho.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } else if sensor.autorizacao == .denied || sensor.autorizacao == .restricted {
                Text("Libere o PodControl em Ajustes do Sistema › Privacidade e Segurança › Movimento e Condicionamento.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            if sensor.fonte == .airpods {
                Toggle("Não deixar o som ir para os AirPods", isOn: $config.manterSomNoMac)
                Toggle("Usar o fone como mouse", isOn: $config.modoMouse)
                if config.modoMouse { blocoMouse }
            }
            Toggle("Controladora do Onda", isOn: $config.modoControladora)
            if config.modoControladora { blocoControladora }
            if sensor.fonte == .airpods && sensor.autorizacao != .denied && sensor.autorizacao != .restricted && !sensor.recebendo {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Os AirPods só mandam movimento quando acham que estão no ouvido. Para usar o fone na mesa, desligue a **Detecção automática de ouvido** nos ajustes dos AirPods.")
                    Button("Abrir ajustes do Bluetooth") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.BluetoothSettings")!)
                    }
                }
                .font(.callout).foregroundStyle(.secondary)
            }
            LabeledContent("Posição", value: sensor.lado?.nome ?? "fora de um lado gravado")
            LabeledContent("Giro") { Medidor(valor: sensor.giro, maximo: 360, unidade: "°/s", simetrico: true) }
            LabeledContent("Agitação") { Medidor(valor: sensor.agitacao, maximo: 2.5, unidade: "g", marca: config.forcaChacoalhada) }
            LabeledContent("Último gesto", value: controlador.ultimoGesto)
        }
    }

    private var blocoMouse: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Aperte em Calibrar com a haste apontada para a tela. Nos 3 segundos seguintes, comece **levantando** a ponta e fique subindo e descendo. Depois, um aperto na haste clica e dois apertos são o clique direito.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                if let falta = controlador.calibrandoMouse {
                    Text("Suba e desça a ponta… \(falta)").monospacedDigit()
                } else {
                    Button(config.hasteMouse == nil ? "Calibrar" : "Calibrar de novo") {
                        avisoMouse = nil
                        controlador.calibrarMouse { ok in
                            if !ok { avisoMouse = "Não deu para calibrar. Faça o movimento maior, subindo e descendo a ponta." }
                        }
                    }
                }
                Spacer()
                Slider(value: $config.velocidadeMouse, in: 0.3...3).frame(width: 150)
            }
            if let avisoMouse { Text(avisoMouse).font(.callout).foregroundStyle(.orange) }
        }
    }

    private var blocoControladora: some View {
        VStack(alignment: .leading, spacing: 8) {
            if sensor.fonte == .airpods {
                Toggle("Um fone em cada deck", isOn: $config.doisFones)
            }
            if sensor.fonte == .airpods && config.doisFones {
                Text("O fone esquerdo comanda o Deck 1 e o direito o Deck 2, cada um com a sua roda. Grave os lados com os dois fones deitados na mesa.")
                    .font(.callout).foregroundStyle(.secondary)
                LabeledContent("Movimento vindo de", value: sensor.fonesAtivos.isEmpty ? "nenhum fone" : sensor.fonesAtivos)
            }
            Text("Ligue a chave **Controladora** na cabine do Onda. Vire para o Lado B para abrir a roda e gire para escolher o controle. Vire para o Lado A e gire para mexer nele.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }

    // MARK: Calibração

    private var secaoCalibracao: some View {
        Section {
            Text("Deite o objeto na mesa de um jeito e grave como lado A. Vire do outro lado e grave como lado B. Se não gravar o B, ele vale como o oposto do A.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                botaoGravar(.a, gravado: config.ladoA != nil)
                botaoGravar(.b, gravado: config.ladoB != nil)
                Spacer()
                if config.ladoA != nil || config.ladoB != nil {
                    Button("Apagar") {
                        config.ladoA = nil; config.ladoB = nil
                        if config.fonte == .airpods { config.ladoADireito = nil; config.ladoBDireito = nil }
                    }
                }
            }
            if let aviso { Text(aviso).font(.callout).foregroundStyle(.orange) }
        } header: { Text("Lados na mesa") }
    }

    private func botaoGravar(_ lado: Lado, gravado: Bool) -> some View {
        Button {
            aviso = controlador.gravar(lado) ? nil : "Sem leitura do sensor. Ele precisa estar mandando movimento para gravar."
        } label: {
            Label("Gravar \(lado.nome)", systemImage: gravado ? "checkmark.circle.fill" : "circle")
        }
    }

    // MARK: Gestos

    private var secaoGestos: some View {
        Section {
            Picker("Girar no lado A", selection: $config.giroA) {
                ForEach(AcaoGiro.allCases) { Text($0.nome).tag($0) }
            }
            Picker("Girar no lado B", selection: $config.giroB) {
                ForEach(AcaoGiro.allCases) { Text($0.nome).tag($0) }
            }
            Picker("Chacoalhar", selection: $config.chacoalhar) {
                ForEach(AcaoGatilho.allCases) { Text($0.nome).tag($0) }
            }
            if config.chacoalhar == .abrirApp {
                HStack {
                    if let app = config.app {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: app.path)).resizable().frame(width: 20, height: 20)
                        Text(app.deletingPathExtension().lastPathComponent)
                    } else {
                        Text("Nenhum app escolhido").foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Escolher…", action: escolherApp)
                }
            }
        } header: { Text("Gestos") } footer: {
            Text("Girar no sentido horário aumenta, anti-horário diminui.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private func escolherApp() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.application]
        p.directoryURL = URL(fileURLWithPath: "/Applications")
        p.prompt = "Escolher"
        if p.runModal() == .OK, let url = p.url { config.app = url }
    }

    // MARK: Sensibilidade

    private var secaoSensibilidade: some View {
        Section("Sensibilidade") {
            LabeledContent("Giro por degrau") {
                HStack {
                    Slider(value: $config.grausPorPasso, in: 5...45, step: 5)
                    Text("\(Int(config.grausPorPasso))°").monospacedDigit().frame(width: 36, alignment: .trailing)
                }
            }
            LabeledContent("Força da chacoalhada") {
                HStack {
                    Slider(value: $config.forcaChacoalhada, in: 0.5...2.0, step: 0.1)
                    Text(String(format: "%.1f g", config.forcaChacoalhada)).monospacedDigit().frame(width: 44, alignment: .trailing)
                }
            }
            Toggle("Inverter sentido do giro", isOn: $config.inverterSentido)
        }
    }

    // MARK: Integrações

    private var secaoIntegracoes: some View {
        Section {
            DisclosureGroup("Home Assistant") {
                TextField("Endereço", text: $config.haEndereco, prompt: Text("http://homeassistant.local:8123"))
                SecureField("Token de longa duração", text: $config.haToken)
                LabeledContent("Luz 1") {
                    HStack {
                        TextField("Nome", text: $config.haNomeLuz1, prompt: Text("Luz 1")).labelsHidden()
                        TextField("Entidade", text: $config.haLuz1, prompt: Text("light.sala")).labelsHidden()
                    }
                }
                LabeledContent("Luz 2") {
                    HStack {
                        TextField("Nome", text: $config.haNomeLuz2, prompt: Text("Luz 2")).labelsHidden()
                        TextField("Entidade", text: $config.haLuz2, prompt: Text("light.quarto")).labelsHidden()
                    }
                }
                Text("O token se cria no Home Assistant em Perfil › Segurança › Tokens de acesso de longa duração.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            DisclosureGroup("Alexa") {
                TextField("Nome do Echo", text: $config.alexaAparelho, prompt: Text("Echo Dot da sala"))
                TextField("Domínio da Amazon", text: $config.alexaDominio, prompt: Text("amazon.com.br"))
                SecureField("Refresh token", text: $config.alexaToken)
                if !FileManager.default.fileExists(atPath: Alexa.script.path) {
                    Text("Falta instalar o alexa-remote-control. O passo a passo está no README.")
                        .font(.callout).foregroundStyle(.orange)
                }
            }
        } header: { Text("Integrações") } footer: {
            Text("Opcional. Só precisa para as ações de luz e volume da Alexa.").font(.caption).foregroundStyle(.secondary)
        }
    }

    private var secaoAcessibilidade: some View {
        Section {
            Text("O modo mouse, rolar, trocar de aba e as teclas de mídia simulam teclado e mouse. Para isso o macOS exige a permissão de Acessibilidade.")
                .font(.callout).foregroundStyle(.secondary)
            Button("Liberar Acessibilidade") { Acessibilidade.pedir() }
        } header: { Text("Permissão necessária") }
    }
}

/// Barra horizontal simples para mostrar um valor ao vivo.
private struct Medidor: View {
    let valor: Double
    let maximo: Double
    let unidade: String
    var simetrico = false
    var marca: Double? = nil

    var body: some View {
        HStack(spacing: 8) {
            GeometryReader { geo in
                let w = geo.size.width
                let frac = min(abs(valor) / maximo, 1)
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    if simetrico {
                        Capsule().fill(Color.accentColor)
                            .frame(width: w / 2 * frac)
                            .offset(x: valor >= 0 ? w / 2 : w / 2 - w / 2 * frac)
                    } else {
                        Capsule().fill(Color.accentColor).frame(width: w * frac)
                    }
                    if let marca {
                        Rectangle().fill(.orange).frame(width: 2).offset(x: w * min(marca / maximo, 1) - 1)
                    }
                }
            }
            .frame(width: 140, height: 6)
            Text(String(format: unidade == "g" ? "%.2f %@" : "%.0f %@", valor, unidade))
                .monospacedDigit().font(.caption).frame(width: 64, alignment: .trailing)
        }
    }
}
