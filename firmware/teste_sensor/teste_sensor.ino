// Teste de ligação: procura o MPU6050 no I2C (SDA=21, SCL=22) e imprime as leituras.
#include <Wire.h>

const uint8_t SDA_PIN = 21, SCL_PIN = 22;
uint8_t endereco = 0;

bool lerRegs(uint8_t reg, uint8_t *buf, uint8_t n) {
  Wire.beginTransmission(endereco);
  Wire.write(reg);
  if (Wire.endTransmission(false) != 0) return false;
  if (Wire.requestFrom(endereco, n) != n) return false;
  for (uint8_t i = 0; i < n; i++) buf[i] = Wire.read();
  return true;
}

void escrever(uint8_t reg, uint8_t v) {
  Wire.beginTransmission(endereco);
  Wire.write(reg); Wire.write(v);
  Wire.endTransmission();
}

void setup() {
  Serial.begin(115200);
  delay(500);
  Wire.begin(SDA_PIN, SCL_PIN);
  Serial.println("\n== teste do sensor ==");
  for (uint8_t a = 1; a < 127; a++) {
    Wire.beginTransmission(a);
    if (Wire.endTransmission() == 0) {
      Serial.printf("I2C: achei dispositivo em 0x%02X\n", a);
      if (a == 0x68 || a == 0x69) endereco = a;
    }
  }
  if (!endereco) { Serial.println("ERRO: nenhum MPU6050 em 0x68/0x69. Confira os fios."); return; }
  uint8_t who = 0;
  lerRegs(0x75, &who, 1);
  Serial.printf("WHO_AM_I = 0x%02X\n", who);
  escrever(0x6B, 0x00); // acorda o sensor
  escrever(0x1B, 0x08); // giro +-500 graus/s
  escrever(0x1C, 0x00); // acel +-2 g
  delay(100);
}

void loop() {
  if (!endereco) { delay(2000); setup(); return; }
  uint8_t b[14];
  if (!lerRegs(0x3B, b, 14)) { Serial.println("ERRO: leitura falhou"); delay(500); return; }
  auto v = [&](int i) { return (int16_t)((b[i] << 8) | b[i + 1]); };
  float ax = v(0) / 16384.0, ay = v(2) / 16384.0, az = v(4) / 16384.0;
  float gx = v(8) / 65.5, gy = v(10) / 65.5, gz = v(12) / 65.5;
  Serial.printf("acel g: %6.2f %6.2f %6.2f | giro graus/s: %7.1f %7.1f %7.1f\n", ax, ay, az, gx, gy, gz);
  delay(100);
}
