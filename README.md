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
| WINV26 / WIN$ | M5 | **ScalpWIN_v2** | 260917 | 2.03 | Daytrade escada % (recomendado) |
| WINV26 / WIN$ | M5 | ScalpWIN_v1 | 260916 | 1.02 | Scalp TP/ATR (referência) |
| WINV26 / WIN$ | M5 | TrendWIN_v1 | 260914 | 1.11 | Tendência (referência) |

**ScalpWIN_v2** (preferido)
- Rompimento M5 + EMA/ADX (entrada seletiva)
- **Capital virtual (Clear):** semente (`InpSeedCapital`) + PnL do magic — não depende do saldo MT5
- **Faixas de volume:** R$500–1500 → 1 · R$1500–2500 → 2 · R$2500–3500 → 3 · …
- **Histórico diário** em `MQL5/Files/ScalpWIN_v2_equity.csv` (ini / dayPnL / fim / contratos)
- **v2.02+ filtros:** ADX ≥ 25, corpo ≥ 0,50×ATR, rompimento 5 barras, volume ≥ 1,30× média
- Sessão **10:45–15:30**, flat ~15:45
- Escada: **+2% → 50%** · **+5% → +25%** · resto soft lock (1 contrato zera no L1)
- SL folgado ATR, teto **5%** · stop diário **10%** · sem teto de trades/dia

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
