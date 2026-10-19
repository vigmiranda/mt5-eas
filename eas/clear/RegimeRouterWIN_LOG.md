# RegimeRouterWIN — legenda do log (v1.05+)

No Experts do MT5 a coluna **Mensagem** é estreita. Por isso o pulse M5 usa **2 linhas curtas** com prefixo `RR` e abreviações.

Documentação geral do EA: [`README.md`](../../README.md) · regras: [`REGRAS.md`](../../REGRAS.md).

---

## Formato a cada barra M5

```
RR HH:MM | <regime> <módulo> | <decisão> | cx=… ADX=… dPnL=… t=… […]
RR .. | <porque (regimeWhy)> | <último skip ou ação>
```

**Exemplo**

```
RR 18:20 | FORA - | IDLE | cx=1355(R2) ADX=29 dPnL=0 t=0/8 [0|0|0]
RR .. | após flat 16:00 | REGIME R2_EXPLOSIVA -> FORA | ...
```

Outros prefixes:

| Prefixo | Quando aparece |
|---------|----------------|
| `RR init \| …` | Na inicialização do EA |
| `RR ! \| …` | Evento importante (entrada, regime, ciclo PM, etc.) |
| `RR …` / `RR .. \| …` | Pulse periódico (estado + detalhe) |

---

## Regime (`RegimeAbbr`)

| Abrev | Significado |
|-------|-------------|
| `R1` | Abertura OK — caixa válida, OpenBreak elegível |
| `R2` | Abertura explosiva / caixa inválida — sem ORB; PM bloqueado |
| `R3` | Tendência — Pullback elegível |
| `R4` | Lateral — Preço médio elegível |
| `STOP` | STOP DIA ativo (risco do dia) |
| `FORA` | Fora de sessão / sem fit / flat |
| `?` | Desconhecido |

---

## Módulo / estratégia (`ModuleAbbr`)

| Abrev | Estratégia | Flag |
|-------|------------|------|
| `OB` | OpenBreak (abertura) | `InpEnableOpenBreak` |
| `PB` | Pullback (tendência) | `InpEnablePullback` |
| `PM` | Preço médio (lateral) | `InpEnablePrecoMedio` |
| `-` | Nenhum módulo ativo | — |

Cascata: **OB → PB → PM**. Com posição (ou pernas PM), fica em **LOCK** nessa estratégia até flat.

---

## Decisão (3º campo do pulse)

| Abrev | Significado |
|-------|-------------|
| `IDLE` | Cascata sem fit / flags / fora de janela — não opera |
| `WAIT-OB` / `WAIT-PB` / `WAIT-PM` | Módulo ativo, aguardando sinal de entrada |
| `LOCK-OB` / `LOCK-PB` / `LOCK-PM` | Posição (ou ciclo PM) aberta — só gestão, sem outra estratégia |
| `POS` | Em posição (gestão) |
| `MAX` | Atingiu teto de segurança `InpMaxTradesDay` |
| `STOP` | STOP DIA — flat + bloqueio |

---

## Campos da linha 1

| Campo | Significado |
|-------|-------------|
| `cx=1355(R2)` | Tamanho da caixa em pontos + tag: `OK` / `R2` / `…` (montando) |
| `ADX=29` | ADX atual (arredondado) |
| `dPnL=0` | Day PnL em R$ (virtual) |
| `t=0/8` | Trades do dia / teto de segurança |
| `[0\|0\|0]` | Contadores `[OB\|PB\|PM]` (ciclos já usados hoje) |

---

## Telinha do gráfico (`Comment`)

Compacta, mesma ideia de abreviações:

```
RR v1.05 WIN$N | FORA - | -
após flat 16:00
flags OB1 PB1 PM1 | OBabort | cx=1355(R2)
...
```

| Tag | Significado |
|-----|-------------|
| `flags OB1 PB1 PM1` | `1` = ligada, `0` = desligada |
| `LOCK OB` / `PB` / `PM` | Estratégia dona da posição |
| `OBabort` | OpenBreak liberou a cascata B/C |
| `free` | Sem lock e OB ainda não abortou (ou já flat) |
| `HALT` | Dia parado por STOP |

---

## Eventos importantes (`RR !`)

Ações relevantes (entrada, aborto OB, ciclo PM, STOP DIA, etc.) saem em uma linha:

```
RR ! | ENTRADA OB BUY vol=1 @≈... | regime=R1 | ...
RR ! | OB ABORTADO → libera cascata B/C | caixa inválida ...
```

Textos longos são cortados (`...`) para caber na coluna do Experts; o detalhe completo fica na telinha (`act:` / `skip:`) quando couber.
