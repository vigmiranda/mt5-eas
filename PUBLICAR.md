# Como publicar no GitHub (vigmiranda/mt5-eas)

Repo: https://github.com/vigmiranda/mt5-eas  
(antes: `nomo-mt5-eas`; pastas `eas/nomo/` e `eas/clear/` continuam — são as corretoras)

## Estrutura atual

- `eas/clear/` — EAs Clear (B3 / WIN)
- `eas/nomo/` — EAs Nomo (forex/CFD)

## Remote local

Se o clone ainda aponta para o nome antigo:

```bash
git remote set-url origin https://github.com/vigmiranda/mt5-eas.git
git remote -v
```

## Push (com GitHub CLI)

```bash
gh auth login
git push -u origin <branch>
```

Ou PAT com scope `repo` no lugar da senha HTTPS.
