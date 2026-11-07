// case-podcontrol.scad
// Caixa para o objeto PodControl: ESP32 DevKit V1 (30 pinos) + GY-521 em cima da lata
// + bateria embaixo da placa + TP4056 micro USB em pé na ponta + chave deslizante na lateral.
// Corpo tipo "seixo": cantos verticais e arestas de cima/baixo arredondados; a tampa segue a curva.
// Unidades em mm. Valores marcados (est.) foram estimados pelas fotos de 01/11/2026,
// usando a placa do ESP32 (pinos a 2,54 mm) como escala. Ajuste e renderize de novo.
//
// Renderizar:  openscad -D 'parte="base"'  -o base.stl  case-podcontrol.scad
//              openscad -D 'parte="tampa"' -o tampa.stl case-podcontrol.scad

parte = "ambas";          // "base", "tampa", "ambas" (lado a lado) ou "fechada" (montada, só para ver)

// ---------- peças ----------
placa_c   = 51.8;         // ESP32 DevKit V1 30 pinos: comprimento
placa_l   = 28.2;         // largura
placa_e   = 1.6;          // espessura
furo_d    = 3.0;          // furos de fixação da placa
furo_x    = 2.6;          // (est.) centro do furo até a borda curta
furo_y    = 2.6;          // (est.) centro do furo até a borda longa
pinos_h   = 11;           // (est.) quanto os pinos + solda descem abaixo da placa
cima_h    = 11;           // (est.) altura ocupada acima da placa (GY-521 na lata + fios)
usb_furo  = [8, 3.4];     // furo no formato do plugue micro USB (largura, altura): só a ponta metálica passa (6,85 x 1,8 mm)
usb_chanf = 1.0;          // chanfro dos cantos do lado estreito do micro USB
usb_canto = 0.4;          // arredondamento dos cantos do furo
usb_bolso = [11.5, 6.5];  // rebaixo por fora, em volta do furo, para o corpo plástico do cabo encostar (largura, espessura)
usb_resto = 1.0;          // parede que sobra no fundo do rebaixo
usb_esp_z = 1.35;         // centro do conector do ESP32 acima do topo da placa (conector de 2,7 mm)

tp_e      = 5;            // (est.) TP4056 em pé: placa + componentes + solda
tp_l      = 19;           // (est.) TP4056 largura (horizontal); pela proporção na foto é a placa de 25 x 19 mm, confira
tp_a      = 25;           // (est.) TP4056 altura (em pé, USB para cima); é ela que manda na altura da caixa

chave     = [3.7, 8.6];   // corpo da chave SS12D00 visto de frente: largura (y) e altura (z); o furo é retangular igual a ele
chave_fol = 0.3;          // folga do furo em cada lado
chave_dy  = 2.5;          // (est.) centro do furo à direita da borda do TP4056
chave_z   = 8;            // (est.) centro do furo acima do piso interno

furo_en   = false;        // furo na tampa para apertar o botão EN com uma caneta (desligado: a chave reinicia)
en_xy     = [4, 5];       // (est.) botão EN: distância da ponta do USB e da borda direita
en_d      = 4.5;          // diâmetro do furo do EN

bateria   = [40, 25, 6];  // (est.) 650 mAh tipo 602540; fica embaixo da placa, só conferência

// ---------- caixa ----------
estilo      = "diamante"; // "diamante": facetas a 45° em cima e embaixo; "seixo": tudo arredondado
chanfro     = 4;          // diamante: largura e altura das facetas (45°)
parede      = 2;
piso        = 2;
tampa_e     = (estilo == "diamante") ? chanfro : 2;   // no diamante a tampa é a faceta de cima inteira
folga       = 0.5;        // folga entre peças e paredes
folga_tampa = 0.2;        // folga do lábio da tampa
labio_a     = 2;          // altura do lábio da tampa
labio_e     = 1.2;        // espessura do lábio
raio_v      = 6;          // raio dos cantos verticais (vista de cima)
raio_h      = 3;          // raio das arestas de cima e de baixo
fios_lado   = 4;          // espaço extra à direita (+y) para os fios do GY-521
usb_sai     = 1;          // quanto o micro USB do ESP32 passa da borda da placa
poste_d     = 4;          // diâmetro dos postes sob os furos da placa
pino_h      = 2;          // altura do pino que entra no furo da placa
unha        = [14, 1.5];  // entalhe para a unha na borda da tampa (largura, profundidade)
colmeia      = true;      // grade de hexágonos vazados na tampa, em cima da placa (mostra os LEDs)
colmeia_furo = 5;         // largura de cada hexágono, entre lados paralelos
colmeia_par  = 1.2;       // parede entre hexágonos
colmeia_marg = 6;         // margem até a borda externa da tampa (fica fora da curva)
colmeia_fim  = 3;         // a grade para a esta distância do TP4056
colmeia_diag = [28, 46];  // corte diagonal: x onde a grade termina na borda de cima (y maior) e na de baixo; só entram hexágonos inteiros
led_esp      = [20.3, 18.3];  // (est.) LED do ESP32: distância da ponta do USB e da borda esquerda da placa; um hexágono fica centrado nele
led_gy       = [27.7, 16.8];  // (est.) LED do GY-521, mesmas referências; só conferido no echo
colmeia_tp   = true;      // furos hexagonais na parede da ponta, colados à esquerda da chave (LEDs de carga do TP4056)
colmeia_tp_n = 2;         // quantos furos, empilhados na vertical
colmeia_tp_dy = 0;        // afastar os furos da chave (mm a mais para a esquerda)
colmeia_tp_dz = 0;        // subir (+) ou descer (-) os furos em relação ao centro da chave
$fn = 48;

