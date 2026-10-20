# RegimeRouterWDO — legenda (Profit Pro / Genial) v1.00

Plataforma: **Profit Pro** (Nelogica) · Corretora: **Genial** · Ativo: **WDO** · TF: **M5**  
Linguagem: **NTSL** · Arquivo: [`RegimeRouterWDO_v1.ntsl`](RegimeRouterWDO_v1.ntsl)

Mecânica igual ao RegimeRouterWIN (cascata + lock + flags + STOP DIA), **sem preço médio** no WDO v1.

---

## Cascata

`OB → PB → ContBreak → VwapFade`

| mod | Estratégia | Por que no WDO |
|-----|------------|----------------|
| 1 | **OB** OpenBreak | Rompimento da caixa 09:00–09:15 (abertura B3) |
| 2 | **PB** Pullback | Dia de tendência USD com pullback na EMA |
| 3 | **CB** ContBreak | Trend day sem pullback — rompe range manhã (até 11:00) |
| 4 | **VF** VwapFade | WDO mean-reverte muito à VWAP de sessão |
| — | ~~PM~~ | **Não** no v1 — média/grid no dólar sofre com notícia/gap |

OB sem indício (caixa R2, janela 10:30, flag off, já operou) → libera PB/CB/VF **antes das 11h**.

---

## statusCode (`st=`)

| st | Significado |
|----|-------------|
| 0 | IDLE — sem fit |
| 1 | OB (aguardando / janela) |
| 2 | PB ativo |
| 3 | CB ativo |
| 4 | VF ativo |
| 5 | STOP DIA |
| 6 | FLAT fim do dia |
| 7 | R2 (caixa inválida) |
| 8 | Teto `MaxTradesDay` |

---

## Telinha (PlotText)

```
RR WDO v1 | mod=3 lock=0 st=3 | ver RegimeRouterWDO_LOG.md
dPnL=... STOP=-... t=0/8 OB0 PB0 CB0 VF0 ADX=... cx=...
```

| Campo | Significado |
|-------|-------------|
| `mod` | Módulo da cascata (0–4) |
| `lock` | Dono da posição até flat (0 = livre) |
| `st` | statusCode |
| `dPnL` | Resultado do dia (DailyResult c/ floating) |
| `STOP` | Limite de perda do dia em R$ |
| `t` | Trades / teto |
| `cx` | Tamanho da caixa em ticks |

---

## STOP DIA

1. Se `SeedCapital > 0` → `STOP = SeedCapital × StopDiaPct%`  
2. Senão → `StopDiaReais` (default 250 — **ajuste** ao risco da sim)

---

## Pontos / ticks

Inputs `*Pts` são em **ticks** (`MinPriceIncrement`, tipicamente **0,5** no WDO).  
Ex.: `OB_StopPts(40)` ≈ 40 × 0,5 = **20,0** no preço.
