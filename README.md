# uLamp → Alexa — PROJETO COMPLETO ✅

**Status: protocolo 100% reversado e validado ao vivo. Controle direto por BLE sem app, sem nuvem, sem auth.**

## Comece por aqui

```bash
# 1. teste (lâmpada por perto)
./ulampctl status                    # {"lineStyle":3,"mode":2,"power":1,...}
./ulampctl off && sleep 1 && ./ulampctl on
./ulampctl color ff0000              # vermelho!
./ulampctl color 0066ff 30           # azul com brilho 30

# 2. Home Assistant
#    copie homeassistant/configuration_ulamp.yaml para /config/configuration.yaml
#    ajuste caminhos se necessário → Reload Template Entities

# 3. Alexa
#    Home Assistant Cloud (Nabu Casa) → tudo automático,
#    ou skill Haaska → entidade light.ulamp_strip
#    "Alexa, liga a Fita uLamp" 🔊
```

## Como funciona (1 parágrafo)

A strip (produto Uascent 88006190, chip Beken) aceita comandos GATT diretos no serviço
`FFB0` (write `FFB1`, notify `FFB2`) com o enquadramento `0A A5 <TID> <CMD> <ARGS>`
— sem checksum e sem autenticação (o caminho de auth por nuvem existe no app, mas só
para produtos "bleVersion 4" com protocolo de data-points). A lâmpada ecoa cada comando
na FFB2 como confirmação e responde ao query `FF` com o estado completo.

## Arquivos

| Arquivo | O que é |
|---|---|
| **`ulampctl`** / `.swift` | Cliente final (CLI + saída JSON p/ HA) |
| `homeassistant/configuration_ulamp.yaml` | Integração HA (light template + sensor de estado) |
| **`PROTOCOL.md`** | Documentação completa do protocolo com evidências |
| `ulamp_test`, `ulamp_probe`, `ulamp_sniff` (+`.swift`) | Ferramentas da investigação (probe GATT, sniffer de adv) |
| `ulamp_micsniff`, `ulamp_advmic` (+`.swift`) | Teste do mic da fita: loga FFB2/beacon com modo música ativo |
| `tools/` | Disassemblers do VM Lua customizado + anotador ARM64 |
| `captura/appdata/Documents/UALuaProtocol/*/88006190.lua` | **Fonte Lua oficial do protocolo do produto** (ouro) |
| `disasm.txt`, `objc_dump.txt`, `indirect.txt` | Artefatos de análise do binário |

## 💡 Sobre "capturar a imagem que o dispositivo observa"

**A fita não tem câmera.** Verificado por 4 vias: (1) o GATT dela só tem serviços de controle
(FFB0/FFC0), sem qualquer canal de vídeo; (2) o protocolo Lua oficial do produto não tem nenhum
opcode de imagem; (3) o app usa a câmera do iPhone/Mac apenas para QR code; (4) BLE não tem
banda para vídeo. Os "modos filme/jogo" do app são efeitos pré-programados, e o único sensor
real da fita é o **microfone** (music sync, opcode 06).

**O que fizemos no lugar:** o *Modo Ambiente* do widget captura a tela do Mac
(ScreenCaptureKit), calcula a cor média de 5 regiões e pinta os 5 segmentos da fita em
tempo real (4 fps) — o efeito "ambient lighting" de verdade, melhor que camera-sync
(zero latência, funciona com DRM, sem hardware extra). Descoberta-chave que habilitou
isso: o comando `paintColor` com `count=5` pinta cores diferentes por segmento (validado ao vivo).

## 🎬 Widget (uLamp Widget.app)

- Painel flutuante (arrastável pelo cabeçalho, sempre por cima) + ícone 💡 na barra de menus
- Liga/desliga, brilho, 10 cores rápidas, seletor custom, cor aleatória
- **Modo Ambiente**: sincroniza com a imagem da tela do Mac (amostra as bordas: esquerda,
  topo-E, topo-D, direita, base) e pinta as 5 seções da fita com o mapeamento pré-ajustado
  do enrolamento anti-horário (seções: 1=Topo-E 2=Esq 3=Base 4=Dir 5=Topo-D);
  se as laterais ficarem trocadas: menu 💡 → "⇄ Inverter esquerda↔direita"
- **Modo Música**: liga/desliga o mic da própria fita (opcode 06) com controle de
  sensibilidade — a análise de áudio é feita toda no chip Beken; o BLE não expõe a onda
  (verificado: sem streaming em FFB2 e beacon `4d43 <on> <sens>` estático)
- Permissão de gravação de tela com preflight (pede 1x, espera e auto-reinicia ao aprovar)
- Auto-inicia com o macOS (LaunchAgent `com.joao.ulamp-widget`)
- Permissões: Bluetooth + Gravação de Tela (já concedidas)
- Reconstruir: `cd widget && swiftc -O -o uLampWidget uLampWidget.swift -framework AppKit -framework CoreBluetooth -framework ScreenCaptureKit`

## Notas de operação

- O Mac precisa ficar com Bluetooth ligado e **o app uLamp fechado** (BLE é exclusivo).
- O `TID` inicial é aleatório e incrementa; a lâmpada aceita qualquer sequência.
- Estado por advertisement (`uac088`, mfr `5456 02 ...`) também funciona para leitura sem conexão (`ulamp_sniff`).
- Se um dia um firmware novo exigir auth, o caminho da nuvem está documentado em PROTOCOL.md §5c.

## Histórico da investigação (resumo)

1. Localizado app iOS no Mac → `ua_common.lua` (bytecode Lua 5.3 com VM customizada)
2. Quebrados por criptoanálise: layout de instrução (`op[0:6] A[6:14] C[14:22] k[22] B[23:31]`), permutação de opcodes → 61 funções descompiladas = protocolo genérico "JX"
3. Teste ao vivo: JX ignorado; probe GATT achou resposta no serviço transparente → caça à auth (Hopper travado → otool: stubs `__objc_stubs` resolvidos manualmente; chaves HMAC e cadeia nonce/sign extraídas)
4. App rodou no Mac → container → **fonte Lua oficial do produto baixada** → protocolo real `0A A5` sem auth
5. Validado ao vivo: on/off/RGB/status — tudo confirmado pela própria lâmpada
