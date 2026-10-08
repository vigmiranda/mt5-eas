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
| WINV26 / WIN$ | M5 | **ScalpWIN_v2** | 260917 | 2.12 | Daytrade escada % (recomendado) |
| WINV26 / WIN$ | M5 | ScalpWIN_v1 | 260916 | 1.02 | Scalp TP/ATR (referência) |
| WINV26 / WIN$ | M5 | TrendWIN_v1 | 260914 | 1.11 | Tendência (referência) |

**ScalpWIN_v2** (preferido)
- Rompimento M5 + EMA/ADX (entrada seletiva)
- **Capital virtual (Clear):** semente **R$5.353,45** (saldo Clear) + PnL novo − taxas (~R$0,25/lado)
- **Faixas:** R$500–1500 → 1 · R$1500–2500 → 2 · … (com ~R$5353 → **vol≈5**)
- **Filtros v2.12:** ADX ≥ **20** · corpo **0,40–1,30×ATR** · break **4** · vol ≥ **0,95×** · cooldown **6** barras
- Sessão **10:30–15:45**, flat **16:00**
- Histórico: `MQL5/Files/ScalpWIN_v2_equity.csv`
- Escada: **+2% → 50%** · **+5% → +25%** · resto soft lock
- SL folgado ATR, teto **5%** · **STOP DIA 5%** · **BANK DIA 2%** (protege) · **META 3%**
- v2.12: vol 0,95 + STOP 5% + bank 2% (exceção multi-ajuste pós-análise histórico)
- `.set` recomendado: `eas/clear/ScalpWIN_v2.set`

Instalação: copie `eas/clear/ScalpWIN_v2.mq5` (+ opcional `.set`) → `MQL5/Experts/`, F7. **Remova** e arraste de novo. Log: `v2.12`, `stopDia=5%`, `bankDia=2%`, `vol>=0.95`.

### Capital virtual Clear — como funciona

A Clear (B3) muitas vezes **não reporta** equity/balance confiável no MT5. Por isso o ScalpWIN_v2 usa **capital virtual**:

`capital = semente (InpClearSaldo) + PnL do magic depois da semente − taxas estimadas (+ floating)`

- A semente fica salva no terminal (GlobalVariable), não no saldo da corretora.
- **Aporte na Clear não atualiza o EA sozinho** — é preciso regravar a semente (passo a passo abaixo).
- Faixas de contratos, META DIA e STOP DIA usam esse capital virtual.
- **v2.11** já vem com semente **R$5.353,45** (nova chave GV → aplica ao arrastar de novo).

### Aporte / atualizar semente (passo a passo)

Quando depositar (ou quiser alinhar a semente ao saldo Clear atual):

1. Veja o **saldo atual na Clear** (app/site), ex.: R$5.353,45  
2. No gráfico, abra as propriedades do **ScalpWIN_v2**  
3. Em **Volume / capital virtual**:
   - `InpClearSaldo` = saldo Clear atual  
   - `InpResetVirtualSeed` = **true**  
4. Clique OK → **remova** o EA do gráfico → **arraste de novo** (sem .set antigo)  
5. No log **Experts**, confira: `ScalpWIN2: semente R$5353.45 a partir de …`  
6. Abra de novo as propriedades e volte `InpResetVirtualSeed` = **false**  
   (se deixar `true`, cada restart zera a época de novo)

O reset também reinicia a “época”: o PnL antigo deixa de ser somado (já está refletido no saldo Clear) e o EA passa a contar só operações **depois** desse momento.

**Saque:** mesma lógica — coloque em `InpClearSaldo` o saldo Clear **após** o saque e use `InpResetVirtualSeed = true` uma vez.

**ScalpWIN_v1** / **TrendWIN_v1**: referências anteriores.

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
    ScalpWIN_v2.mq5       # Clear / WIN escada % (recomendado)
    ScalpWIN_v1.mq5       # Clear / WIN scalp TP (referência)
    TrendWIN_v1.mq5       # Clear / WIN tendência (referência)
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
