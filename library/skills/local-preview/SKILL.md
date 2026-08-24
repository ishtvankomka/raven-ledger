---
name: local-preview
description: >-
  Run the frontend locally against a REMOTE shared backend so any change with a visible effect
  can be looked at before it is pushed — the split-stack preview setup. Covers building the
  internal packages the app imports, pointing both the browser-side and server-side API base
  URLs at the remote environment (there is no private network on a laptop), starting the app
  through the harness's launch configuration rather than a stray terminal process, and the fact
  that forms hit a real database. Use whenever a change alters UI, a flow, or copy — whoever
  asked for it.
always_on: false
activation: "before pushing any change with a visible effect; when previewing a frontend locally against a shared remote backend"
context_cost: low
---

# Preview locally before you push

The rule: **a change with a visible effect gets looked at in a running app before it is pushed.**
Not typechecked, not reasoned about — opened, and clicked.

The cheapest way to honour it on a split stack is to run only the frontend locally and leave the
backend and database remote. You get the real API, the real data shapes, and none of the setup
cost — at the price of the caveats at the bottom, which are real.

## Steps

1. **Install dependencies** at the repo root, with the repo's package manager.

2. **Build the internal packages the app imports.** In a workspace repo the app resolves a
   first-party package from its *built* output, not its source. A stale build is the single most
   common cause of "the types are wrong but the code is right", and of an import that exists in
   the editor and fails at runtime. Build them before starting the app, and again after touching
   them.

3. **Make sure the environment file exists** (copy the committed example if not), and point the
   API base URLs at the remote environment:

   ```
   <PUBLIC_API_BASE_URL>=https://<remote-api-host>/<api-prefix>
   <SERVER_API_BASE_URL>=https://<remote-api-host>/<api-prefix>
   ```

   Both, and both public. Deployed, the server-side variable usually names a private/internal
   hostname that only resolves inside the hosting network — **on a laptop there is no private
   network**, so an internal hostname produces server-side fetch failures that look like an API
   outage. Swap it for the public host locally.

4. **Start it through the harness's preview/launch configuration**, not a raw backgrounded
   terminal command. That gives a live preview pane, a managed process, and logs you can read.
   If no launch configuration exists, create one:

   ```json
   {
     "version": "0.0.1",
     "configurations": [
       {
         "name": "web",
         "runtimeExecutable": "<package-manager>",
         "runtimeArgs": ["<the app's dev script invocation>"],
         "port": 3000
       }
     ]
   }
   ```

5. **Open the page the change affects and use it.** Loading it is not verification:

   - Click the thing. Submit the form. Open the menu. A render that never had its handler wired
     looks identical to one that works.
   - Check **every theme** the app ships (light and dark), not just the one you have open.
   - Check **every locale** the change touches — a copy change in one catalog strands the others.
   - Check the states the design skipped: loading, empty, error, and any gated/paywalled variant.
   - Check the narrow viewport if the change is layout-bearing.

6. **Only then** commit and push.

## Caveats of pointing a local frontend at a shared backend

- **Writes are real.** Any form you submit writes a real row in the shared environment, sends a
  real email, and may charge a real (test-mode) payment. Use obviously fake input, and say in
  your report what you created so it can be cleaned up.
- **You are testing against someone else's data.** A row you did not create can change what you
  see between two runs; do not chase a "bug" that is really another session's state.
- **Never point local at production** to preview a change. Staging or an equivalent pre-production
  environment only.

## When the change also touches the backend

Run the backend locally too and repoint the server-side base URL at it
(`http://localhost:<api-port>/<api-prefix>`). At that point the database is the only remote
piece, and every rule about which database you are connected to applies — state the target
environment out loud before any request that writes.

## Afterwards

Stop the dev server when you are done rather than leaving an orphaned process holding the port —
the next session's "port already in use" is this session's fault. Report what you actually
looked at: which pages, which themes, which locales, which interactions — not "previewed
locally".