// ---------- derivados ----------
ch_i   = (estilo == "diamante") ? max(chanfro - parede, 0) : 0;   // faceta de baixo da cavidade
int_c  = usb_sai + placa_c + tp_e + 2*folga + ch_i;   // + ch_i: o chão afunila na ponta, o TP4056 precisa de chão reto
int_l  = placa_l + fios_lado + 2*folga;
int_a  = max(pinos_h + placa_e + cima_h, tp_a) + folga;
ext_c  = int_c + 2*parede;
ext_l  = int_l + 2*parede;
base_a = piso + int_a;            // altura da base = plano de corte da tampa
ext_a  = base_a + tampa_e;        // altura total fechada
rv_i   = max(raio_v - parede, 1.5);   // raios da cavidade
rh_i   = max(raio_h - parede, 0.8);

x_b = parede + folga + usb_sai;   // começo da placa (ponta do USB do ESP32)
y_b = parede + folga;             // borda esquerda da placa
z_b = piso + pinos_h;             // face de baixo da placa
x_tp = x_b + placa_c + folga;     // face do TP4056 encostada na ponta da placa
y_mid = y_b + placa_l/2;

echo(str("Externo: ", ext_c, " x ", ext_l, " x ", ext_a, " mm"));
assert(bateria[2] <= pinos_h, "bateria mais grossa que o vão sob a placa");
assert(raio_h <= raio_v, "raio_h precisa ser menor ou igual a raio_v");

// Caixa com cantos verticais de raio rv e arestas horizontais de raio rh,
// ocupando exatamente [0..c] x [0..l] x [0..a].
module seixo(c, l, a, rv, rh) {
    minkowski() {
        translate([0, 0, rh])
            hull() for (x = [rv, c - rv], y = [rv, l - rv])
                translate([x, y, 0]) cylinder(r = rv - rh, h = a - 2*rh);
        sphere(r = rh);
    }
}

// Furo 2D no formato do micro USB: lado largo em +y, lado estreito chanfrado em -y, centrado na origem.
module microusb_2d() {
    l = usb_furo[0]; a = usb_furo[1]; c = usb_chanf; r = usb_canto;
    offset(r = r) offset(delta = -r)
        polygon([[-l/2, a/2], [l/2, a/2], [l/2, -a/2 + c], [l/2 - c, -a/2], [-l/2 + c, -a/2], [-l/2, -a/2 + c]]);
}

// Colmeia 2D: hexágonos inteiros, de ponta para cima, em fileiras alternadas, centrados no retângulo
// [x0..x1] x [y0..y1]. Com diag = [xd_cima, xd_baixo], só entram os hexágonos inteiramente à esquerda
// da diagonal que vai de (xd_baixo, y0) a (xd_cima, y1).
module colmeia_rect_2d(x0, y0, x1, y1, diag = undef, ancora = undef) {
    p  = colmeia_furo + colmeia_par;      // passo entre centros na fileira
    dy = p * sqrt(3) / 2;                 // distância entre fileiras
    R  = colmeia_furo / sqrt(3);          // raio até o vértice
    a  = (ancora == undef) ? [(x0 + x1)/2, (y0 + y1)/2] : ancora;   // um hexágono fica centrado aqui
    ni = ceil((x1 - x0) / p) + 2;
    nj = ceil((y1 - y0) / dy) + 2;
    for (j = [-nj : nj], i = [-ni : ni]) {
        cx = a[0] + i*p + (abs(j) % 2) * p/2;
        cy = a[1] + j*dy;
        // menor sobra (positiva = dentro) entre os 6 vértices e as bordas do retângulo e a diagonal
        sobra = min([for (k = [0 : 5]) let(vx = cx + R * cos(30 + 60*k), vy = cy + R * sin(30 + 60*k))
                     min(vx - x0, x1 - vx, vy - y0, y1 - vy,
                         (diag == undef) ? 1 : (diag[1] + (diag[0] - diag[1]) * (vy - y0) / (y1 - y0)) - vx)]);
        if (sobra >= 0) translate([cx, cy]) rotate(30) circle(r = R, $fn = 6);
    }
}

