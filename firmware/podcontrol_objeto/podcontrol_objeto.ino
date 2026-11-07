// PodControl: objeto de mesa. Lê o MPU6050 e manda as leituras para o Mac por Bluetooth (BLE).
// Ligações: VCC->3V3, GND->GND, SCL->22, SDA->21.
// O Mac faz toda a interpretação dos gestos; aqui só medimos e transmitimos.
#include <Wire.h>
#include <BLEDevice.h>
#include <BLEServer.h>
#include <BLE2902.h>
#include <esp_system.h>
#include <Preferences.h>

// Os mesmos UUIDs ficam no app do Mac (FonteObjeto.swift).
#define UUID_SERVICO "7a1e0001-5c3b-4f0e-9a51-0d0c0b0a0901"
#define UUID_LEITURA "7a1e0002-5c3b-4f0e-9a51-0d0c0b0a0901"

const uint8_t SDA_PIN = 21, SCL_PIN = 22, MPU = 0x68;
const uint32_t PERIODO_US = 20000; // 50 leituras por segundo
// Para poupar bateria a placa dorme, e só acorda pelo botão EN ou desligando e ligando.
const uint32_t DORMIR_SEM_MAC_MS = 3 * 60 * 1000;  // ninguém conectou
const uint32_t DORMIR_PARADO_MS = 10 * 60 * 1000;  // conectado, mas ninguém mexeu

BLECharacteristic *leitura = nullptr;
volatile bool conectado = false;

// Pacote de 16 bytes, little-endian. Escalas: acel 4096 por g (+-8 g), giro 32.8 por grau/s (+-1000).
struct __attribute__((packed)) Pacote {
  uint32_t tempo_us;
  int16_t ax, ay, az, gx, gy, gz;
};

class Conexao : public BLEServerCallbacks {
  void onConnect(BLEServer *s, esp_ble_gatts_cb_param_t *param) override {
    conectado = true;
    Serial.println("Mac conectou");
    // Pede ao Mac um ritmo fixo de 15-30 ms (unidades de 1,25 ms; limites da Apple), sem pular
    // intervalos, e 4 s até dar a conexão por perdida. Sem isso o Mac pode usar um ritmo lento
    // demais para 50 leituras/s e a fila de envio transborda.
    s->updateConnParams(param->connect.remote_bda, 12, 24, 0, 400);
  }
  void onDisconnect(BLEServer *s) override {
    conectado = false;
    Serial.println("Mac desconectou, anunciando de novo");
    BLEDevice::startAdvertising();
  }
};

void escrever(uint8_t reg, uint8_t v) {
  Wire.beginTransmission(MPU); Wire.write(reg); Wire.write(v); Wire.endTransmission();
}

bool lerSensor(Pacote &p) {
  Wire.beginTransmission(MPU);
  Wire.write(0x3B);
  if (Wire.endTransmission(false) != 0) return false;
  if (Wire.requestFrom(MPU, (uint8_t)14) != 14) return false;
  uint8_t b[14];
  for (int i = 0; i < 14; i++) b[i] = Wire.read();
  auto v = [&](int i) { return (int16_t)((b[i] << 8) | b[i + 1]); };
  p.ax = v(0); p.ay = v(2); p.az = v(4);
  p.gx = v(8); p.gy = v(10); p.gz = v(12);
  return true;
}

// Acorda e configura o sensor. Se ele perder energia por um instante, volta dormindo
// e passa a ler zeros; por isso o loop chama isto de novo quando percebe.
void configurarSensor() {
  escrever(0x6B, 0x01); // acorda, relógio do giroscópio
  escrever(0x1A, 0x03); // filtro passa-baixa ~44 Hz
  escrever(0x1B, 0x10); // giro +-1000 graus/s
  escrever(0x1C, 0x10); // acel +-8 g
}

void iniciarBarramento() {
  Wire.begin(SDA_PIN, SCL_PIN);
  Wire.setClock(400000);
  Wire.setTimeOut(10); // ms; um fio falhando não pode prender o programa
}

const char *motivoReinicio() {
  switch (esp_reset_reason()) {
    case ESP_RST_POWERON: return "ligou";
    case ESP_RST_BROWNOUT: return "queda de tensao (brownout)";
    case ESP_RST_TASK_WDT: case ESP_RST_INT_WDT: case ESP_RST_WDT: return "travou e o vigia reiniciou";
    case ESP_RST_PANIC: return "erro no programa (panic)";
    case ESP_RST_SW: return "reinicio pelo programa";
    case ESP_RST_EXT: return "botao EN";
    default: return "outro";
  }
}

