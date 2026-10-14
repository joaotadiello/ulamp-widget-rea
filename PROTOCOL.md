# uLamp (Uascent iLamp) — Protocolo BLE — Relatório de Engenharia Reversa

**Alvo:** uLamp 2.5.8 (bundle `com.uascent.iLamp`, app iOS no Mac, `/Applications/UascentBLELight.app`)
**Produto do usuário:** strip LED TV `88006190` (chip Beken BK3633, anuncia como `BK3633_BLE789`)
**Data:** 2026-10-14 · Método: RE estática (bytecode Lua + disassembly ARM64) + **validação ao vivo completa**

---

## ⭐ RESULTADO PRINCIPAL (validado ao vivo — 100% funcional)

**O controle da lâmpada NÃO exige autenticação nem nuvem.** Escrita direta no GATT:

| Camada | Valor |
|---|---|
| Serviço | `FFB0` (`0000FFB0-0000-1000-8000-00805F9B34FB`) |
| Escrita | `FFB1` (write without response) |
| Notificação | `FFB2` (notify) |

**Formato do pacote:** `0A A5 <TID> <CMD> <ARGS...>` — **sem checksum, sem auth**
- `0A A5`: header little-endian de `0xA50A`
- `TID`: contador de mensagem 0–255 (a lâmpada ecoa o TID de volta)
- A lâmpada **confirma cada comando** ecoando-o na FFB2

### Dicionário de comandos (produto 88006190, do fonte `88006190.lua`)

| CMD | Função | Argumentos | Testado |
|---|---|---|---|
| `01` | **Power** | `<0/1>` | ✅ on/off ao vivo |
| `02` | **Mode** | `<mode>` | ✅ |
| `04` | **PaintColor (RGB)** | `<type=1> <action=1> <count=1> <brilho> <r> <g> <b>` | ✅ vermelho/verde/azul ao vivo |
| `05` | Cena fantasma/DIY | `<sceneId=0> <changeMode> <speed> <bright> <sceneType> <direction> <expansion> <count> <r g b Δt>...` | (fonte) |
| `06` | Música | `<open> <musicMode> <dir> <sens> <count> <r g b>...` | (fonte) |
| `07` | **Lamp beads** | `<n 2B LE> <total 2B LE>` | ✅ (estado reporta 110/150) |
| `09` | **LineStyle** | `1=RGB 2=RBG 3=BRG 4=BGR 5=GRB 6=GBR` | ✅ (atual=3) |
| `0B` | White balance | `<r> <g> <b>` | (fonte) |
| `FF` | **Query estado completo** | – | ✅ dumpa tudo |

### Respostas (FFB2 → parse opCode)
`01`=power, `02`=mode, `04`=paintColor, `05`=cena atual(changeMode/speed/brightness), `06`=**música** `<open> <mode> <dir> <sens> <count> <rgb>...`, `07`=beads, `09`=lineStyle, `0C`=**segmentos** `<id> <val> <?>`, `0D`=?, `0F`=?, `0A`=estado estendido. O echo do comando confirma a aplicação.

### 🔇 O mic da fita NÃO expõe áudio por BLE (validado ao vivo, 2026-10-14)
O microfone do music sync é lido e processado **100% dentro do BK3633** (DSP no firmware
acende os LEDs direto). Provas (`ulamp_micsniff`/`ulamp_advmic`):
1. GATT: com `06 01 …` ativo, 25s de escuta na FFB2 → só o eco do comando (0 pacotes/s de áudio);
2. Beacon `uac088`: em modo música vira `4d43 <musicOn 0/1> <sens>` — estático; 294 frames
   em 16s (8 silêncio + 8 barulho) sem mudar 1 byte;
3. Fonte Lua oficial: parser sem nenhum opcode de áudio/nível.
Logo não existe "onda do mic da fita" para visualizar — o controle possível é `06` (on/off + sens).

### Ferramenta pronta
```bash
./ulampctl on|off|status|color RRGGBB [bri]|white v|beads n tot|style n
# status → {"lineStyle":3,"mode":2,"power":1,"segments":[1,2,3,4,5]}
```

### Cenas predefinidas (ControlScene no fonte, 1–7+)
Cada cena = DIY dinâmica: ex. cena 1 =流水 (fluxo) `changeMode=0x10`, speed=50, 5 cores `#FF7B56 #FF02D4 #00FF15 #FFF60A #00F2FF`, brilho=100. Ver fonte linhas 560-742.

---

## Visão geral da arquitetura (contexto)

