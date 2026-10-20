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

## Onde ver o saldo da simulação

1. Fecha o Editor (volta à tela principal do Profit).  
2. Confira no canto da boleta / Chart Trading: conta **S Sim …**.  
3. Embaixo, aba **Custódia** (ou **Day Trade**): olhe **Saldo** / **Patrimônio** / **Líquido**.  
4. Alternativa: menu **Negociação** → opções de conta / financeiro da sim.

Anota esse valor e usa em `SeedCapital` (ou 5% dele em `StopDiaReais`).

## Instalação (sim · 1 mês)

1. Profit Pro (Genial) → **Editor de Estratégias** → nova execução  
2. Cole o raw da main (texto puro, sem HTML):  
   `https://raw.githubusercontent.com/vigmiranda/mt5-eas/main/eas/genial/RegimeRouterWDO_v1.ntsl`  
3. **Compilar** (se falhar, teste antes o smoke: `RegimeRouterWDO_smoke.ntsl`)  
4. **Automação de Estratégias** → Nova:
   - Conta: **Simulação**
   - Ativo: **WDO** (vencimento atual) · **M5**
   - Qtd por ordem: **1** · Máx posição: **1**
5. `SeedCapital` = saldo da sim **ou** `StopDiaReais` ≈ 5%  
6. Ative e deixe o Profit aberto no pregão.

**Nota v1.03:** `VWAP` no Profit exige parâmetro — usamos `VWAP(1)` (diário).

---

## Checklist do mês

- [ ] Compilou 0 erros  
- [ ] Automação na **sim** (não real)  
- [ ] STOP alinhado ao saldo da sim  
- [ ] Log/telinha: quais `mod` mais entram  
- [ ] Se um módulo sangrar → `Enable* = false`

Regras: [`../../REGRAS.md`](../../REGRAS.md).
