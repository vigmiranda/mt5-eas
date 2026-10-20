# MT5 Expert Advisors — Nomo + Clear

Repositório: [vigmiranda/mt5-eas](https://github.com/vigmiranda/mt5-eas)

**Regras do projeto (valem em qualquer plataforma):** [`REGRAS.md`](REGRAS.md) · agentes: [`AGENTS.md`](AGENTS.md)

Automação multiplataforma:

| Pasta | Corretora / plataforma | Mercado |
|-------|--------------------------|---------|
| `eas/nomo/` | Nomo · **MT5** | Forex / CFDs |
| `eas/clear/` | Clear · **MT5** | Minicontratos B3 (WIN) |
| `eas/genial/` | Genial · **Profit Pro (NTSL)** | Minicontrato dólar (WDO) |

---

## Clear (B3)

| Ativo | Timeframe | EA | Magic | Versão | Papel |
|-------|-----------|----|-------|--------|-------|
| WINV26 / WIN$ | M5 | **RegimeRouterWIN_v1** | 260920 | 1.07 | **Único EA ativo (roteador em cascata)** |

EAs anteriores (OpenBreak, Pullback, ScalpWIN, TrendWIN) estão em [`eas/clear/archive/`](eas/clear/archive/) — **não usar no real**.

**RegimeRouterWIN_v1** — cascata M5 (v1.07)
- **A OpenBreak → B Pullback → D ContBreak → E VwapFade → C Preço médio** (flags `InpEnable*`)
- **CB / VF ligados por padrão** — desligue no input se for mal (`InpEnableContBreak` / `InpEnableVwapFade`)
- **Lock:** 1 estratégia dona até flat (PM pode abrir pernas)
- **Aborto cedo do OB** → libera B–E antes das 11h
- PB só entra com **sinal de pullback** (senão a cascata tenta CB)
- CB: rompimento do range manhã (09:00→11:00) com ADX≥22 · VF: fade à VWAP se dist≥150 pts e ADX≤22
- **R2:** OB off · **PM** bloqueado · **VF liberado** (mesmos critérios; v1.07) · PB/CB se fit
- Arraste no gráfico **WIN M5** (init avisa se chart ≠ `InpTF`) — sem afrouxar MaxBox / ADX / candle PB
- **Sem meta de lucro** · teto `InpMaxTradesDay` · **STOP DIA 5%** · semente **R$4.538,48** · magic **260920**
- Log curto `RR …` · legenda: [`eas/clear/RegimeRouterWIN_LOG.md`](eas/clear/RegimeRouterWIN_LOG.md)

**Instalação**
1. Remova qualquer EA antigo do gráfico WIN (OpenBreak/Pullback/Scalp…)
2. Copie `eas/clear/RegimeRouterWIN_v1.mq5` → `MQL5/Experts/` → **F7**
3. Arraste no **WIN M5**, Algotrading ON
4. Log: `RegimeRouterWIN v1.07` + `RR …` (2 linhas/M5) — ver legenda
5. CB/VF já vêm ON — desligue no input se precisar

### Capital virtual Clear — como funciona

A Clear (B3) muitas vezes **não reporta** equity/balance confiável no MT5. Por isso o RegimeRouter usa **capital virtual**:

`capital = semente (InpClearSaldo) + PnL do magic depois da semente − taxas estimadas (+ floating)`

- A semente fica salva no terminal (GlobalVariable).
- **Aporte na Clear não atualiza o EA sozinho** — regrave a semente (abaixo).
- STOP DIA 5% usa esse capital virtual.

### Aporte / atualizar semente (passo a passo)

1. Saldo atual na Clear (app/site)  
2. Propriedades do **RegimeRouterWIN_v1** → `InpClearSaldo` + `InpResetVirtualSeed=true`  
3. OK → remova o EA → arraste de novo  
4. Log: `Router: semente capital R$…`  
5. Volte `InpResetVirtualSeed=false`

**Arquivo:** `eas/clear/archive/` = referências antigas.

---

## Nomo (layout recomendado)

| Ativo | Timeframe | EA | Magic | Versão | Papel |
|-------|-----------|----|-------|--------|-------|
| XAUUSD | **M15** | **RegimeRouterXAU_v1** | 320932 | 1.00 | **Único EA ativo Nomo (roteador)** |

Demais EAs Nomo (ScalpXAU, Pattern, Trend*, Grid BTC, etc.) estão em [`eas/nomo/archive/`](eas/nomo/archive/) — **não usar no real**.

**RegimeRouterXAU_v1** — ouro, mesma lógica de regimes do WIN
- Saldo seed/fallback **US$254** · lote fixo **0,01** · STOP DIA **5%** (~US$12,70)
- Sessão **GMT** (servidor Nomo): caixa Londres **13:00–13:30** · OB até **15:00** · tarde **16:05–19:00** · flat **21:00** · só dias úteis
- **R1** caixa OK → OpenBreak · **R2** explosiva → sem ORB, tarde só se R3 · **R3** Pullback · **R4** MeanRev BB
- Logs `Router: M15 …` a cada barra + telinha com regime/módulo/porque
- Magic **320932**

**Instalação:** remova ScalpXAU/Pattern/etc. → `eas/nomo/RegimeRouterXAU_v1.mq5` → F7 → gráfico **XAUUSD M15**. Log: `RegimeRouterXAU v1.00`.

---

## Genial (Profit Pro · NTSL)

| Ativo | Timeframe | Estratégia | Versão | Papel |
|-------|-----------|------------|--------|-------|
| WDO$ | M5 | **RegimeRouterWDO_v1** | 1.04 | Único robô ativo na sim Genial |

**RegimeRouterWDO_v1** — cascata larga p/ teste Genial (dólar) · DNA alinhado ao WIN
- `OB → AB → OF → PB → NY → CB → IB → RD → LF → VF` (flags ON)
- **R2** (caixa inválida): OB off · **LF** bloqueado · **VF liberado** (mesmos critérios; v1.04) · AB/OF/PB/NY/CB/IB/RD se fit
- Automação no **WDO M5** · 1 contrato · sem preço médio
- STOP via `SeedCapital` (5%) ou `StopDiaReais` — na migração Clear→Genial, gravar o capital alocado em `SeedCapital`
- Pasta: [`eas/genial/`](eas/genial/) · guia: [`eas/genial/README.md`](eas/genial/README.md) · legenda: [`eas/genial/RegimeRouterWDO_LOG.md`](eas/genial/RegimeRouterWDO_LOG.md)

**Instalação rápida:** Profit Pro → Editor → colar `.ntsl` → Automação **sim** → WDO **M5** · qtd 1. Detalhes no README da pasta.

---

## Instalação geral

1. Copie o `.mq5` da pasta correta (`nomo` ou `clear`) para `MetaTrader 5/MQL5/Experts/`
2. MetaEditor → compile (**F7** → 0 erros)
3. No gráfico (símbolo + timeframe): arraste o EA
4. Ative **Algotrading**
5. Confira o log **Experts** na inicialização

## Soft lock

Tendência + ADX + SL por ATR, **sem TP fixo**. Soft lock arma depois de X ATR de lucro e faz trail.

## Estrutura

```
eas/
  clear/
    RegimeRouterWIN_v1.mq5   # Clear / MT5 / WIN (ativo)
    archive/
  nomo/
    RegimeRouterXAU_v1.mq5   # Nomo / MT5 / XAU (ativo)
    archive/
  genial/
    RegimeRouterWDO_v1.ntsl  # Genial / Profit Pro / WDO (sim)
    README.md
    RegimeRouterWDO_LOG.md
```

## Aviso

Ferramentas de automação. Teste em demo antes de conta real. Na Clear, confirme alocação em **Day Trade (Plataformas)** e RLP ativo para minicontratos.
