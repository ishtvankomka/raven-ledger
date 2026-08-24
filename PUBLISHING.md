# Publishing Raven Ledger

How this repo becomes something other people can run for themselves. The model is
**sync-only**: the toolset is inseparable from its capture → `/promote` → distribute
loop, so there is no plugin build and no marketplace. People create their own copy
of the whole repo (template, not fork) and run their own ledger.

## One-time setup

1. **Rename the GitHub repo** from `claude-collection` to `raven-ledger` (GitHub →
   Settings → rename; old URLs redirect). Then update the local remote:

   ```bash
   git remote set-url origin ishtvan_personal:ishtvankomka/raven-ledger
   ```

2. **Arm the private-name gate before going public.** Create
   `sync/private-names.txt` with one client/project term per line (it stays out of
   git) and run `sync/validate-library.sh` — until that file exists, no client name
   has ever actually been checked for.

3. **Push the squashed history.** The first push after the history rewrite replaces
   what's on the remote:

   ```bash
   git push --force-with-lease origin main --tags
   ```

4. **Make the repo public and mark it as a template**: Settings → check
   **Template repository**. This is what turns the visitor's button into
   "Use this template".

5. *(Optional)* Settings → Social preview → upload the logo
   (`assets/logo.svg`), and add GitHub topics (`claude-code`, `claude`,
   `ai-tooling`, `developer-tools`) so the repo is findable.

## How people adopt it

They click **Use this template** → create their own copy — private allowed, which
is the whole reason this is a template and not a fork model: forks of a public repo
can never be private, and a person's `incoming/` staging and curated library belong
to them. Then, in their clone:

```bash
sync/install-project.sh /path/to/their/project
```

and paste `library/INSTALL_PROMPT.md` into a Claude Code session at that project.
Their copy never reports back to this one. To receive future improvements they add
this repo as an `upstream` remote once — the mesh then nudges them at session start
when it has new commits, and `sync/upstream-check.sh --merge` applies them.

## Releasing a new version

Versioning is git tags plus `CHANGELOG.md` — there is no separate artifact version.

```bash
sync/validate-library.sh          # contract check over library/
sync/build-index.sh               # refresh the router index
# add a CHANGELOG.md entry, then:
git add -A && git commit -m "release: vX.Y.Z"
git tag -a vX.Y.Z -m "Raven Ledger X.Y.Z"
git push origin main --tags
```

People on their own copies pick releases up whenever they merge from `upstream` —
there is nothing to bump on your side beyond the tag.
