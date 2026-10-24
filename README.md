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
| WINV26 / WIN$ | M5 | **RegimeRouterWIN_v1** | 260920 | 1.13 | **Único EA ativo (roteador em cascata)** |

EAs anteriores (OpenBreak, Pullback, ScalpWIN, TrendWIN) estão em [`eas/clear/archive/`](eas/clear/archive/) — **não usar no real**.

**RegimeRouterWIN_v1** — cascata M5 (v1.13)
- **A OpenBreak → B Pullback → D ContBreak → E VwapFade → C Preço médio** (flags `InpEnable*`)
- **CB / VF ligados por padrão** — desligue no input se for mal (`InpEnableContBreak` / `InpEnableVwapFade`)
- **Lock:** 1 estratégia dona até flat (PM pode abrir pernas)
- **Aborto cedo do OB** → libera B–E antes das 11h
- PB só entra com **sinal de pullback** (senão a cascata tenta CB)
- CB: rompimento do range manhã (09:00→11:00) com ADX≥22 · VF: fade à VWAP se dist≥150 pts e ADX≤22
- **R2:** OB off · **PM** bloqueado · **VF liberado só após 10:00** · PB/CB se fit
- **Piso SL (v1.13):** VF **e** PB — `max(**200** hardcoded, MinRisk, ATR×1 / R2×1,25)`. Input 80 no gráfico **não** vale. VF: se VWAP não pagar RR≥1 → **skip**
- **Sizing (v1.10):** por capital virtual — **&lt;R$5k → 1** · **≥R$5k → 2** · **≥R$8k → 3** (teto); `SIZING_FIXED` opcional
- Arraste no gráfico **WIN M5** (init avisa se chart ≠ `InpTF`) — sem afrouxar MaxBox / ADX / candle PB
- **Sem meta de lucro** · teto `InpMaxTradesDay` · **STOP DIA 5%** · semente **R$4.538,48** · magic **260920**
- Log curto `RR …` · legenda: [`eas/clear/RegimeRouterWIN_LOG.md`](eas/clear/RegimeRouterWIN_LOG.md)

**Instalação**
1. Remova qualquer EA antigo do gráfico WIN (OpenBreak/Pullback/Scalp…)
2. Copie `eas/clear/RegimeRouterWIN_v1.mq5` → `MQL5/Experts/` → **F7**
3. Arraste no **WIN M5**, Algotrading ON
4. Log: `RegimeRouterWIN v1.13` + `SL efetivo≥200` — ver legenda
5. CB/VF já vêm ON — desligue no input se precisar
6. Se o gráfico guardar MinRisk=80: o código **ignora** (&lt;200); ainda assim prefira Resetar inputs / colocar 200 manualmente

### Capital virtual Clear — como funciona

A Clear (B3) muitas vezes **não reporta** equity/balance confiável no MT5. Por isso o RegimeRouter usa **capital virtual**:

`capital = semente (InpClearSaldo) + PnL do magic depois da semente − taxas estimadas (+ floating)`

- A semente fica salva no terminal (GlobalVariable).
- **Aporte na Clear não atualiza o EA sozinho** — regrave a semente (abaixo).
- STOP DIA 5% e o **lote (faixas 1/2/3)** usam esse capital virtual.

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
| XAUUSD | **M15** | **RegimeRouterXAU_v1** | 320932 | 1.00 | Roteador — **opera** |
| ETHUSD | **H1** (ou M15) | **TrendAdvisorETH_v1** | 330933 | 1.01 | Tendência — sinal + **1 ordem** (não empilha) |

Demais EAs Nomo (ScalpXAU, Pattern, Trend*, Grid BTC, etc.) estão em [`eas/nomo/archive/`](eas/nomo/archive/) — **não usar no real**.

