# Genial · Profit Pro — RegimeRouterWDO

Conta **simulação** Genial · **Profit Pro** · **WDO** M5 · teste ~**1 mês**  
(mesma filosofia do `RegimeRouterWIN` na Clear — validar na sim antes de alocar capital real).

| Arquivo | Uso |
|---------|-----|
| [`RegimeRouterWDO_v1.ntsl`](RegimeRouterWDO_v1.ntsl) | **Execução** — Automação (**v1.09** + VF≥10:00 em R2 + sizing + OB BE/trail + `ConsoleLog`) |
| [`RegimeRouterWDO_viz.ntsl`](RegimeRouterWDO_viz.ntsl) | **Só visual** v1.02 — cor + PlotText no candle (sem ordens) |
| [`RegimeRouterWDO_LOG.md`](RegimeRouterWDO_LOG.md) | Legenda mod/st + cores |
| [`RegimeRouterWDO_smoke.ntsl`](RegimeRouterWDO_smoke.ntsl) | Smoke se o editor falhar |

---

## Cascata v1.09 (10 módulos, flags ON)

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
| LF | Lunch fade | Mean-revert curto 12h–14h (**off em R2**) |
| VF | VWAP fade | Extensão vs VWAP (**também em R2**, v1.04) |

**R2** = caixa 09:00–09:15 fora de `[BoxMinPts–BoxMaxPts]` → OB abortado.  
Não afrouxamos MaxBox / ADX / candle — liberamos **VF** no buraco de regime **só após 10:00** (`VF_R2Start`, igual WIN v1.11).

Sem preço médio. Desligue no input o que for mal (**uma flag por vez**).

---

## Visual / análise no Profit (sem Experts)

Profit não tem log tipo MT5. Para **analisar** o dia:

1. Automação = **`RegimeRouterWDO` v1.09** — aba **Eventos** recebe `ConsoleLog` (`RR …` a cada M5, tipo Experts). OB: BE+trail; VF em R2 só ≥10:00; sizing por `SeedCapital`. Se der erro de sintaxe em `ConsoleLog`, Profit antigo: atualize ou `EnableConsoleLog=0`.  
2. Compila **`RegimeRouterWDO_viz`** v1.02 (raw GitHub, texto puro).  
3. Gráfico WDO M5 → **Inserir Regra de Coloração** → `RegimeRouterWDO_viz`.  
4. No candle aparece texto (`OB`/`VF`/`R2`/`IDLE`…) + cor.  
5. **Não** use o script de execução como coloração.  
6. Fim do pregão: print do gráfico **e** da Automação (Eventos) — isso é o “log” do WDO.

Legenda: [`RegimeRouterWDO_LOG.md`](RegimeRouterWDO_LOG.md).

## Ops (sem afrouxar regra)

- Automação sempre em **WDO M5** (não M1).
- Conta **Sim** até fechar o mês de validação.
- **Máx posição ≥ 3** (teto do sizing). A Qtd da automação pode ficar 1 — o código manda `BuyAtMarket(n)`.

### Sizing (v1.08) — igual WIN, via `SeedCapital`

O NTSL **não lê** o saldo da Genial. Por isso o capital é o input `SeedCapital` (+ `DailyResult` no dia):

| Capital efetivo | Contratos |
|-----------------|-----------|
| &lt; R$5.000 | 1 |
| ≥ R$5.000 | 2 |
| ≥ R$8.000 | 3 (`MaxLots`) |

- `SizingByCapital=0` → usa só `FixedLots`
- `SeedCapital=0` → cai em `FixedLots` (e STOP usa `StopDiaReais`)

## Onde ver o saldo da simulação

1. Fecha o Editor (volta à tela principal do Profit).  
2. Confira no canto da boleta / Chart Trading: conta **S Sim …**.  
3. Embaixo, aba **Custódia** (ou **Day Trade**): olhe **Saldo** / **Patrimônio** / **Líquido** / **Total**.  
4. Alternativa: menu **Negociação** → opções de conta / financeiro da sim.

Anota esse valor → `SeedCapital` (sizing + STOP 5%) **ou** só `StopDiaReais` se preferir lote fixo.

Quando for migrar parte do capital Clear → Genial: `SeedCapital` = valor alocado na Genial e `StopDiaPct = 5`.

## Instalação (sim · 1 mês)

1. Profit Pro (Genial) → **Editor de Estratégias** → nova execução  
2. Cole o raw da main (texto puro, sem HTML):  
   `https://raw.githubusercontent.com/vigmiranda/mt5-eas/main/eas/genial/RegimeRouterWDO_v1.ntsl`  
3. **Compilar** (se falhar, teste o smoke)  
4. **Automação de Estratégias** → Nova:
   - Conta: **Simulação**
   - Ativo: **WDO** (vencimento atual) · **M5**
   - Qtd por ordem: **1** · Máx posição: **3** (permite as faixas)
5. `SeedCapital` = saldo da sim (obrigatório p/ sizing 1/2/3)  
6. Ative e deixe o Profit aberto no pregão.

**Nota:** `VWAP` no Profit exige parâmetro — usamos `VWAP(1)` (diário).

---

## Checklist do mês

- [ ] Compilou execução `v1.09` + viz  
- [ ] Automação na **sim** · **M5** · máx posição **3** · `SeedCapital` preenchido  
- [ ] Regra de coloração `RegimeRouterWDO_viz` no gráfico  
- [ ] STOP + sizing alinhados ao saldo da sim (`SeedCapital`)  
- [ ] Em dia R2: VF ainda pode entrar se dist/ADX baterem  
- [ ] Se um módulo sangrar → `Enable* = 0` (**uma** flag)

Regras: [`../../REGRAS.md`](../../REGRAS.md).
