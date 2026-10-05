# Regras do projeto (multiplataforma)

Estas regras valem para **qualquer corretora/plataforma** (Clear, Nomo ou futuras) e para qualquer EA deste repositório.  
Mudanças de código, parâmetros e análises devem respeitá-las.

---

## 1. Papel de especialista day trader

Toda análise do que vamos implementar, ajustar ou descartar deve ser feita no **papel de especialista em day trade**:

- Priorizar qualidade de entrada, gestão de risco e expectativa (não só win rate).
- Evitar heurísticas fracas sem evidência (histórico, planilha, logs).
- Separar o que é regra de negócio do que é detalhe da corretora (magic, fees, fuso, símbolo).

## 2. Nunca inferir — na dúvida, perguntar

- **Não inventar** intenção, saldo, meta, horário, sizing ou comportamento do broker.
- Se faltar contexto (print, log, valor Clear/Nomo, preferência de risco): **perguntar** antes de implementar.
- Não “completar” requisitos ambíguos com suposições silenciosas.

## 3. Meta do dia com o menor número de operações

- Objetivo operacional: **bater a meta do dia** (hoje **+3%**) com **o menor número de trades possível**.
- Ideal atual: **1 operação** buscando os **~3%** (quando o mercado permitir com qualidade).
- Mais trades só quando necessário para a meta — nunca operar por operar.
- Escada/parciais existem para **proteger** e realizar, não para incentivar overtrade.

## 4. Mitigar erro de entrada e minimizar prejuízo

- Análises e mudanças devem mirar primeiro: **menos entradas ruins**.
- Em seguida: **prejuízo máximo menor** (STOP DIA, SL coerente, cooldown, filtros).
- Subir alvo de lucro **não** é o caminho preferido se isso aumenta exposição/tempo na operação.
- Preferir seletividade (menos sinais, melhores) a “compensar” loss com mais operações.

## 5. Mudança de entrada com evidência

- Apertar ou afrouxar filtro de entrada só com base em **histórico, planilha ou logs**.
- Um trade isolado (bom ou ruim) **não** basta para mudar regra de entrada.

## 6. Uma mudança por vez

- Em cada ciclo: alterar **entrada** **ou** **gestão** **ou** **sizing** — não os três juntos.
- Misturar mudanças impede saber o que melhorou (ou piorou) a assertividade / meta.

## 7. Payoff do dia

- Um dia negativo **não pode** anular vários dias de meta.
- STOP DIA, SL e volume devem ser coerentes com o capital: perda típica de um dia ruim ≤ ~1–1,5× um dia de meta.

## 8. Corretora nova herda estas regras

- Clear, Nomo ou qualquer plataforma futura **herdam** este documento por padrão.
- Só documentar o que for específico da corretora (pasta, magic, fees, fuso, símbolo, capital virtual).

## 9. Magic e comment únicos por EA

- Cada EA tem **magic** e **comment** próprios.
- Dois EAs no mesmo magic misturam histórico, A/B e gestão — **proibido**.

---

## Princípios já adotados (reforço)

Valem em todas as plataformas, salvo exceção explícita acordada:

| Princípio | Descrição |
|-----------|-----------|
| Sem grid / sem martingale | No máximo **1 posição** por EA/magic |
| META DIA | Só com conta **flat** + lucro **realizado** |
| STOP DIA | Inclui floating; protege o dia |
| DNA compartilhado | Risco/meta/escada podem ser iguais; **entrada** pode variar por ativo |
| Capital virtual | Quando o broker não reporta saldo confiável (ex.: Clear), semente alinhada ao saldo real |
| Evidência | Mudança relevante vem de histórico/planilha/log — não de feeling isolado |

---

## Como usar no dia a dia

1. Antes de propor código: reler estas regras.  
2. Em PRs/commits: se a mudança afeta entrada, meta ou risco, citar qual regra motiva.  
3. Novas corretoras: **herdam** este documento; só documentar o que for específico (pasta, magic, fees, sessão).

Atualizações neste arquivo só com acordo explícito.
