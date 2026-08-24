---
name: language-specialists
type: stack-module
description: Activates language-specific idiomatic conventions, tooling, and patterns only when the detected language is present in the repo. Includes specialized guidance for Python (django-pro/fastapi-pro), Go, Rust, and TypeScript ecosystems—reducing context waste by binding to the language of the change set.
model: haiku
always_on: false
activation: "ACTIVATE ONLY IF the repo contains a toolchain file for a covered language — pyproject.toml (Python), go.mod (Go), Cargo.toml (Rust), or tsconfig.json (TypeScript). Bind only to the language(s) of the files in the current change set"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

## Language Detection & Binding

Detection is file-based (`pyproject.toml`, `go.mod`, `Cargo.toml`, `tsconfig.json`). There are no
separate specialist files to load — **apply the matching inline specialist section below**:

- **Python** (`pyproject.toml`) → Python Specialist section
- **Go** (`go.mod`) → Go Specialist section
- **Rust** (`Cargo.toml`) → Rust Specialist section
- **TypeScript** (`tsconfig.json`) → TypeScript Specialist section

**Polyglot repos:** one module per language surface being edited — bind to the language of the
files in the current change set, not to every language present in the repo.

---

## Python Specialist (django-pro / fastapi-pro)

**When activated:**
- Use `python -m` for module execution; avoid bare `python` in scripts.
- Respect `pyproject.toml` [project] for versioning; do not edit `__version__` strings manually.
- For async: prefer `asyncio` patterns; flag coroutine leaks.
- Testing: `pytest -xvs` with markers (`@pytest.mark.slow`); never skip coverage gaps without doc comment.
- Linting: run `ruff check .` before commits; use `ruff format .` for style.
- Secrets: `env/<env>.env` (git-ignored) + `env/.env.example` per GLOBAL_PREFERENCES; match the existing repo convention if one exists; never introduce a new one.

---

## Go Specialist (golang-pro)

**When activated:**
- Use `go mod tidy` before commits.
- Idiomatic error handling: check `err != nil` early; return wrapped errors via `fmt.Errorf("context: %w", err)`.
- No `log.Fatal` in libraries; return error from `main()` instead.
- Testing: `go test ./...` with `-race` flag; use `testify/assert` for clarity.
- Linting: run `golangci-lint run` before commits.
- Defer cleanup in reverse order (acquire A → B, defer B cleanup → A cleanup).

---

## Rust Specialist (rust-pro)

**When activated:**
- Respect `Cargo.toml` [workspace] structure; do not manually edit versions (use `cargo add/update`).
- Run `cargo clippy -- -D warnings` before commits; heed all warnings.
- Unsafe blocks: document invariants in a `// SAFETY:` comment; minimize scope.
- Test with `cargo test -- --nocapture` for output; use property-based testing via `proptest` for edge cases.
- Feature gates: document with comments; test both `--no-default-features` and `--all-features`.
- No `unwrap()` in lib code; use `Result<T>` + `?` operator.

---

## TypeScript Specialist (typescript-pro)

**When activated:**
- Type-safety: `strict: true` in `tsconfig.json`; no `any` without `@ts-expect-error` + explanation.
- Linting: ESLint + Prettier; run `npm run lint -- --fix` before commits.
- Testing: Jest or Vitest with `--coverage`; flag untested branches.
- Async: use Promise + async/await; handle rejections with `.catch()` or try/catch in async functions.
- Module exports: prefer named exports; document public API at module top.
- Schemas: use `zod` for runtime validation; derive TS types via `z.infer<typeof>`.

---

## Shared Cross-Language Rules

- **Commits**: Follow the repo's convention. Commit as the repo's own git identity — no `Co-Authored-By: Claude`, no `--author` override (see GLOBAL_PREFERENCES).
- **Secrets**: `env/<env>.env` (git-ignored) per GLOBAL_PREFERENCES; never commit credentials.
- **Tests**: Always run before commits; maintain >80% coverage for new code.
- **Dependencies**: Use lock files (`package-lock.json`, `poetry.lock`, `Cargo.lock`, `go.sum`); commit them.
- **CI/CD**: Respect repo's GitHub Actions/GitLab CI; do not force-push without checking status.
