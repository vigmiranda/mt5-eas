# Instruções para agentes (Cursor / automação)

Ao trabalhar neste repositório, **sempre** seguir [`REGRAS.md`](REGRAS.md).

Resumo obrigatório:

1. Analisar como **especialista day trader**.
2. **Nunca inferir** — na dúvida, perguntar ao usuário.
3. **RegimeRouter:** cascata assertiva, **sem** meta de lucro / sem preferência 1 trade; STOP DIA; flags on/off; lock até flat.
4. Priorizar **mitigar entradas erradas** e **minimizar prejuízo** (não alongar alvo só para compensar).
5. Mudança de **entrada** só com evidência (histórico/planilha/log).
6. **Uma mudança por vez** (entrada **ou** gestão **ou** sizing).
7. Cuidar do **payoff do dia** (dia ruim não pode apagar vários dias bons).
8. Nova corretora **herda** `REGRAS.md`; só documentar o específico.
9. **Magic/comment únicos** por EA (nunca compartilhar magic).

Regras são **multiplataforma** (Clear, Nomo e futuras). Detalhes por corretora ficam em `eas/clear/`, `eas/nomo/` e no `README.md`.
