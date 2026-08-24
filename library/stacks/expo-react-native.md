---
name: expo-react-native
type: stack-module
description: 'Expo / React Native app work: EAS builds, prebuild semantics, push notifications, monorepo React-version alignment, and the rule that pinned versions and reference builds are declared by the project, never assumed.'
model: haiku
always_on: false
activation: "ACTIVATE IF the repo contains an Expo project (app.json/app.config.* with an expo key, or eas.json)"
context_cost: low
inherits: ../GLOBAL_PREFERENCES.md
---

## Read the project's pins first

Never assume versions or a reference build. Read `app.json`/`app.config.*`, `eas.json`, and
`package.json` and work to what they declare. Three things a project may pin, each of which changes
what is a bug and what is intentional:

- **SDK / runtime pins** — Expo SDK, React Native, and React versions. A version that looks old is
  usually a deliberate pin (native-module compatibility, a store submission window). Do not
  "modernize" it without an explicit request.
- **Peer-dependency escape hatches** — `legacy-peer-deps`/`--force` in `.npmrc` or the install
  script. In a monorepo where web and mobile sit on different React majors this is expected, not a
  defect. Verify the intent before removing it; the fix for a real conflict is aligning the
  consumer's React version, not silencing the resolver everywhere.
- **Reference builds** — some repos keep a pinned previous implementation (often gitignored) as the
  behavioral source of truth. Read it to confirm expected behavior; never "unify" it with the
  current app on your own initiative.

## Builds & prebuild

- Local dev: `expo start`; clear a stale bundler cache with `expo start -c`.
- Cloud builds: `eas build` per platform, driven by the profiles in `eas.json`.
- `expo prebuild` generates `ios/` and `android/` — these are **build artifacts, not source**.
  When they are gitignored, keep them gitignored and regenerate; never commit them, and never
  hand-edit generated native code (the change is lost on the next prebuild — change the config
  plugin instead).
- Prebuild failing: clear the Xcode/Gradle caches, then `expo prebuild --clean`.
- EAS build hanging: check EAS account permissions and the linked Apple/Play developer accounts
  before touching app code.

## Push notifications

- Device token via `expo-notifications`; delivery through the Expo push service.
- Credentials live in the EAS account and `eas.json` — never inline a credential in app source and
  never print a token value into a log or a report.
- Test on a real device build: push does not work in a simulator.

## Monorepo conventions

- The Expo app is one workspace; shared packages must resolve to the React version the app uses —
  a duplicated React in the mobile bundle produces hook errors that look like app bugs.
- Metro needs to be told about workspace roots in a monorepo; when imports resolve in the editor but
  fail at runtime, suspect the Metro resolver config before the code.

## Guardrails

- Never loosen a `.gitignore` rule covering native folders, reference builds, or credentials.
- Version pins, peer-dep escape hatches, and reference builds are project decisions: confirm before
  changing one, and state what you verified.
- Generic testing and performance guidance lives in `agents/test-automator.md` and
  `agents/performance-engineer.md` — this module only adds the Expo-specific mechanics.