// Colmeia da tampa: em cima da placa, do lado do USB do ESP32, até o corte diagonal.
module colmeia_2d() {
    colmeia_rect_2d(colmeia_marg, colmeia_marg, x_tp - colmeia_fim, ext_l - colmeia_marg, colmeia_diag, led_xy(led_esp));
}

// Posição na caixa de um ponto dado em relação à placa (da ponta do USB, da borda esquerda).
function led_xy(l) = [x_b + l[0], y_b + l[1]];

// Distância do LED do GY-521 ao centro do hexágono mais próximo (só para conferir no echo).
function dist_hex(pt) = let(p = colmeia_furo + colmeia_par, dy = p*sqrt(3)/2, a = led_xy(led_esp), d = pt - a,
    j = round(d[1] / dy), i = round((d[0] - (abs(j) % 2) * p/2) / p))
    norm(d - [i*p + (abs(j) % 2) * p/2, j*dy]);
echo(str("LED do GY-521 fica a ", dist_hex(led_xy(led_gy)), " mm do centro do hexágono mais próximo (dentro se < ", colmeia_furo/2, ")"));

// Furos hexagonais da parede da ponta, em pilha vertical logo à esquerda da chave, na altura dela
// (coordenadas: x = y da caixa, y = z da caixa). Lados retos em cima e embaixo, para a parede entre eles ser uniforme.
module colmeia_tp_2d() {
    R  = colmeia_furo / sqrt(3);
    yc = y_mid + tp_l/2 + chave_dy - (chave[0]/2 + chave_fol) - colmeia_par - colmeia_furo/2 - colmeia_tp_dy;
    zc = piso + chave_z + colmeia_tp_dz;
    passo = colmeia_furo + colmeia_par;
    for (k = [0 : colmeia_tp_n - 1])
        translate([yc, zc + (k - (colmeia_tp_n - 1)/2) * passo]) circle(r = R, $fn = 6);
}

// Retângulo com cantos arredondados, de [0,0] a [c,l].
module rrect(c, l, r) { offset(r = r) offset(delta = -r) square([c, l]); }

// Caixa facetada: faceta de baixo (ch_baixo) e de cima (ch_cima) a 45°, cantos verticais de raio rv,
// ocupando exatamente [0..c] x [0..l] x [0..a].
module facetado(c, l, a, ch_baixo, ch_cima, rv) {
    hull() {
        linear_extrude(0.01) offset(delta = -ch_baixo) rrect(c, l, rv);
        translate([0, 0, ch_baixo]) linear_extrude(max(a - ch_baixo - ch_cima, 0.01)) rrect(c, l, rv);
        translate([0, 0, a - 0.01]) linear_extrude(0.01) offset(delta = -ch_cima) rrect(c, l, rv);
    }
}

// Contorno 2D da cavidade (para o lábio da tampa).
module cavidade_2d(enc = 0) {
    offset(r = rv_i - enc) offset(delta = -rv_i)
        translate([parede, parede]) square([int_c, int_l]);
}

