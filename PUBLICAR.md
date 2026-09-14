# Como publicar no GitHub (vigmiranda/mt5-eas)

> Repo renomeado de `nomo-mt5-eas` → `mt5-eas`. Pastas `eas/nomo/` e `eas/clear/` continuam (corretoras).

## Estrutura atual

- `eas/clear/` — EAs Clear (B3 / WIN)
- `eas/nomo/` — EAs Nomo (forex/CFD)

## Renomear no GitHub (uma vez)

1. Abra https://github.com/vigmiranda/nomo-mt5-eas/settings
2. **Repository name** → `mt5-eas` → **Rename**
3. Atualize o remote local:

```bash
git remote set-url origin https://github.com/vigmiranda/mt5-eas.git
```

O GitHub redireciona a URL antiga por um tempo; o remote novo evita confusão.

## Push (com GitHub CLI)

```bash
gh auth login
git push -u origin <branch>
```

Ou PAT com scope `repo` no lugar da senha HTTPS.
