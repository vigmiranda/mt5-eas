# Nomo MT5 — Expert Advisors

Coleção de EAs (Expert Advisors) para operação automatizada na **Nomo (MetaTrader 5)**.

## Layout recomendado (atual)

| Par      | Timeframe | EA                 | Magic  | Versão | Papel |
|----------|-----------|--------------------|--------|--------|-------|
| EURUSD   | M30       | TrendEURUSD_v1     | 260828 | 1.22   | Trend filtrado |
| USDJPY   | M5        | ScalpUSDJPY_v2     | 260830 | 2.01   | Daytrade seletivo |

Demais EAs ficam no repo para referência; use com cautela (crypto/spread).

## Layout completo no repositório

| Par      | Timeframe | EA                 | Magic  | Versão |
|----------|-----------|--------------------|--------|--------|
| EURUSD   | M30       | TrendEURUSD_v1     | 260828 | 1.22   |
| USDJPY   | M5        | ScalpUSDJPY_v2     | 260830 | 2.01   |
| XRPUSD   | M30       | TrendXRPUSD_v1     | 300831 | 1.40   |
| DOGEUSD  | M30       | TrendMeme_Pct_v1   | 310901 | 1.10   |
| BTCUSD   | H1        | TrendBTCUSD_v1     | 310903 | 1.10   |
| WTIUSD   | H1        | TrendWTIUSD_v1     | 310902 | 1.10   |
| NMAI     | H1        | NMAI_BuyDip_v1     | 310904 | 1.00   |

## Instalação

1. Copie os arquivos `.mq5` de `eas/` para:
   `MetaTrader 5/MQL5/Experts/`
2. Abra o **MetaEditor**, compile cada EA (**F7** → 0 erros).
3. No gráfico correto (par + timeframe): arraste o EA compilado.
4. Ative **Permitir algotrading** e confirme o botão verde no terminal.
5. Verifique o log **Experts** na inicialização (versão e parâmetros).

## Proteção de lucro (soft lock)

**TrendEURUSD v1.22** e **ScalpUSDJPY v2.01**: EMA 50/200 + ADX + SL por ATR, **sem TP**. Soft lock mais folgado (arma mais tarde; trail mais longe do preço).

**ScalpUSDJPY v2** extras (daytrade):
- ADX ≥ 25, risco 0,30%, 1 posição, máx. 6 trades/dia
- Sessão 08h–17h (horário do servidor)
- Flat perto do rollover

## Estrutura

```
eas/
  TrendEURUSD_v1.mq5    # Trend forex v1.22 (soft lock folgado)
  ScalpUSDJPY_v2.mq5    # Daytrade JPY v2.01 (soft lock folgado)
  TrendXRPUSD_v1.mq5
  TrendBTCUSD_v1.mq5
  TrendWTIUSD_v1.mq5
  TrendMeme_Pct_v1.mq5
  NMAI_BuyDip_v1.mq5
  archive/              # ScalpUSDJPY_v1 e outros legados
```

## Aviso

Estes EAs são ferramentas de automação. Teste em demo antes de usar em conta real. Parâmetros de spread/stop variam entre demo e produção — especialmente **XRP** e **DOGE**.
