# Genial · Profit Pro — RegimeRouterWDO

Conta **simulação** Genial · **Profit Pro** · **WDO** M5 · teste ~**1 mês**.

| Arquivo | Uso |
|---------|-----|
| [`RegimeRouterWDO_v1.ntsl`](RegimeRouterWDO_v1.ntsl) | Colar no Editor (v1.02 — ASCII / flags 0|1) |
| [`RegimeRouterWDO_LOG.md`](RegimeRouterWDO_LOG.md) | Legenda mod/st |

---

## Cascata v1.01 (10 módulos, flags ON)

```
OB → AB → OF → PB → NY → CB → IB → RD → LF → VF
```

| # | Módulo | Por que no WDO |
|---|--------|----------------|
| OB | OpenBreak | Abertura B3 |
| AB | Asia/Overnight break | Rompe H/L do dia anterior |
| OF | Overnight Fibo | Fade 50–61,8% do range anterior |
| PB | Pullback | Trend day com correção |
| NY | NY Open | 10:30 BRT — break ou fade da micro-caixa |
| CB | ContBreak | Continuação do range manhã |
| IB | Inside/Compression | Compressão ATR → expansão |
| RD | Retest day | Reteste abertura / extremos do dia |
| LF | Lunch fade | Mean-revert curto 12h–14h |
| VF | VWAP fade | Extensão vs VWAP |

Sem preço médio. Desligue no input o que for mal (**uma flag por vez**).

---

## Instalação (sim · 1 mês)

1. Profit Pro (Genial) → **Editor de Estratégias** → nova execução  
2. Cole `RegimeRouterWDO_v1.ntsl` → **Compilar**  
3. **Automação de Estratégias** → Nova:
   - Conta: **Simulação**
   - Ativo: **WDO** (vencimento atual) · **M5**
   - Qtd por ordem: **1** · Máx posição: **1**
4. Ajuste risco:
   - `SeedCapital` = saldo da sim **ou**
   - `StopDiaReais` ≈ 5% desse saldo
5. Ative e deixe o Profit rodando no pregão.

---

## Checklist do mês

- [ ] Compilou 0 erros  
- [ ] Automação na **sim** (não real)  
- [ ] STOP alinhado ao saldo da sim  
- [ ] Log/telinha: quais `mod` mais entram  
- [ ] Se um módulo sangrar → `Enable* = false`

Regras: [`../../REGRAS.md`](../../REGRAS.md).