O app é um controlador de lâmpadas **Bluetooth Mesh (stack padrão + Telink/Beken)**:

| Camada | Evidência |
|---|---|
| App iOS (ObjC/Swift + RAC) | `UascentBLELight` binário ARM64 (7.5 MB) |
| Lógica do protocolo | **`ua_common.lua`** — bytecode Lua 5.3 com VM customizada (opcodes+campos embaralhados) |
| Transporte | Telink mesh: serviço **FFB0**, característica **FFB1 (write)**, **FFB2 (notify)**; também anuncia `MeshProxyService` (0x1828) |
| Strings nativas | `MeshProxyService`, `Telink Semiconductor Co. Ltd`, `meshnetwork`, `nodeAddress`, `connectNonceAuthBleWithDevice` |
| UUID template | `0000%@-0000-1000-8000-00805F9B34FB` (monta UUID-128 a partir dos 16 bits) |
| ProductIds conhecidos | `D598172E`, `4753414C`, `59CBFE03`, `58B4A0D5`, `9c68915b`, `00A8C41B`, `1F7E2323`, `00632BF2`, `222F3647`, `4F85E982`, `5b99fb76` |

O binário nativo invoca o Lua por `lua_getglobal`: `ControlBleDevice`, `GetBleDeviceStatusBlePackage`, `BleRecieveDataResolv` (parser de notificações), `CreateCountdown`, `DeleteCountdown`. Os demais builders são chamados pelo motor de "painéis BLE" baixados por productId.

## 2. Enquadramento "JX" (camada de aplicação)

```
pacote = 4A 58 <TID> <OP1> <OP2> <FLAGS> <ARGS...> <XOR>
          │  │   │     │     │     │            └─ checksum = XOR de TODOS os bytes anteriores
          │  │   │     │     │     └─ sempre 0x00 nos comandos analisados (reservado/segmento?)
          │  │   │     │     └─ subopcode (0x82 = controle, 0x83/0x84 = variantes)
          │  │   │     └─ opcode do comando
          │  │   └─ transaction ID: contador 0–255, incrementa a cada pacote (wrap via CurrTid)
          │  └─ 'X' (0x58)
          └─ 'J' (0x4A)
```

- **Checksum (verificado):** seed `0x4A`, depois `^= 0x58, ^= TID, ^= OP1, ^= OP2, ^= FLAGS, ^= cada arg`.
- Builders "payload-only" (família `Control*`) retornam `<OP1><OP2><00><args>` + XOR parcial; o lado nativo concatena com o cabeçalho. O resultado no ar é idêntico à fórmula acima.
- Pacotes são construídos em **string hex lowercase** no Lua (`string.format("%02x", ...)`).

## 3. Dicionário de comandos (extraído dos builders Lua)

### Consultas (geram pacote completo com cabeçalho)
| Função | OP1 OP2 | Argumentos | Observação |
|---|---|---|---|
| `GetBleDeviceStatusBlePackage` | `d0 82` | – | pede estado completo |
| `GetDeviceIdBlePackage` | `d0 82` | – | mesmo opcode (resposta distingue) |
| `GetProductIdBlePackage` | `e1 82` | – | |
| `GetTimeStampBlePackage` | `c0 82` | `<ts 4 bytes BE>` | sincroniza relógio do dispositivo |
| `GetTimerListPackage` | `a3 82` | – | lista de agendamentos |
| `DeleteCountdown`/`DeleteTimerTaskPackage` | `a0 82` | `<timerId>` | |
| `RemoveDynamicDiyPackage` | `43 84` | `<dynamicId>` | |
| `RemoveMusicDiyPackage` | `44 84` | `<musicId>` | |
| `RemoveStaticDiyPackage` | `45 84` | `<staticId>` | |
| `OpenBreatheSpeedPackage` | `46 83` | `<state> <value>` | efeito "respiração" |
| `CreateTimertaskPackage` | `a1 82` | `<timerId> <power> <start 4B> <stop 4B> <state> <repeat/circle>` | agendamento completo |
| `ControlBleDevice` | *(dispatch)* | JSON de estado completo | aplica estado inteiro (usado pós-restore) |