module corpo(extra = 0) {   // extra: a cavidade passa do plano da tampa (evita faces coplanares na base)
    difference() {
        if (estilo == "diamante") {
            facetado(ext_c, ext_l, ext_a, chanfro, chanfro, raio_v);
        } else {
            seixo(ext_c, ext_l, ext_a, raio_v, raio_h);
        }
        // cavidade: no diamante o teto é reto (a tampa é maciça) e só o chão afunila
        if (estilo == "diamante") {
            translate([parede, parede, piso]) facetado(int_c, int_l, int_a + extra, ch_i, 0, rv_i);
        } else {
            translate([parede, parede, piso]) seixo(int_c, int_l, int_a + extra, rv_i, rh_i);
        }
        // micro USB do ESP32 (parede x = 0): lado largo para cima, com rebaixo por fora para o corpo do cabo
        translate([-1, y_mid, z_b + placa_e + usb_esp_z]) rotate([90, 0, 90]) {
            linear_extrude(parede + 2) microusb_2d();
            linear_extrude(1 + parede - usb_resto) translate([-usb_bolso[0]/2, -usb_bolso[1]/2]) rrect(usb_bolso[0], usb_bolso[1], 1.5);
        }
        // chave (parede da ponta do TP4056, x = ext_c): furo retangular do tamanho do corpo dela, em pé
        translate([ext_c - parede - 1, y_mid + tp_l/2 + chave_dy - chave[0]/2 - chave_fol, piso + chave_z - chave[1]/2 - chave_fol])
            cube([parede + 2, chave[0] + 2*chave_fol, chave[1] + 2*chave_fol]);
        // micro USB do TP4056, que aponta para cima: lado estreito encostado na placa do TP4056 (-x),
        // com rebaixo na tampa para o corpo do cabo
        translate([x_tp + tp_e/2, y_mid, base_a - labio_a - 1])
            rotate([0, 0, -90]) linear_extrude(labio_a + tampa_e + 2) microusb_2d();
        translate([x_tp + tp_e/2, y_mid, ext_a - (tampa_e - usb_resto)])
            rotate([0, 0, -90]) linear_extrude(tampa_e + 1) translate([-usb_bolso[0]/2, -usb_bolso[1]/2]) rrect(usb_bolso[0], usb_bolso[1], 1.5);
        // colmeia na parede da ponta, em frente aos LEDs do TP4056
        if (colmeia_tp)
            translate([ext_c - parede - 1, 0, 0]) rotate([90, 0, 90]) linear_extrude(parede + 2) colmeia_tp_2d();
        // acesso ao botão EN com uma caneta (opcional)
        if (furo_en)
            translate([x_b + en_xy[0], y_b + placa_l - en_xy[1], base_a - 1]) cylinder(d = en_d, h = tampa_e + 2);
        // entalhe para a unha, na borda da tampa (parede direita)
        translate([ext_c/2 - unha[0]/2, ext_l - unha[1], base_a - 0.01]) cube([unha[0], unha[1] + 1, tampa_e + 1]);
    }
}

module base() {
    intersection() { corpo(1); cube([ext_c, ext_l, base_a]); }
    // postes sob os furos da placa
    for (x = [x_b + furo_x, x_b + placa_c - furo_x], y = [y_b + furo_y, y_b + placa_l - furo_y])
        translate([x, y, piso - 0.01]) {
            cylinder(d = poste_d, h = z_b - piso + 0.01, $fn = 32);
            cylinder(d = furo_d - 0.3, h = z_b - piso + pino_h, $fn = 32);
        }
    // calço que segura o TP4056 em pé (dois trilhos finos)
    for (y = [y_mid - tp_l/2 - 1.2, y_mid + tp_l/2])
        translate([x_tp - 0.3, y, piso]) cube([tp_e + 0.6, 1.2, 6]);
}

// Tampa na posição montada: fatia de cima do corpo mais o lábio que entra na cavidade.
module tampa_montada() {
    difference() {
        union() {
            intersection() { corpo(); translate([0, 0, base_a]) cube([ext_c, ext_l, tampa_e + 1]); }
            translate([0, 0, base_a - labio_a])
                linear_extrude(labio_a + 0.01)
                    difference() { cavidade_2d(folga_tampa); cavidade_2d(folga_tampa + labio_e); }
        }
        // repete o furo do TP4056, que atravessa o lábio
        translate([x_tp + tp_e/2, y_mid, base_a - labio_a - 1])
            rotate([0, 0, -90]) linear_extrude(labio_a + tampa_e + 2) microusb_2d();
        // colmeia vazada em cima da placa
        if (colmeia) translate([0, 0, base_a - 1]) linear_extrude(tampa_e + 2) colmeia_2d();
    }
}

// Tampa para imprimir: virada, com a face de corte apoiada na mesa (x e y iguais aos da base).
module tampa() {
    translate([0, 0, base_a + tampa_e]) mirror([0, 0, 1]) tampa_montada();
}

if (parte == "base" || parte == "ambas") base();
if (parte == "tampa") tampa();
if (parte == "ambas") translate([0, ext_l + 8, 0]) tampa();
if (parte == "fechada") { base(); tampa_montada(); }
if (parte == "leds") {   // caixa fechada com os dois LEDs marcados em vermelho (só no preview, F5)
    base(); tampa_montada();
    for (l = [led_esp, led_gy]) color("red") translate([led_xy(l)[0], led_xy(l)[1], 0]) cylinder(d = 1.6, h = ext_a + 1, $fn = 16);
}