**RegimeRouterXAU_v1** — ouro, mesma lógica de regimes do WIN
- Saldo seed/fallback **US$254** · lote fixo **0,01** · STOP DIA **5%** (~US$12,70)
- Sessão **GMT** (servidor Nomo): caixa Londres **13:00–13:30** · OB até **15:00** · tarde **16:05–19:00** · flat **21:00** · só dias úteis
- **R1** caixa OK → OpenBreak · **R2** explosiva → sem ORB, tarde só se R3 · **R3** Pullback · **R4** MeanRev BB
- Logs `Router: M15 …` a cada barra + telinha com regime/módulo/porque
- Magic **320932**

**TrendAdvisorETH_v1** — ETH 24x7, sinal + execução (máx **1** posição)
- Default **H1** (`InpTF`; M15 se quiser mais sinais)
- Tendência: EMA20/50 + ADX≥20 → ALTA / BAIXA / LATERAL
- **SINAL COMPRA/VENDA** + ordem a mercado só com pullback conveniente
- Defaults execução (print Nomo): lote **0,20** · SL **4252** pts · TP **5473** pts
- Se já houver posição/pendente do magic → **não abre outra**
- Sem setup: `TA .. | … aguarde` · na entrada: `TA ! | EXECUTOU BUY/SELL …`
- `InpEnableTrading=false` volta ao modo só-log · magic **330933**

**Instalação**
1. Arquivo: só use os EAs da tabela acima (resto em `archive/`)
2. XAU: `RegimeRouterXAU_v1.mq5` → F7 → **XAUUSD M15** (se for usar)
3. ETH: `TrendAdvisorETH_v1.mq5` → F7 → **ETHUSD H1** · Algotrading **ON**
4. Logs: `TrendAdvisorETH v1.01` / `TA !` (sinal+exec) / `TA ..` (aguarde / já em posição)

---

## Genial (Profit Pro · NTSL)

| Ativo | Timeframe | Estratégia | Versão | Papel |
|-------|-----------|------------|--------|-------|
| WDO$ | M5 | **RegimeRouterWDO_v1** | 1.11 | Único robô ativo na sim Genial |

**RegimeRouterWDO_v1** — cascata larga p/ teste Genial (dólar) · DNA alinhado ao WIN
- `OB → AB → OF → PB → NY → CB → IB → RD → LF → VF` (flags ON)
- **R2:** OB/LF off · **VF on só após 10:00** (`VF_R2Start`) · demais se fit
- **Risco dinâmico (v1.11):** max risco/trade = `%` do `SeedCapital` (teto fração do STOP DIA); TP encurtado se longe demais; skip se SL &gt; max (`riskMax=` no log)
- **Gestão (v1.11):** BE+trail em **todos** os módulos (não só OB) — evita ficar até o flat sem SL/TP
- **VF SL (v1.10):** piso ATR/min risk + RR vs VWAP
- **Sizing v1.08:** `SeedCapital` — **&lt;R$5k → 1** · **≥R$5k → 2** · **≥R$8k → 3**
- **Visual:** `RegimeRouterWDO_viz` = Regra de Coloração no gráfico (sem ordens); execução só na Automação
- Automação **WDO M5** · máx posição **≥ MaxLots (3)** · sem preço médio
- STOP via `SeedCapital` (5%) ou `StopDiaReais`
- Pasta: [`eas/genial/`](eas/genial/) · guia: [`eas/genial/README.md`](eas/genial/README.md) · legenda: [`eas/genial/RegimeRouterWDO_LOG.md`](eas/genial/RegimeRouterWDO_LOG.md)

**Instalação rápida:** Editor → colar execução + viz → Automação **sim** WDO **M5** · coloração = viz. Detalhes no README da pasta.

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
    RegimeRouterXAU_v1.mq5   # Nomo / XAU (opera)
    TrendAdvisorETH_v1.mq5   # Nomo / ETH (sinal + 1 ordem)
    archive/
  genial/
    RegimeRouterWDO_v1.ntsl   # execução (Automação)
    RegimeRouterWDO_viz.ntsl  # Regra de Coloração (sem ordens)
    README.md
    RegimeRouterWDO_LOG.md
```

## Aviso

Ferramentas de automação. Teste em demo antes de conta real. Na Clear, confirme alocação em **Day Trade (Plataformas)** e RLP ativo para minicontratos.
