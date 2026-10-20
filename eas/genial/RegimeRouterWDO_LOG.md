# RegimeRouterWDO — legenda (Profit Pro / Genial) v1.04

Plataforma: **Profit Pro** · Corretora: **Genial (sim)** · Ativo: **WDO** · TF: **M5**  
Arquivo: [`RegimeRouterWDO_v1.ntsl`](RegimeRouterWDO_v1.ntsl)

---

## Cascata (ordem)

```
OB → AB → OF → PB → NY → CB → IB → RD → LF → VF
```

| mod | Flag | Estratégia | Ideia |
|-----|------|------------|-------|
| 1 | `EnableOpenBreak` | **OB** OpenBreak | Rompe caixa 09:00–09:15 B3 |
| 2 | `EnableAsiaBreak` | **AB** Asia/Overnight break | Rompe H/L do **dia anterior** |
| 3 | `EnableOvernightFibo` | **OF** Overnight Fibo | Fade na zona 50–61,8% do range anterior → meio |
| 4 | `EnablePullback` | **PB** Pullback | Tendência + pullback EMA |
| 5 | `EnableNYOpen` | **NY** NY Open | Micro-caixa 10:30–10:45: break (ADX alto) ou fade (ADX baixo) |
| 6 | `EnableContBreak` | **CB** ContBreak | Rompe range manhã (até 11:00) com tendência |
| 7 | `EnableInsideBreak` | **IB** Inside/Compression | ATR comprimido → rompe lookback |
| 8 | `EnableRetestDay` | **RD** Retest day | Reteste abertura / PDL / PDH com rejeição |
| 9 | `EnableLunchFade` | **LF** Lunch fade | 12:00–14:00 fade curto à VWAP (**bloqueado em R2**) |
| 10 | `EnableVwapFade` | **VF** VWAP fade | Extensão vs VWAP (**também em R2**, v1.04) |

**Sem preço médio / grid** no WDO.

**R2** = caixa fora de `[BoxMinPts–BoxMaxPts]` → OB off; LF off; **VF on** (mesmos `VF_MinDistPts` / `VF_ADXMax`).  
AB / OF / PB / NY / CB / IB / RD seguem se fit (não dependem de R2).

Lock: `lock=mod` até flat. OB aborta cedo → libera AB…VF.

---

## statusCode (`st`)

| st | Significado |
|----|-------------|
| 0 | IDLE |
| 1–10 | Módulo correspondente (tabela acima) |
| 13 | R2 — cascata sem fit (PM-style hole; VF/PB/… não bateram) |
| 14 | Teto `MaxTradesDay` |

Em lock, `mod`/`lock` mostram o dono.

---

## STOP DIA

- `SeedCapital > 0` → `SeedCapital × StopDiaPct%`  
- Senão → `StopDiaReais` (**ajuste** ao saldo da sim Genial)

Migração futura Clear → Genial: gravar o capital alocado em `SeedCapital`.

---

## Ticks

`*Pts` = ticks × `MinPriceIncrement` (≈ **0,5** no WDO).

---

## Ops

Automação no gráfico/período **M5** (não M1). Não afrouxa MaxBox / ADX / candle — só remove o bloqueio de regime do VF em R2 (DNA do WIN v1.07).
