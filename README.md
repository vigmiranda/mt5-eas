# MT5 Expert Advisors — Nomo + Clear

Repositório: [vigmiranda/mt5-eas](https://github.com/vigmiranda/mt5-eas)

Automação em **MetaTrader 5** para duas corretoras:

| Pasta | Corretora | Mercado |
|-------|-----------|---------|
| `eas/nomo/` | Nomo | Forex / CFDs |
| `eas/clear/` | Clear | Minicontratos B3 (WIN) |

---

## Clear (B3)

| Ativo | Timeframe | EA | Magic | Versão | Papel |
|-------|-----------|----|-------|--------|-------|
| WINV26 / WIN$ | M5 | **ScalpWIN_v2** | 260917 | 2.00 | Daytrade escada % (recomendado) |
| WINV26 / WIN$ | M5 | ScalpWIN_v1 | 260916 | 1.02 | Scalp TP/ATR (referência) |
| WINV26 / WIN$ | M5 | TrendWIN_v1 | 260914 | 1.11 | Tendência (referência) |

**ScalpWIN_v2** (preferido)
- Rompimento M5 + EMA/ADX (mesma entrada seletiva)
- **Volume por capital** (1 mini / R$ 1.000) — sobe com o saldo
- **Escada de lucro** sobre o capital do dia: **+2% → fecha 50%** · **+5% → fecha +25%** · resto com soft lock (mais apertado após parciais)
- Com **1 contrato**: no 1º alvo fecha tudo (não dá pra fracionar)
- **SL folgado** por ATR, teto **5%** do capital (não aperta demais no ruído)
- **Sem teto de trades/dia** — só para no **stop diário 10%** do capital do dia
- Capital Manual (Clear) + logs `SKIP | motivo`
- Sessão 10:15–16:45, flat ~17:00

Instalação: copie `eas/clear/ScalpWIN_v2.mq5` → `MQL5/Experts/`, compile (F7), arraste no **WINV26 M5**. Remova ScalpWIN_v1 / TrendWIN do gráfico. Ajuste `InpManualCapital`.

**ScalpWIN_v1** / **TrendWIN_v1**: referências anteriores.

---

## Nomo (layout recomendado)

| Par | Timeframe | EA | Magic | Versão | Papel |
|-----|-----------|----|-------|--------|-------|
| EURUSD | M30 | TrendEURUSD_v1 | 260828 | 1.22 | Trend filtrado |
| USDJPY | M5 | ScalpUSDJPY_v2 | 260830 | 2.01 | Daytrade seletivo |

### Demais EAs Nomo (referência)

| Par | Timeframe | EA | Magic | Versão |
|-----|-----------|----|-------|--------|
| XRPUSD | M30 | TrendXRPUSD_v1 | 300831 | 1.40 |
| DOGEUSD | M30 | TrendMeme_Pct_v1 | 310901 | 1.10 |
| BTCUSD | H1 | TrendBTCUSD_v1 | 310903 | 1.10 |
| WTIUSD | H1 | TrendWTIUSD_v1 | 310902 | 1.10 |
| NMAI | H1 | NMAI_BuyDip_v1 | 310904 | 1.00 |

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
    TrendEURUSD_v1.mq5
    ScalpUSDJPY_v2.mq5
    TrendXRPUSD_v1.mq5
    TrendBTCUSD_v1.mq5
    TrendWTIUSD_v1.mq5
    TrendMeme_Pct_v1.mq5
    NMAI_BuyDip_v1.mq5
    archive/              # versões antigas
```

## Aviso

Ferramentas de automação. Teste em demo antes de conta real. Na Clear, confirme alocação em **Day Trade (Plataformas)** e RLP ativo para minicontratos.
