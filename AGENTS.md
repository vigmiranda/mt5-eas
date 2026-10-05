# Instruções para agentes (Cursor / automação)

Ao trabalhar neste repositório, **sempre** seguir [`REGRAS.md`](REGRAS.md).

Resumo obrigatório:

1. Analisar como **especialista day trader**.
2. **Nunca inferir** — na dúvida, perguntar ao usuário.
3. Objetivo: **meta do dia (~3%) com o menor número de operações** (ideal: 1 trade).
4. Priorizar **mitigar entradas erradas** e **minimizar prejuízo** (não alongar alvo só para compensar).
5. Mudança de **entrada** só com evidência (histórico/planilha/log).
6. **Uma mudança por vez** (entrada **ou** gestão **ou** sizing).
7. Cuidar do **payoff do dia** (dia ruim não pode apagar vários dias de meta).
8. Nova corretora **herda** `REGRAS.md`; só documentar o específico.
9. **Magic/comment únicos** por EA (nunca compartilhar magic).

Regras são **multiplataforma** (Clear, Nomo e futuras). Detalhes por corretora ficam em `eas/clear/`, `eas/nomo/` e no `README.md`.
