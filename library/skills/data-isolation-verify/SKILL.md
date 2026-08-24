---
name: data-isolation-verify
description: >-
  Prove that database-enforced data isolation still holds on a live database — that the
  restricted schema holding sensitive data is unreachable by the application's least-privilege
  role, denied by the engine's own grants rather than by application code. Run after ANY schema
  change, migration, grant change, role change, or new table, against the environment that
  changed. Use when a project separates sensitive data (personal data, tenant data, financial
  records) into its own schema with its own role, and when adding tables to such a database.
always_on: false
activation: "after any migration, grant change, role change, or new table on a database that enforces schema-level isolation"
context_cost: low
keywords: "data isolation, row level access, pii separation, grants"

---

# Verify database-enforced isolation

The pattern this verifies: **sensitive rows live in their own schema, and the role the
application normally runs as has no grant that reaches them.** The everyday code path physically
cannot read them; a separate, narrowly-scoped role and code path handles the cases that must.

The point of the pattern is that it is enforced by the database engine, not by a `if
(user.canSee)` branch that a refactor can delete. The point of *this skill* is that grants are
invisible state — nothing in the diff tells you a migration or a `GRANT` widened them. So you
check, on the live database, every time the schema or the roles move.

## Vocabulary used below

| Placeholder | Meaning |
|---|---|
| `<restricted>` | the schema holding sensitive data |
| `<open>` | the ordinary application schema (often `public`) |
| `<app-role>` | the least-privilege role the app runs as by default |
| `<privileged-role>` | the narrow role allowed into `<restricted>` |
| `<migrator-role>` | the role that owns DDL and grants |

Each role has its own connection URL. Keep them as separate environment variables — a single
"the database URL" is how the app ends up connecting as the migrator and the whole invariant
evaporates.

## Run it against the environment that changed

Connecting from a workstation to a managed database: use the provider's **public/proxy host**.
Internal-only hostnames resolve only from inside the platform's network and will look like an
outage.

Keep the checks in a script in the repo (e.g. `infra/db/verify-isolation.sh`) so the same six
run identically in CI, on a laptop, and after an incident. All six must pass; a partial pass is
a fail.

### 1 — The restricted schema exists and holds what it should

```sql
SELECT table_name FROM information_schema.tables WHERE table_schema = '<restricted>';
```

Cross-check against the model definitions. Then the inverse, which is the one people skip: scan
`<open>` for columns that look sensitive (email, phone, name, address, document, national id,
raw file names) and confirm each is deliberate.

### 2 — The privileged role CAN read it

```sql
-- as <privileged-role>
SELECT count(*) FROM <restricted>.<a-table>;
```

This check exists to prove the harness is talking to a live database with real grants. Without
it, a broken connection string makes every other check "pass" by failing.

### 3 — The app role CANNOT read it

```sql
-- as <app-role>; must ERROR, SQLSTATE 42501 insufficient_privilege
SELECT 1 FROM <restricted>.<a-table> LIMIT 1;
```

Assert on the **error code**, not on message text, and assert on the statement's own exit status.
Piping a query through `head` or `grep ... | something` masks the failure — check the exit code
of the command that actually ran.

### 4 — A cross-schema join fails the same way

```sql
-- as <app-role>; must ERROR with the same 42501
SELECT o.id FROM <open>.<a-table> o JOIN <restricted>.<a-table> r ON r.id = o.<fk>;
```

Denial must not depend on the shape of the query. A join is the query a well-meaning feature
actually writes.

### 5 — A table added tomorrow is denied too

Table-level revocation is not the invariant; **schema-level `USAGE` is**. Without it, a new table
created with default grants can be readable the moment it exists.

```sql
SELECT has_schema_privilege('<app-role>', '<restricted>', 'USAGE');   -- expect false
```

And confirm default privileges do not re-open it:

```sql
SELECT defaclobjtype, defaclacl FROM pg_default_acl d
JOIN pg_namespace n ON n.oid = d.defaclnamespace WHERE n.nspname = '<restricted>';
```

### 6 — No route back in through the open schema

The three classic leaks, each of which passes checks 3-5 untouched:

```sql
-- views in the open schema that read the restricted one
SELECT schemaname, viewname FROM pg_views
WHERE schemaname <> '<restricted>' AND definition ILIKE '%<restricted>.%';

-- SECURITY DEFINER functions: they run with the owner's rights, not the caller's
SELECT n.nspname, p.proname FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE p.prosecdef AND n.nspname NOT IN ('pg_catalog','information_schema');

-- foreign tables / materialized views pointing at restricted data
SELECT foreign_table_schema, foreign_table_name FROM information_schema.foreign_tables;
```

Anything found here must be justified in the repo, or removed.

## If a check fails

**Do not ship.** Re-apply the grant bootstrap — keep it as one **idempotent** SQL file in the
repo so recovery is a single command and not an archaeology session:

```bash
psql "$<MIGRATOR_URL>" -v ON_ERROR_STOP=1 -f infra/db/bootstrap-grants.sql
```

Then re-run all six. If it still fails, something structural changed — a role was recreated, a
schema was dropped and remade, ownership moved. Find what, and when, before any deploy. A
failing isolation check is never "flaky".

## When adding tables

- **Classify first.** Anything identifying a person, or scoped to one tenant's confidentiality,
  goes in `<restricted>` with the schema named explicitly in the model. Everything else goes in
  `<open>`.
- **Qualify the schema in the migration SQL.** The generated statement must read
  `CREATE TABLE "<restricted>"."<table>"`. If the table name is unqualified, **stop** — it will
  be created wherever `search_path` resolves, which is almost always `<open>`, and the invariant
  breaks silently with a green migration.
- **Index every foreign key explicitly.** Several ORMs do not create an index for a declared
  relation on Postgres; the missing index only shows up as a slow join under real data.
- Access to `<restricted>` goes through one dedicated module using the privileged connection.
  Never import that client from anywhere else — one import is the whole invariant.
- Re-run this skill after the migration lands, on the environment it landed in.
