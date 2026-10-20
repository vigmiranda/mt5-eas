# Genial · Profit Pro — RegimeRouterWDO

Conta de **simulação** Genial Investimentos no **Profit Pro** (Nelogica), ativo **WDO** M5.

Objetivo: rodar **~1 mês** em conta teste, mesma mecânica do RegimeRouterWIN (cascata + lock + flags + STOP DIA), com estratégias que fazem sentido no dólar.

| Arquivo | Uso |
|---------|-----|
| [`RegimeRouterWDO_v1.ntsl`](RegimeRouterWDO_v1.ntsl) | Colar no Editor de Estratégias |
| [`RegimeRouterWDO_LOG.md`](RegimeRouterWDO_LOG.md) | Legenda `mod` / `st` / telinha |

---

## Cascata WDO (v1.00)

`OpenBreak → Pullback → ContBreak → VwapFade`

- **Sem preço médio** no v1 (WDO + notícia USD / gap).
- Flags todas **ON** — desligue no input se for mal.
- STOP DIA: `SeedCapital×5%` **ou** `StopDiaReais` se semente = 0.

---

## Instalação (sim Genial · 1 mês)

1. Abra o **Profit Pro** logado na Genial (conta **simulação**).
2. Menu **Estratégias → Editor de Estratégias → Nova estratégia de execução**.
3. Cole o conteúdo de `RegimeRouterWDO_v1.ntsl` → **Compilar** (0 erros).
4. Salve com nome `RegimeRouterWDO_v1`.
5. **Estratégias → Automação de Estratégias → Nova Automação**:
   - Conta: **Simulação**
   - Estratégia: `RegimeRouterWDO_v1`
   - Ativo: **WDO$** / vencimento atual (ex. WDOX25)
   - Periodicidade: **5 minutos**
   - Quantidade por ordem: **1** (comece assim)
   - Quantidade máx. posição: **1**
6. Aba **Risco** (recomendado): alinhar stop diário da automação com o do robô (ou um pouco mais folgado).
7. **Ativar** a automação e deixar o Profit aberto no pregão (ou PC estável).

### Ajustes obrigatórios antes do mês

| Input | O que fazer |
|-------|-------------|
| `SeedCapital` | Saldo da sim Genial em R$ (se souber) |
| `StopDiaReais` | Se `SeedCapital=0`, defina o STOP em R$ (ex. 5% do saldo sim) |
| Quantidade | 1 mini no primeiro mês |

> **Não inventamos o saldo da sua sim.** Sem `SeedCapital`, o freio usa `StopDiaReais` — ajuste esse valor.

---

## Checklist do mês de teste

- [ ] Compilou sem erro no Editor  
- [ ] Automação na **simulação** (não real)  
- [ ] WDO M5 + 1 contrato  
- [ ] STOP configurado (`SeedCapital` ou `StopDiaReais`)  
- [ ] Anotar por dia: trades OB/PB/CB/VF, dayPnL, se STOP bateu  
- [ ] Se um módulo for mal → flag `Enable*` = false (uma mudança por vez)

---

## Notas Profit / Genial

- Automação em **simulação** no Profit Pro costuma ser **gratuita**; conta real exige módulo pago.
- PC precisa permanecer com Profit + automação ativos no horário do pregão.
- Day trade WDO: flat padrão **17:50** (`FlatHora`).

Regras do projeto: [`../../REGRAS.md`](../../REGRAS.md).
