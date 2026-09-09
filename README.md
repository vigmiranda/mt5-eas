# Nomo MT5 — Expert Advisors

Coleção de EAs (Expert Advisors) para operação automatizada na **Nomo (MetaTrader 5)**.

## Layout operacional

| Par      | Timeframe | EA                 | Magic  | Versão |
|----------|-----------|--------------------|--------|--------|
| EURUSD   | M30       | TrendEURUSD_v1     | 260828 | 1.20   |
| XRPUSD   | M30       | TrendXRPUSD_v1     | 300831 | 1.40   |
| DOGEUSD  | M30       | TrendMeme_Pct_v1   | 310901 | 1.10   |
| BTCUSD   | H1        | TrendBTCUSD_v1     | 310903 | 1.10   |
| WTIUSD   | H1        | TrendWTIUSD_v1     | 310902 | 1.10   |
| NMAI     | H1        | NMAI_BuyDip_v1     | 310904 | 1.00   |
| USDJPY   | M5        | ScalpUSDJPY_v1     | 260829 | 1.30   |

## Instalação

1. Copie os arquivos `.mq5` de `eas/` para:
   `MetaTrader 5/MQL5/Experts/`
2. Abra o **MetaEditor**, compile cada EA (**F7** → 0 erros).
3. No gráfico correto (par + timeframe): arraste o EA compilado.
4. Ative **Permitir algotrading** e confirme o botão verde no terminal.
5. Verifique o log **Experts** na inicialização (versão e parâmetros).

## Proteção de lucro (soft lock)

Os Trend **EUR, XRP, BTC e WTI** usam duas fases:

1. **Soft lock** — lucro ≥ `SoftLockStart` → SL = entrada + `SoftLockPts`
2. **Trailing completo** — lucro ≥ `TrailStart` → SL segue o preço

O **TrendEURUSD v1.20** usa EMA 50/200 + ADX + SL/TP por ATR (soft lock em frações de ATR).

O **TrendMeme (DOGE)** também usa soft lock em **% do preço** (spread alto ~5%):

- Soft lock: lucro ≥ 12% → SL = entrada + 5%
- Trailing: lucro ≥ 25% → SL segue o preço (lock 12%)

O **NMAI (BuyDip)** é só BUY, **1 posição**, **sem TP**: soft lock progressivo sobe com o lucro; ao fechar, espera novo dip.

## Estrutura

```
eas/
  TrendEURUSD_v1.mq5    # Trend forex v1.20: EMA50/200 + ADX + ATR + soft lock
  TrendXRPUSD_v1.mq5    # Trend crypto, soft lock v1.40
  TrendBTCUSD_v1.mq5    # Trend BTC H1, spread ~2900 pts, soft lock v1.10
  TrendWTIUSD_v1.mq5    # Trend petróleo, soft lock v1.10
  TrendMeme_Pct_v1.mq5  # DOGE, soft lock + trailing em %
  NMAI_BuyDip_v1.mq5    # NMAI H1, só BUY, 1 pos, sem TP, soft lock sobe
  ScalpUSDJPY_v1.mq5    # Scalp JPY, trailing em degraus
  archive/              # EAs legados (não usados no layout atual)
```

## Aviso

Estes EAs são ferramentas de automação. Teste em demo antes de usar em conta real. Parâmetros de spread/stop variam entre demo e produção — especialmente **XRP** e **DOGE**.
