# Como publicar no GitHub (vigmiranda/nomo-mt5-eas)

## Estrutura atual

- `eas/clear/` — EAs Clear (B3 / WIN)
- `eas/nomo/` — EAs Nomo (forex/CFD)

## Push (com GitHub CLI)

```bash
gh auth login
git push -u origin <branch>
```

Ou PAT com scope `repo` no lugar da senha HTTPS.