### Controles imediatos (payload; nativo adiciona cabeçalho)
| Função | OP1 OP2 | Argumentos | Significado |
|---|---|---|---|
| `ControlPowerState` | `02 82` | `<power 0/1>` | **ligar/desligar** |
| `ControlBright` | `4c 82` | `<bright>` | **brilho** |
| `ControlSpeed` | `60 82` | `<speed>` | velocidade de transição |
| `ControlSaturation` | `21 82` | `<sat>` | saturação |
| `ControlBrightnessEnhancement` | `24 82` | `<val>` | reforço de brilho |
| `ControlSensitivity` | `2a 82` | `<val>` | sensibilidade (modo música) |
| `ControlScene` | `42 82` | `<sceneId>` | **cena predefinida** |
| `ControlSceneClolor` | `32 82` | `<r> <g> <b>` | **cor RGB direta** |
| `ControlColorTemperature` | `64 82` | `<hi> <lo>` (16-bit BE) | **temperatura de cor** |
| `ControlLampBeads` | `f0 82` | `<hi> <lo>` | nº de contas de LED |
| `ControlwhiteBalance` | `27 82` | `<r 2B> <g 2B> <b 2B>` | balanço de branco |
| `ControlLinkageStatuss` | `2d 82` | `<status>` | agrupamento/linkage |
| `ControlDynamic` | `43 82` | `<dynamicId>` | cena dinâmica DIY |
| `ControlMusic` | `44 82` | `<musicId>` | cena musical |
| `ControlStaticWithStaticId` | `45 82` | `<staticId>` | cena estática DIY |
| `DeleteCustomScene` | `13 82` | – | apaga cena custom |
| `ControlCustomScene` | `11 82` | `<mode> <count> <r g b>...` | cena custom (cores via `Convert16HexStrToInt8`) |
| `ControlTimerTask` | `<a0/a1/a2> 82` | `<timerId> <power> <start 4B> <stop 4B>` | countdowns |

Conversores: `Convert2ByteValue(v) = (v>>8, v&0xFF)` (BE); `Convert4ByteValue` idem 4 bytes; `XorValue(arr)` = XOR de todos os bytes (seed `-1` no Lua = 0xFF... equivalente a XOR simples byte a byte aqui).

## 4. Respostas (notificações FFB2 — parser `BleRecieveDataResolv`)

Mesmo enquadramento JX. O parser decodifica `opcode16 = OP1 | (OP2<<8)` e despacha (constantes do bytecode):

| opcode16 | bytes | Campos parseados (nomes no parser) |
|---|---|---|
| `0x8204` | `04 82` | power, brightness, speed, scene, color |
| `0x8212`/`0x8213` | | deleção de cena / countdown |
| `0x8222` `0x8225` `0x822b` `0x822e` | | saturação / enhancement / sensitivity / linkage |
| `0x8234` | | cor de cena |
| `0x8243` `0x8244` `0x8245` | | dynamic / music / static |
| `0x824f` | | **estado completo**: power, brightness, speed, scene, color(`#`), color_temperature, lamp_bead, saturation, brightnessEnhancement, sensitivity, mode, colorsCount, colors[], dynamicId, musicId, staticId, linkageStatus |
| `0x8261` `0x8266` | | timers (timerId, power, startTimeStamp, stopTimeStamp, minute, second) |
| `0x82a3` | | lista de timers |
| `0x82b0` `0x82b1` `0x82b3` | | deviceId / productId / timestamp |
| `0x82c1` | | ack timestamp |
| `0x82e0` `0x82e1` | | eventos mesh |
| `0x82f1` | | segmentCount (pacotes longos segmentados!) |
| `0x8343` `0x8344` `0x8345` | | acks remoção DIY |
| `0xb2d1` | | especial (mesh?) |

Para Alexa `ReportState`: `0x8204` (estado rápido) e `0x824f` (completo) cobrem power/brightness/cor/temperatura.

## 5b. Descobertas de runtime (validação ao vivo, 2026-10-14)

**Dispositivo real:** lâmpada/strip com chip **Beken BK3633**, anuncia-se como `BK3633_BLE789` (conectável, com FFB0) **e** como `uac088` (beacon de estado).

**Mapa GATT confirmado por conexão real:**
| Serviço | Caract. | Props | Comportamento observado |
|---|---|---|---|
| FFB0 | FFB1 | read+writeNR | write JX `4a 58 .. d0 82 00 ..` → **sem resposta** (provável exigência de auth antes) |
| FFB0 | FFB2 | notify | sem notificações sem auth |
| FFB0 | FFB4/FFB5 | write/notify | idem FFB1/FFB2 (OTA na convenção Telink) |
| F000FFC0-0451-4000-B000-000000000000 | FFC1 | write+writeNR+notify | **RESPONDEU**: `7d 08 ec 84 42 42 42 42 0d 00` (parece challenge de auth — bate com `connectNonceAuthBleWithDevice` do app) |
| idem | FFC2 | write+notify | respondeu `00 00` |

