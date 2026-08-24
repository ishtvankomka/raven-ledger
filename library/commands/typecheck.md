---
name: typecheck
description: Run TypeScript type checking (tsc --noEmit or turbo run typecheck) to validate type correctness without building. Reports errors grouped by file as the fast correctness gate before shipping code.
allowed-tools: Read, Grep, Glob, Bash
model: haiku
source: project command (promoted to generic)
always_on: false
activation: "repo contains tsconfig.json"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

## Detect & Run

1. **Check for turbo.json** → if present and has typecheck task, use `turbo run typecheck`
2. **Fallback to tsc** → if no turbo, use `tsc --noEmit` from repo root
3. **Parse stderr** for errors; if none found, report "✓ All types valid"

## Report Format

- **Group errors by file path**
- **Per-file summary**: line:col message
- **Show first 15 errors max** (truncate with "... N more errors in this file")
- If multiple files affected, list file names in order before details

## Error Modes

| Condition | Action |
|-----------|--------|
| Command not found (tsc/turbo) | "Install dependencies: `npm install` or check PATH" |
| tsconfig.json missing | "No tsconfig.json found; skipping typecheck" |
| Only warnings | Report warnings, treat as pass |
| 0 errors | Success message: "Type check passed" |

## Example Output

```
typecheck: 3 files with errors

dist/index.ts (2 errors)
  12:4   TS2339: Property 'foo' does not exist on type 'Bar'
  45:8   TS2304: Cannot find name 'Missing'

src/main.ts (1 error)
  8:15  TS1005: ',' expected
```

## Notes

- Run from repo root (pwd check)
- Silent on zero errors
- No build artifacts generated (--noEmit flag)
- Times out after 30s
