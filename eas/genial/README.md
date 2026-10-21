# Genial · Profit Pro — RegimeRouterWDO

Conta **simulação** Genial · **Profit Pro** · **WDO** M5 · teste ~**1 mês**  
(mesma filosofia do `RegimeRouterWIN` na Clear — validar na sim antes de alocar capital real).

| Arquivo | Uso |
|---------|-----|
| [`RegimeRouterWDO_v1.ntsl`](RegimeRouterWDO_v1.ntsl) | **Execução** — Automação (**v1.05**) |
| [`RegimeRouterWDO_viz.ntsl`](RegimeRouterWDO_viz.ntsl) | **Só visual** v1.02 — cor + PlotText no candle (sem ordens) |
| [`RegimeRouterWDO_LOG.md`](RegimeRouterWDO_LOG.md) | Legenda mod/st + cores |
| [`RegimeRouterWDO_smoke.ntsl`](RegimeRouterWDO_smoke.ntsl) | Smoke se o editor falhar |

---

## Cascata v1.05 (10 módulos, flags ON)

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
Não afrouxamos MaxBox / ADX / candle — só liberamos **VF** no buraco de regime (igual WIN v1.07).

Sem preço médio. Desligue no input o que for mal (**uma flag por vez**).

---

## Visual / análise no Profit (sem Experts)

Profit não tem log tipo MT5. Para **analisar** o dia:

1. Automação = **`RegimeRouterWDO`** (ordens) — olhe aba **Eventos** + Op Totais / Res. Dia.  
2. Compila **`RegimeRouterWDO_viz`** v1.02 (raw GitHub, texto puro).  
3. Gráfico WDO M5 → **Inserir Regra de Coloração** → `RegimeRouterWDO_viz`.  
4. No candle aparece texto (`OB`/`VF`/`R2`/`IDLE`…) + cor.  
5. **Não** use o script de execução como coloração.  
6. Fim do pregão: print do gráfico **e** da Automação (Eventos) — isso é o “log” do WDO.

Legenda: [`RegimeRouterWDO_LOG.md`](RegimeRouterWDO_LOG.md).

## Ops (sem afrouxar regra)

- Automação sempre em **WDO M5** (não M1).
- Conta **Sim** até fechar o mês de validação.
- Qtd **1** / máx posição **1**.

## Onde ver o saldo da simulação

1. Fecha o Editor (volta à tela principal do Profit).  
2. Confira no canto da boleta / Chart Trading: conta **S Sim …**.  
3. Embaixo, aba **Custódia** (ou **Day Trade**): olhe **Saldo** / **Patrimônio** / **Líquido** / **Total**.  
4. Alternativa: menu **Negociação** → opções de conta / financeiro da sim.

Anota esse valor → `SeedCapital` **ou** 5% dele em `StopDiaReais`.

Quando for migrar parte do capital Clear → Genial: `SeedCapital` = valor alocado na Genial e `StopDiaPct = 5`.

## Instalação (sim · 1 mês)

1. Profit Pro (Genial) → **Editor de Estratégias** → nova execução  
2. Cole o raw da main (texto puro, sem HTML):  
   `https://raw.githubusercontent.com/vigmiranda/mt5-eas/main/eas/genial/RegimeRouterWDO_v1.ntsl`  
3. **Compilar** (se falhar, teste o smoke)  
4. **Automação de Estratégias** → Nova:
   - Conta: **Simulação**
   - Ativo: **WDO** (vencimento atual) · **M5**
   - Qtd por ordem: **1** · Máx posição: **1**
5. `SeedCapital` = saldo da sim **ou** `StopDiaReais` ≈ 5%  
6. Ative e deixe o Profit aberto no pregão.

**Nota:** `VWAP` no Profit exige parâmetro — usamos `VWAP(1)` (diário).

---

## Checklist do mês

- [ ] Compilou execução `v1.05` + viz  
- [ ] Automação na **sim** · **M5** · 1 contrato  
- [ ] Regra de coloração `RegimeRouterWDO_viz` no gráfico  
- [ ] STOP alinhado ao saldo da sim  
- [ ] Em dia R2: VF ainda pode entrar se dist/ADX baterem  
- [ ] Se um módulo sangrar → `Enable* = 0` (**uma** flag)

Regras: [`../../REGRAS.md`](../../REGRAS.md).
