# Genial · Profit Pro — RegimeRouterWDO

Conta **simulação** Genial · **Profit Pro** · **WDO** M5 · teste ~**1 mês**  
(mesma filosofia do `RegimeRouterWIN` na Clear — validar na sim antes de alocar capital real).

| Arquivo | Uso |
|---------|-----|
| [`RegimeRouterWDO_v1.ntsl`](RegimeRouterWDO_v1.ntsl) | Colar no Editor (**v1.04**) |
| [`RegimeRouterWDO_LOG.md`](RegimeRouterWDO_LOG.md) | Legenda mod/st |
| [`RegimeRouterWDO_smoke.ntsl`](RegimeRouterWDO_smoke.ntsl) | Smoke se o editor falhar |

---

## Cascata v1.04 (10 módulos, flags ON)

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

- [ ] Compilou 0 erros (`v1.04` no comentário do script)  
- [ ] Automação na **sim** · **M5** · 1 contrato  
- [ ] STOP alinhado ao saldo da sim  
- [ ] Em dia R2: VF ainda pode entrar se dist/ADX baterem  
- [ ] Se um módulo sangrar → `Enable* = 0` (**uma** flag)

Regras: [`../../REGRAS.md`](../../REGRAS.md).
