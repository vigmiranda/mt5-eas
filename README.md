# MT5 Expert Advisors — Nomo + Clear

Repositório: [vigmiranda/mt5-eas](https://github.com/vigmiranda/mt5-eas)

**Regras do projeto (valem em qualquer plataforma):** [`REGRAS.md`](REGRAS.md) · agentes: [`AGENTS.md`](AGENTS.md)

Automação em **MetaTrader 5** para duas corretoras:

| Pasta | Corretora | Mercado |
|-------|-----------|---------|
| `eas/nomo/` | Nomo | Forex / CFDs |
| `eas/clear/` | Clear | Minicontratos B3 (WIN) |

---

## Clear (B3)

| Ativo | Timeframe | EA | Magic | Versão | Papel |
|-------|-----------|----|-------|--------|-------|
| WINV26 / WIN$ | M5 | **RegimeRouterWIN_v1** | 260920 | 1.00 | **Único EA ativo (roteador de regimes)** |

EAs anteriores (OpenBreak, Pullback, ScalpWIN, TrendWIN) estão em [`eas/clear/archive/`](eas/clear/archive/) — **não usar no real**.

**RegimeRouterWIN_v1** — um EA, vários regimes
- **R1 ABERTURA_OK** (caixa 80–1200 pts): módulo OpenBreak manhã (até 10:30, flat 11:00, BE+trail)
- **R2 EXPLOSIVA** (caixa inválida): sem ORB; tarde só Pullback se virar **R3**; senão fora
- **R3 TENDÊNCIA** (ADX≥20 + EMAs alinhadas): Pullback 1 trade, TP 2R
- **R4 LATERAL** (ADX≤18, e não R2): Mean-reversion Bollinger, **1 contrato**, 1 trade
- **RISCO_DIA**: STOP **5%** único (todos os módulos) → flat + bloqueio
- Capital virtual Clear · volume default **1** · logs ricos `Router:` · telinha com regime/módulo/porque
- Magic **260920** · Histórico: `MQL5/Files/RegimeRouterWIN_v1_equity.csv`

**Instalação**
1. Remova qualquer EA antigo do gráfico WIN (OpenBreak/Pullback/Scalp…)
2. Copie `eas/clear/RegimeRouterWIN_v1.mq5` → `MQL5/Experts/` → **F7**
3. Arraste no **WIN M5**, Algotrading ON
4. Log: `RegimeRouterWIN v1.00` + linhas `REGIME …` / `ENTRADA …`
5. Telinha: `REGIME: R1_…` / `módulo:` / `porque:` / dayPnL / trades OB/PB/MR

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

| Par | Timeframe | EA | Magic | Versão | Papel |
|-----|-----------|----|-------|--------|-------|
| XAUUSD | **M15** | **ScalpXAUUSD_v1** | 320930 | 1.05 | Daytrade ouro escada % (recomendado) |
| XAUUSD | **M15** | **PatternXAUUSD_v1** | 320931 | 1.00 | A/B padrões candle (paralelo) |
| EURUSD | M30 | TrendEURUSD_v1 | 260828 | 1.22 | Trend filtrado |
| USDJPY | M5 | ScalpUSDJPY_v3 | 260831 | 3.03 | Pausado / referência |

**ScalpXAUUSD_v1** (preferido na Nomo)
- DNA **ScalpWIN**: rompimento + ADX + escada + soft lock · **sem grid/martingale** (1 posição)
- **Faixas de lote:** US$200–500 → **0,01** · 500–800 → **0,02** · 800–1100 → **0,03** · (+US$300 → +0,01)
- **META DIA +3%** (flat + realizado) · **STOP DIA 5%** · **sem teto** de trades/dia
- Escada: **+0,5% → zera micro-lote** (~US$1,50 em ~300) · **+1% → L2** · soft lock **0,5×ATR**
- Filtros **v1.05 (apertados):** EMA **on** · ADX ≥ **22** · corpo ≥ **0,40×ATR** · break **4** · vol ≥ **1,0×**
- Sessão **13:00–19:00 GMT** · flat **21:00 GMT** · **só seg–sex** · M15
- Magic **320930**

Instalação: copie `eas/nomo/ScalpXAUUSD_v1.mq5` → `MQL5/Experts/`, compile (F7). Gráfico **XAUUSD M15**. **Remova** e arraste de novo. Log: `v1.05`, `EMA=on`, `ADX>=22`, `break=4`.

**PatternXAUUSD_v1** (experimento A/B — não altera o Scalp)
- Mesmo DNA de risco (faixas, escada, META/STOP, sessão) · **entrada por padrões**
- Padrões: **Three Outside Up/Down** · **Three White Soldiers / Black Crows** · **Engulfing**
- Filtros: EMA **on** · ADX ≥ **20** · corpo ≥ **0,25×ATR** · vol ≥ **0,90×**
- Magic **320931** · comment `PatternXAUUSD_v1`
- Rode em **outro gráfico** XAUUSD M15 em paralelo; risco pode somar — desligue o pior

Instalação: copie `eas/nomo/PatternXAUUSD_v1.mq5` → `MQL5/Experts/`, compile (F7). Novo gráfico **XAUUSD M15**. Log: `v1.00`, `magic=320931`, `padrões: engulf=on`.

### Demais EAs Nomo (referência)

| Par | Timeframe | EA | Magic | Versão |
|-----|-----------|----|-------|--------|
| XRPUSD | M30 | TrendXRPUSD_v1 | 300831 | 1.40 |
| DOGEUSD | M30 | TrendMeme_Pct_v1 | 310901 | 1.10 |
| BTCUSD | H1 | TrendBTCUSD_v1 | 310903 | 1.10 |
| WTIUSD | H1 | TrendWTIUSD_v1 | 310902 | 1.10 |
| NMAI | H1 | NMAI_BuyDip_v1 | 310904 | 1.00 |
| BTCUSD | M15+ | **Nomo_Futures_Grid_Bot** | 310940 | 1.01 | **EXPERIMENTAL grid** |

**Nomo_Futures_Grid_Bot** (teste BTC ~US$300 — **fora das REGRAS** de “sem grid / 1 posição”)
- Lote **0,01** · níveis default **3** (teto 8) · faixa auto **±2%** do preço
- No init: loga margem buy/sell do 0,01 e quantos níveis a free margin comporta
- Só arma os níveis **mais próximos** que cabem na margem (sem spam de erro)
- BuyLimit abaixo / SellLimit acima · TP = 1 passo de grid
- Fora da faixa: fecha posições + cancela pendentes
- Magic **310940** · só para experimento; não misturar com Scalp/Trend no mesmo capital sem saber o risco

Instalação: `eas/nomo/Nomo_Futures_Grid_Bot.mq5` → `MQL5/Experts/`, F7, gráfico **BTCUSD**. Log: `GridBTC EXP v1.01`, `MARGEM 0.01 | buy≈… sell≈…`.

Arquivos em `eas/nomo/`. Legados em `eas/nomo/archive/`.

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
    RegimeRouterWIN_v1.mq5  # Clear / WIN roteador de regimes (ativo)
    archive/                # EAs antigos (não usar no real)
  nomo/
    ScalpXAUUSD_v1.mq5    # Nomo / XAUUSD escada % (recomendado)
    PatternXAUUSD_v1.mq5  # Nomo / XAUUSD padrões candle (A/B)
    ScalpUSDJPY_v3.mq5    # USDJPY (pausado / referência)
    ScalpUSDJPY_v2.mq5
    TrendEURUSD_v1.mq5
    TrendXRPUSD_v1.mq5
    TrendBTCUSD_v1.mq5
    TrendWTIUSD_v1.mq5
    TrendMeme_Pct_v1.mq5
    NMAI_BuyDip_v1.mq5
    archive/              # versões antigas
```

## Aviso

Ferramentas de automação. Teste em demo antes de conta real. Na Clear, confirme alocação em **Day Trade (Plataformas)** e RLP ativo para minicontratos.
