# RegimeRouterWIN — legenda do log (v1.07+)

No Experts do MT5 a coluna **Mensagem** é estreita. Por isso o pulse M5 usa **2 linhas curtas** com prefixo `RR` e abreviações.

Documentação geral do EA: [`README.md`](../../README.md) · regras: [`REGRAS.md`](../../REGRAS.md).

**Sizing (v1.10):** `BY_CAPITAL` padrão — capital virtual **&lt;R$5k → 1 mini** · **≥R$5k → 2** · **≥R$8k → 3** (teto `InpMaxVolume`), igual em OB/PB/CB/VF/PM. Init loga `sizing=… | vol=… | bandas …`.

**VF em R2 (v1.11):** em dia de caixa explosiva, VWAP fade só após **10:00** (`InpVF_R2StartH/M`). Skip: `VF em R2 só após 10:00…`.

**VF SL (v1.12):** stop = mais longe entre (extremo+buffer) e piso `max(MinRiskPts, ATR×mult)` (R2 usa mult maior). Se distância à VWAP &lt; risco×`MinRewardRisk` → skip `VF RR fraco…`. Init reconta trades do histórico (`trades reconstruidos`).

---

## Formato a cada barra M5

```
RR HH:MM | <regime> <módulo> | <decisão> | cx=… ADX=… dPnL=… t=… [o|p|c|v|m]
RR .. | <porque (regimeWhy)> | <último skip ou ação>
```

**Exemplo**

```
RR 11:20 | R5 CB | WAIT-CB | cx=420(OK) ADX=24 dPnL=0 t=0/8 [0|0|0|0|0]
RR .. | cascata D | CB ADX 24.1 range 128400–128820 viés ALTA | CB aguarda rompimento...
```

Outros prefixes:

| Prefixo | Quando aparece |
|---------|----------------|
| `RR init \| …` | Na inicialização do EA |
| `RR ! \| …` | Evento importante (entrada, regime, ciclo PM, etc.) |
| `RR …` / `RR .. \| …` | Pulse periódico (estado + detalhe) |

---

## Regime (`RegimeAbbr`)

| Abrev | Significado |
|-------|-------------|
| `R1` | Abertura OK — caixa válida, OpenBreak elegível |
| `R2` | Abertura explosiva / caixa inválida — sem ORB; **PM** bloqueado; **VF liberado** (v1.07+) |
| `R3` | Tendência — Pullback com **sinal** |
| `R4` | Lateral — Preço médio elegível |
| `R5` | Continuação — ContBreak (rompimento range manhã) |
| `R6` | VWAP fade — extensão vs VWAP de sessão |
| `STOP` | STOP DIA ativo (risco do dia) |
| `FORA` | Fora de sessão / sem fit / flat |
| `?` | Desconhecido |

---

## Módulo / estratégia (`ModuleAbbr`)

Cascata: **OB → PB → CB → VF → PM**.

| Abrev | Estratégia | Flag (default) |
|-------|------------|----------------|
| `OB` | OpenBreak (abertura) | `InpEnableOpenBreak` = on |
| `PB` | Pullback (tendência + sinal) | `InpEnablePullback` = on |
| `CB` | ContBreak (continuação / breakout) | `InpEnableContBreak` = **on** |
| `VF` | VwapFade (reversão à VWAP) | `InpEnableVwapFade` = **on** |
| `PM` | Preço médio (lateral, até 3 pernas) | `InpEnablePrecoMedio` = on |
| `-` | Nenhum módulo ativo | — |

Com posição (ou pernas PM), fica em **LOCK** nessa estratégia até flat.

---

## Decisão (3º campo do pulse)

| Abrev | Significado |
|-------|-------------|
| `IDLE` | Cascata sem fit / flags / fora de janela — não opera |
| `WAIT-OB` / `WAIT-PB` / `WAIT-CB` / `WAIT-VF` / `WAIT-PM` | Módulo ativo, aguardando sinal |
| `LOCK-OB` / `LOCK-PB` / `LOCK-CB` / `LOCK-VF` / `LOCK-PM` | Posição aberta — só gestão |
| `POS` | Em posição (gestão) |
| `MAX` | Atingiu teto de segurança `InpMaxTradesDay` |
| `STOP` | STOP DIA — flat + bloqueio |

---

## Campos da linha 1

| Campo | Significado |
|-------|-------------|
| `cx=1355(R2)` | Tamanho da caixa em pontos + tag: `OK` / `R2` / `…` (montando) |
| `ADX=29` | ADX atual (arredondado) |
| `dPnL=0` | Day PnL em R$ (virtual) |
| `t=0/8` | Trades do dia / teto de segurança |
| `[o\|p\|c\|v\|m]` | Contadores `OB\|PB\|CB\|VF\|PM` (ciclos já usados hoje) |

---

## Ideia rápida dos módulos novos

**CB (ContBreak)**  
Após range manhã (09:00 → `InpCB_RangeEnd`, default 11:00), com ADX ≥ `InpCB_ADXMin` e EMAs alinhadas: rompimento da máx/mín da manhã no sentido da tendência. 1 entrada, TP por R:R.

**VF (VwapFade)**  
Preço longe da VWAP de sessão (≥ `InpVF_MinDistPts`) e ADX ≤ `InpVF_ADXMax`: fade de volta à VWAP (1 entrada, TP = VWAP).  
**v1.07:** também elegível em dia **R2** (mesmos critérios de distância/ADX — não afrouxa entrada). PM continua bloqueado em R2.

**v1.08 (bugfix):** risco/distância em pontos rejeitam cotação ou SL inválidos (`entry<=0`, `sl<=0`, risco &gt; 5000 pts). VF mede dist no **close** da barra (não bid live). PB não consome sinal se o risco for absurdo.

**v1.09:** `QuotesOk` com fallback `SymbolInfoTick` / `LAST` / close — no Clear `WIN$N` o BID/ASK às vezes vem 0 e bloqueava CB/VF o dia todo (`sem cotacao bid/ask`).

**Ops (sem afrouxar regra):** arraste o EA no gráfico **WIN M5**. Se o chart ≠ `InpTF`, o init loga `RR ! | AVISO chart≠InpTF`.

---

## Telinha do gráfico (`Comment`)

```
RR v1.09 WIN$N | R5 CB | CB rng 128400-128820
...
OB1 PB1 CB0 VF0 PM1 | free | cx=420(OK)
```

| Tag | Significado |
|-----|-------------|
| `OB1 PB1 CB0 VF0 PM1` | `1` = ligada, `0` = desligada |
| `LOCK CB` / etc. | Estratégia dona da posição |
| `OBabort` | OpenBreak liberou a cascata B–E |
| `HALT` | Dia parado por STOP |

---

## Eventos importantes (`RR !`)

```
RR ! | ENTRADA CB BUY vol=1 @≈... | regime=R5 | ...
RR ! | OB ABORTADO → libera cascata B–E | ...
```