// Sono profundo: o chip para quase tudo. O LED e o regulador da placa continuam gastando um pouco.
void dormir(const char *motivo) {
  Serial.printf("Dormindo (%s). Aperte EN para acordar.\n", motivo);
  escrever(0x6B, 0x40); // sensor também dorme
  Serial.flush();
  esp_deep_sleep_start(); // sem fonte de despertar: só o EN ou a energia acordam
}

// Mexeu se o giro passou de ~15 graus/s ou a aceleração mudou mais de ~0,1 g desde a última vez.
bool mexeu(const Pacote &p) {
  static Pacote ref = p;
  const int GIRO = 500, ACEL = 400;
  bool m = abs(p.gx) > GIRO || abs(p.gy) > GIRO || abs(p.gz) > GIRO ||
           abs(p.ax - ref.ax) > ACEL || abs(p.ay - ref.ay) > ACEL || abs(p.az - ref.az) > ACEL;
  if (m) ref = p;
  return m;
}

void setup() {
  setCpuFrequencyMhz(80); // metade do normal; sobra folga para 50 leituras/s e gasta menos
  Serial.begin(115200);
  Serial.printf("\nPodControl iniciando. Motivo do ultimo reinicio: %s\n", motivoReinicio());
  // Diagnóstico da bateria: conta partidas e quedas de tensão na memória, que sobrevive sem energia.
  Preferences diag;
  diag.begin("diag");
  uint32_t partidas = diag.getUInt("partidas") + 1, quedas = diag.getUInt("quedas");
  if (esp_reset_reason() == ESP_RST_BROWNOUT) quedas++;
  diag.putUInt("partidas", partidas);
  diag.putUInt("quedas", quedas);
  diag.end();
  Serial.printf("Diagnostico: %u partidas, %u quedas de tensao\n", partidas, quedas);
  iniciarBarramento();
  configurarSensor();

  BLEDevice::init("PodControl");
  BLEServer *servidor = BLEDevice::createServer();
  servidor->setCallbacks(new Conexao());
  BLEService *servico = servidor->createService(UUID_SERVICO);
  leitura = servico->createCharacteristic(UUID_LEITURA, BLECharacteristic::PROPERTY_NOTIFY | BLECharacteristic::PROPERTY_READ);
  leitura->addDescriptor(new BLE2902());
  servico->start();
  BLEAdvertising *anuncio = BLEDevice::getAdvertising();
  anuncio->addServiceUUID(UUID_SERVICO);
  anuncio->setScanResponse(true);
  anuncio->setMinInterval(0x80); // anuncia a cada 80-160 ms (unidades de 0,625 ms), menos que o padrão
  anuncio->setMaxInterval(0x100);
  BLEDevice::startAdvertising();
  enableLoopWDT(); // se o loop parar por mais de 5 s, a placa reinicia sozinha
  Serial.printf("PodControl pronto, endereco BLE %s, esperando o Mac\n", BLEDevice::getAddress().toString().c_str());
}

void loop() {
  static uint32_t proximo = micros();
  static uint32_t ultimoLog = 0;
  if ((int32_t)(micros() - proximo) < 0) return;
  proximo += PERIODO_US;

  Pacote p;
  p.tempo_us = micros();
  static int falhas = 0;
  if (!lerSensor(p)) {
    Serial.println("ERRO: sensor não respondeu, confira os fios");
    if (++falhas >= 5) { // barramento pode ter ficado preso: recomeça do zero
      Wire.end();
      iniciarBarramento();
      falhas = 0;
    }
    configurarSensor();
    delay(50);
    return;
  }
  falhas = 0;
  // Aceleração zerada nos três eixos é impossível (a gravidade sempre aparece): sensor dormindo.
  if (p.ax == 0 && p.ay == 0 && p.az == 0) {
    Serial.println("Sensor reiniciou sozinho (queda de energia?), acordando de novo");
    configurarSensor();
    delay(50);
    return;
  }
  static uint32_t ultimoMac = millis(), ultimoMovimento = millis();
  if (conectado) ultimoMac = millis();
  if (mexeu(p)) ultimoMovimento = millis();
  if (millis() - ultimoMac > DORMIR_SEM_MAC_MS) dormir("sem o Mac");
  if (millis() - ultimoMovimento > DORMIR_PARADO_MS) dormir("parado");

  if (conectado) {
    leitura->setValue((uint8_t *)&p, sizeof(p));
    leitura->notify();
  }
  if (millis() - ultimoLog > 1000) {
    ultimoLog = millis();
    Serial.printf("%s | acel %d %d %d | giro %d %d %d\n", conectado ? "conectado" : "esperando", p.ax, p.ay, p.az, p.gx, p.gy, p.gz);
  }
}