**Broadcast de estado por advertisement (empírico, 2 capturas):**
- Ligada: `mfr = 54 56 | 02 | A(3 bytes) | B(3 bytes)` — company ID Uascent 0x5654, tipo 0x02, 6 bytes de estado
  - Estado estável observado com metades idênticas (`433826 433826` = branco quente)
  - Mudanças de brilho/cor alteram 1-2 bytes em tempo real (ex.: `1a2b16`→`1a3116` ao subir brilho)
  - Hipótese: metade A = canal branco/CCT, metade B = canal RGB (a confirmar com mais capturas)
- Desligada: frame distinto `56 54 | 07 | 14×20` (company ID invertido, tipo 0x07, 20× 0x14)
- **Isto permite ler o estado da lâmpada sem conexão** (ótimo para Home Assistant)

**Auth GATT (bloqueio atual):** o app faz challenge-response **assistido pela nuvem**:
`requestBleDeviceNonceWithProductId:mac:version:` → cloud `cloud.uascent-iot.com`/`api-us.marsgate.com` → `queryBleDeviceAndAuthWithProductId:mac:version:nonce:sign:` → BLE. O app tem AES256-CBC/SHA1/`signWithParams:`. Os bytes exatos do handshake não foram capturados ainda.

**Não existe skill Alexa oficial** da uLamp (linha BLE-only; os produtos Matter da Uascent são Wi-Fi, outros SKUs).

## 5c. A descoberta que fechou o jogo: o protocolo por produto é baixado EM FONTE PURO

O app baixa por productId um **arquivo Lua em código-fonte legível** para
`~/Library/Containers/com.uascent.iLamp/Data/Documents/UALuaProtocol/88006190_*/88006190.lua`
(1.504 linhas documentadas em chinês). O `ua_common.lua` embarcado (bytecode) é apenas o
**template genérico** — o protocolo real do produto diferencia-se dele (cabeçalho `0A A5`
vs `4A 58`, opcodes de 1 byte vs `XX 82 00`). Sempre prefira extrair o `.lua` do container.

**Cadeia de auth da nuvem (irrelevante para este produto):** o caminho `bleVersion==4`
(transporte de data-points com frames `[header 2B][ver][cmd][len 2B][data][CRC8]`,
auth via nonce/sign da nuvem `cloud.uascent-iot.com`, chaves HMAC locais
`kyHx6exJ5is3CADTkpBEetJh`/`KB8aaPp3nTbZC6NmpBpMAnn6`) NÃO é usado pela strip 88006190 —
ela aceita comandos diretos no protocolo `0A A5`.

## 5d. Confiança e lacunas (honestidade metodológica)

**Observado (evidência direta do bytecode):** opcodes, formato do cabeçalho, XOR, ordem dos argumentos, nomes de campos das respostas.
**Inferido (alto):** UUIDs FFB0/FFB1/FFB2 como transporte (padrão Telink + strings no binário, mas o vínculo exato serviço→característica não foi traçado no assembly).
**Desconhecido (requer captura runtime):**
1. Se o quadro JX vai cru na FFB1 ou encapsulado em PDU mesh Telink (provável: cru em conexão direta, pois o parser Lua recebe hex direto);
2. Semântica exata do byte FLAGS (`00`);
3. Range de brilho (0–100 vs 0–254) e codificação de `power` (0/1);
4. Offsets exatos dos campos nas respostas (tenho nomes e ordem, não todos os offsets).

## 6. Apêndice: o VM Lua customizado

- Cabeçalho 5.3.0-5.3.2 (5 size-bytes, size_t=4), strings sem NUL real ("`-no.lua`" = no-NUL).
- Instrução: `op=w[0:6] A=w[6:14] C=w[14:22] k_C=w[22] B=w[23:31] k_B=w[31] Bx=w[14:32]`.
- Opcodes remapeados (descobertos por criptoanálise): MOVE=0, LOADK=1, LOADNIL=4, GETTABUP=6, GETTABLE=7, SETTABUP=8, SETTABLE=10, NEWTABLE=11, ADD=13, BXOR=22, CONCAT=29, CALL=36, RETURN=38, FORLOOP=39, FORPREP=40, CLOSURE=44.
- Ferramentas: `luawalk.py` (parser de estrutura), `luapretty.py` (disassembler) — no diretório de trabalho temporário.
