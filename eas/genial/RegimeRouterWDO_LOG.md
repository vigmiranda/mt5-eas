# RegimeRouterWDO — legenda (Profit Pro / Genial) v1.05 + viz 1.01

Plataforma: **Profit Pro** · Corretora: **Genial (sim)** · Ativo: **WDO** · TF: **M5**  
Arquivos:
- [`RegimeRouterWDO_v1.ntsl`](RegimeRouterWDO_v1.ntsl) — **execução** (Automação)
- [`RegimeRouterWDO_viz.ntsl`](RegimeRouterWDO_viz.ntsl) — **só visual** (Regra de Coloração) v1.01

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
| 5 | `EnableNYOpen` | **NY** NY Open | Micro-caixa 10:30–10:45: break ou fade |
| 6 | `EnableContBreak` | **CB** ContBreak | Rompe range manhã (até 11:00) |
| 7 | `EnableInsideBreak` | **IB** Inside/Compression | ATR comprimido → rompe lookback |
| 8 | `EnableRetestDay` | **RD** Retest day | Reteste abertura / PDL / PDH |
| 9 | `EnableLunchFade` | **LF** Lunch fade | 12:00–14:00 → VWAP (**off em R2**) |
| 10 | `EnableVwapFade` | **VF** VWAP fade | Extensão vs VWAP (**também em R2**) |

**Sem preço médio / grid.**  
**R2:** OB/LF off · VF on · demais se fit.

---

## Visual / “log pobre” do Profit

Profit **não tem** Experts. Para analisar o dia use **os três** juntos:

1. **Automação** = `RegimeRouterWDO` (ordens) — aba **Eventos** + **Resumo** (Op Totais / Res. Dia).  
2. Gráfico: **Regra de Coloração** = `RegimeRouterWDO_viz` (v1.01) — cor + **texto no candle** (`OB`/`VF`/`R2`/`IDLE`…).  
3. Print no fim do pregão: gráfico com textos + janela Automações (Eventos se houver linhas).

### Cores + PlotText (`RegimeRouterWDO_viz` v1.01)

| Cor | Texto | visMod | Significado |
|-----|-------|--------|-------------|
| Prata | IDLE | 0 | Sem zona clara |
| Aqua | OB | 1 | Janela OB (caixa ok) |
| Azul | AB | 2 | Janela AB / manhã cedo |
| Fúcsia | OF | 3 | Zona OF (ADX baixo manhã) |
| Verde | PB | 4 | Tendência (PB/CB-like) |
| Amarelo | NY | 5 | Janela NY |
| Roxo | LF | 9 | Zona LF (almoço + dist VWAP) |
| Branco | VF | 10 | Zona VF (extensão VWAP) |
| Oliva | R2 | 13 | Dia **R2** sem zona VF |
| Lima | POS | 99 | Conta **com posição** |
| Vermelho | STOP | 11 | STOP DIA |
| Cinza | FLAT | 12 | Após flat / fim sessão |

> A viz **aproxima** a cascata — não é o `lock` da Automação. Ordens reais = Automações / Ordens / Eventos.

### Linhas (viz)

| Plot | Linha | Cor |
|------|-------|-----|
| 1 | EMA rápida | Amarelo |
| 2 | EMA lenta | Azul |
| 3 | VWAP | Branco |
| 4 | `visMod` | Lima |
| 5 | dist à VWAP (ticks) | SkyBlue |

---

## statusCode (`st`) — execução

| st | Significado |
|----|-------------|
| 0 | IDLE |
| 1–10 | Módulo |
| 11 | STOP DIA |
| 12 | Flat fim do dia |
| 13 | R2 sem fit |
| 14 | Teto `MaxTradesDay` |

---

## STOP DIA

- `SeedCapital > 0` → `SeedCapital × StopDiaPct%`  
- Senão → `StopDiaReais`

---

## Ticks

`*Pts` = ticks × `MinPriceIncrement` (≈ **0,5** no WDO).
