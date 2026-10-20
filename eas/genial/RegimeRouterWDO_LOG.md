# RegimeRouterWDO — legenda (Profit Pro / Genial) v1.02

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
| 9 | `EnableLunchFade` | **LF** Lunch fade | 12:00–14:00 fade curto à VWAP |
| 10 | `EnableVwapFade` | **VF** VWAP fade | Extensão vs VWAP (resto do dia) |

**Sem preço médio / grid** no WDO.  
**Filtro WIN×WDO** ainda não (multiativo no NTSL — candidata v1.02).

Lock: `lock=mod` até flat. OB aborta cedo → libera AB…VF.

---

## statusCode (`st`)

| st | Significado |
|----|-------------|
| 0 | IDLE |
| 1–10 | Módulo correspondente (tabela acima) |
| 5* | Também usado como STOP DIA quando `st=5` e sem posição NY — ver telinha `STOP` |
| 6 | FLAT fim do dia |
| 7 | R2 caixa inválida |
| 8 | Teto `MaxTradesDay` |

> Em lock, `mod`/`lock` mostram o dono; `dPnL` e `STOP=-` mostram o freio do dia.

---

## Telinha

```
RR WDO v1.01 | mod=5 lock=0 st=5
dPnL=... STOP=-... t=0/12 ADX=... cx=...
OB0 AB0 OF0 PB0 NY0 CB0 IB0 RD0 LF0 VF0
```

---

## STOP DIA

- `SeedCapital > 0` → `SeedCapital × StopDiaPct%`  
- Senão → `StopDiaReais` (**ajuste** ao saldo da sim Genial)

---

## Ticks

`*Pts` = ticks × `MinPriceIncrement` (≈ **0,5** no WDO).
