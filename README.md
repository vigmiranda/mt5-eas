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
| WINV26 / WIN$ | M5 | **ScalpWIN_v2** | 260917 | 2.08 | Daytrade escada % (recomendado) |
| WINV26 / WIN$ | M5 | ScalpWIN_v1 | 260916 | 1.02 | Scalp TP/ATR (referência) |
| WINV26 / WIN$ | M5 | TrendWIN_v1 | 260914 | 1.11 | Tendência (referência) |

**ScalpWIN_v2** (preferido)
- Rompimento M5 + EMA/ADX (entrada seletiva)
- **Capital virtual (Clear):** semente **R$850** + PnL novo − taxas (~R$0,25/lado)
- **Faixas:** R$500–1500 → 1 · R$1500–2500 → 2 · …
- **Filtros v2.06:** ADX ≥ 18, corpo ≥ 0,25×ATR, rompimento 3 barras, volume ≥ 0,85× média
- Sessão **10:30–15:45**, flat **16:00**
- Inputs renomeados no v2.05 para o MT5 **não reaproveitar** valores antigos salvos no gráfico
- Histórico: `MQL5/Files/ScalpWIN_v2_equity.csv`
- Escada: **+2% → 50%** · **+5% → +25%** · resto soft lock (1 contrato zera no L1)
- SL folgado ATR, teto **5%** · **STOP DIA 10%** (pode flat) · **META DIA +3%** (só bloqueia novas entradas; posição aberta segue escada/soft lock) · sem teto de trades/dia

Instalação: copie `eas/clear/ScalpWIN_v2.mq5` → `MQL5/Experts/`, compile (F7). **Remova** o EA do gráfico e arraste de novo (não use .set antigo). Log: `v2.08`, `metaDia=3.0%`, `seed=R$850`.

**ScalpWIN_v1** / **TrendWIN_v1**: referências anteriores.

---

## Nomo (layout recomendado)

| Par | Timeframe | EA | Magic | Versão | Papel |
|-----|-----------|----|-------|--------|-------|
| USDJPY | M5 | **ScalpUSDJPY_v3** | 260831 | 3.02 | Daytrade escada % (port ScalpWIN) |
| EURUSD | M30 | TrendEURUSD_v1 | 260828 | 1.22 | Trend filtrado |
| USDJPY | M5 | ScalpUSDJPY_v2 | 260830 | 2.01 | Daytrade seletivo (referência) |

**ScalpUSDJPY_v3** (preferido na Nomo)
- Lógica ScalpWIN (escada + META/STOP) com **filtros mais duros no FX** (v3.02)
- Entrada: rompimento **5** barras · ADX ≥ **25** · corpo ≥ **0,45×ATR** · volume ≥ média
- Sessão **12:00–17:00** (overlap Londres/NY) · **só seg–sex** · flat **20:50**
- Máx. **4** trades/dia · risco **0,30%** · STOP DIA **5%** · META DIA **3%** · SL **1,8×ATR**
- Magic **260831** · inputs renomeados no v3.02 (não reaproveita .set antigo)

Instalação: copie `eas/nomo/ScalpUSDJPY_v3.mq5` → `MQL5/Experts/`, compile (F7). Gráfico **USDJPY M5**. **Remova** e arraste de novo. Log: `v3.02`, `dias=seg-sex`, `ADX>=25.0`, `sessao 12:00-17:00`.

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
    ScalpUSDJPY_v3.mq5    # Nomo / USDJPY escada % (recomendado)
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
