---
name: nestjs-prisma-postgres
type: stack-module
description: NestJS + Prisma API patterns for monorepos (Turborepo/npm or pnpm workspaces) with shared Postgres. Covers schema changes, migrations, validation layer alignment (Zod/class-validator), shared DTO packages, and safe DB mutations via CONFIRM gate. Activates only on repos with apps/api NestJS + Prisma + shared Postgres.
model: haiku
always_on: false
activation: "ACTIVATE ONLY IF the repo has apps/api on NestJS AND a Prisma schema AND a shared Postgres"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

## Workspace Detection

- **Turborepo + npm**: Root `turbo.json`, `packages/` dirs, `npm workspaces` in package.json.
- **pnpm workspaces**: `pnpm-workspace.yaml` at root; `"workspaces"` in root package.json.
- Detect early; adjust path patterns (`packages/` vs `apps/` vs custom layout).

## Shared Postgres & Migrations

- Single Postgres instance shared by all apps (not per-app databases).
- All schema changes via `prisma migrate dev --name <name>` in `apps/api` workspace.
- **Migration workflow**: 
  - Edit `prisma/schema.prisma` in `apps/api`.
  - Run `prisma migrate dev` (creates `/prisma/migrations/` folder).
  - Commit migration file + schema change together.
  - Other apps consume the updated schema via their Prisma client (auto-generated on `npm install` or `pnpm install`).
- CI applies pending migrations before tests/deploy: `prisma migrate deploy`.

## Shared DTOs & Validation

- **DTO packages**: `@scope/shared` (or similar) exports Zod schemas + TypeScript types OR class-validator decorated classes.
- **Pattern detection**: 
  - If `@scope/shared` has `.zod.ts` or `z.ZodType` → Zod-first validation.
  - If services use `class-validator` decorators (`@IsString()`, etc.) → class-validator alignment.
- Match the repo's choice; do not mix validators across DTOs.
- Shared UI (`@scope/ui`) is read-only for API context; styles/components do not affect backend logic.

## API Route & Service Structure

```
apps/api/src/
  (shared-modules)  # e.g., database, config
  resources/
    users/          # domain
      dto/          # @scope/shared exports imported here
      users.controller.ts
      users.service.ts
    posts/
      ...
```

- Services depend on Prisma client (`PrismaService`).
- DTOs imported from `@scope/shared`; validation in controller or guard.
- No business logic in controllers; keep services testable.

## Database Mutations: CONFIRM Gate

- **All runtime mutations** (inserts, updates, deletes in production-like envs) require explicit CONFIRM gate.
- Safe (reversible) operations: reads, SELECT queries, schema exploration, dev/test writes.
- Irreversible/remote-state: production data modification, production DB connection changes.
- Example CONFIRM prompt:  
  ```
  Mutating production database: DELETE FROM users WHERE ...
  Target: <db host>/<database>
  Proceed? (type CONFIRM)
  ```
- Never auto-execute mutations without CONFIRM; never remove confirmation for destructive DB ops.

## Secrets & Environment

- Source of truth: `env/<env>.env` (git-ignored) + committed `env/.env.example`, per GLOBAL_PREFERENCES — holds `DATABASE_URL`, API keys, Prisma client config.
- `.env`/`.env.local`: match the existing repo convention if one exists; never introduce a new one.
- Never commit env files to git; never instruct removal of `.gitignore` rules for secrets.
- Use `process.env.DATABASE_URL` or load via `ConfigService` (NestJS).
- CI/deploy: inject via environment variables or secret manager (GitHub Actions Secrets, etc.).

## Debugging & Inspection

- Prisma Studio: `npx prisma studio` (opens GUI at `http://localhost:5555`).
- Generated Prisma client: `node_modules/.prisma/client/` (auto-generated, never edit).
- Schema validation: `prisma format`, `prisma validate`.
- Query logs: Enable `log: ["query"]` in Prisma client config for SQL visibility.

## Common Patterns

| Task | Command/Path |
|------|--------------|
| Add schema field | Edit `apps/api/prisma/schema.prisma` → `prisma migrate dev` |
| Run tests | `npm test` or `pnpm test` (workspace-aware) |
| Lint API | `npm run lint --workspace=@scope/api` or `pnpm lint -F @scope/api` |
| Generate Prisma client | `prisma generate` (auto on `npm install`) |
| Check pending migrations | `prisma migrate status` |

## Non-Negotiable Constraints

- Do not commit `.env` or secrets to git.
- Do not disable migration validation or audit tooling.
- Do not force-execute production DB mutations without CONFIRM.
- Do not mix Zod + class-validator in the same DTO package; match the repo's pattern.
- Reversible actions (dev writes, reads, schema exploration) = full autonomy.
- Irreversible actions (prod mutations, state changes) = one CONFIRM gate.
