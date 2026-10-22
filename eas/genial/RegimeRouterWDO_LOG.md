# RegimeRouterWDO — legenda (Profit Pro / Genial) v1.07 + viz 1.02

Plataforma: **Profit Pro** · Corretora: **Genial (sim)** · Ativo: **WDO** · TF: **M5**  
Arquivos:
- [`RegimeRouterWDO_v1.ntsl`](RegimeRouterWDO_v1.ntsl) — **execução** (Automação) v1.07 — `ConsoleLog` + OB BE/trail
- [`RegimeRouterWDO_viz.ntsl`](RegimeRouterWDO_viz.ntsl) — **só visual** (Regra de Coloração) v1.02

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

1. **Automação** = `RegimeRouterWDO` v1.07 — aba **Eventos** com linhas `RR …` (`ConsoleLog`, a cada M5).  
2. Gráfico: **Regra de Coloração** = `RegimeRouterWDO_viz` — cor + texto no candle.  
3. **Resumo**: Op Totais / Res. Dia.  

### ConsoleLog (Eventos) — v1.07

| Prefixo | Quando |
|---------|--------|
| `RR HHMM \| mod=… st=… cx=… ADX=…` | Pulse a cada barra M5 |
| `RR … \| R2 IDLE \| …` | Dia R2 sem módulo |
| `RR … \| LOCK mod=…` | Posição aberta |
| `RR … \| STOP \| …` | STOP DIA |
| `RR ! ENTRADA mod=…` | Acabou de travar um módulo |
| `RR ! OB BE SL@…` | OpenBreak: stop no break-even |
| `RR ! OB TRAIL slMoves=… tpAdv=…` | OpenBreak: trail SL; TP +1 a cada 2 SL |

### OB gestão (v1.07) — só módulo 1

| Input | Default | Papel |
|-------|---------|-------|
| `OB_EnableTrail` | 1 | Liga BE+trail no OB |
| `OB_BE_Pts` | 25 | Pts a favor → SL na entrada |
| `OB_TrailStepPts` | 10 | Passo de trail do SL (e do TP quando avança) |
| `OB_TP_MaxPts` | 100 | Teto do TP em pts a partir da entrada |

Fluxo: BE conta como 1ª subida do SL → depois cada passo de trail. **TP só avança 1 passo a cada 2 subidas do SL.** Demais módulos (AB…VF) seguem SL/TP fixos.

`mod` 1–10 = OB…VF (mesma tabela). Se o Editor não compilar `ConsoleLog`, o Profit é antigo demais — atualize o app ou desligue `EnableConsoleLog`.

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
