---
name: paas-deploy-check
description: >-
  Verify a push actually reached its domain on a managed container PaaS — the layer where a
  green build still leaves a dead service. Checks CI for your commit, each service's deployment
  status per environment, then the public domain, and names the failure modes unique to this
  hosting shape: a SUCCESS build that 502s because a required variable is missing, a monorepo
  built from the wrong directory, and a custom domain returning 404 because only half its DNS
  records exist. Use after every push to a PaaS-hosted environment. Pairs with
  agents/deploy-verifier.md, which owns proving the live bundle itself changed.
always_on: false
activation: "after pushing to a managed container PaaS with per-service deployments and custom domains"
context_cost: low
---

# Verify a PaaS deploy end to end

On a managed container PaaS, "deployed" has three independent meanings and each can be true
while the next is false:

1. **CI passed** — your commit compiles and its tests ran.
2. **The platform says the deployment SUCCEEDED** — the image built and the container started.
3. **The domain serves the change** — DNS, TLS, routing, and a process that is still alive.

Check all three, in order, every time. Skipping straight to the domain hides *why* it is broken;
stopping at the platform status is how "it's deployed" becomes a support ticket.

> Scope: this skill covers the platform and DNS layers. Proving that the code the browser
> receives actually changed — bundle-hash capture, marker greps, the `grep | head` exit-code
> trap — belongs to `agents/deploy-verifier.md`. Do not restate it here; run it after step 3
> when the change must be visible in a client bundle.

## 1 — CI, for **your** commit

Check the run attached to the SHA you pushed, not the newest run in the list; on a busy branch
those differ, and "CI is green" about someone else's commit is worthless.

```bash
<vcs-cli> run list --limit 5           # find the run for your SHA
<vcs-cli> run view <id> --log-failed   # only when it is red
```

## 2 — Each service's latest deployment, per environment

A PaaS deploys **per service**, and a push commonly rebuilds several. Check every service the
change touches, in the environment you pushed to.

```bash
<platform-cli> deployment list --service <service> --environment <env>
```

The latest must read `SUCCESS`. Then the rule people learn the hard way:

**A SUCCESS build only means the image built and the process started.** A container that starts,
fails its own configuration validation, and exits still reports a successful build while the
domain returns 502. Read the service logs:

```bash
<platform-cli> logs --service <service> --environment <env>
```

## 3 — The domain

Take the public URL for each surface from the repo's own configuration or the platform's domain
settings — never from memory — and check the status code, plus a health endpoint for API
services:

```bash
curl -s -o /dev/null -w '%{http_code}\n' <url>
```

Expect 200 on every surface. For a user-visible change, also confirm the change itself is
present: fetch the page and grep for something the change introduces, testing grep's own exit
code (`grep -q`) rather than a piped result.

**Never poll a public domain in a loop** while waiting for a build — repeated requests trip bot
protection and you end up debugging a challenge page. Poll the platform API; hit the domain once,
at the end.

## Failure modes specific to this hosting shape

- **502 right after a SUCCESS deployment.** The process crashed at boot. Almost always a required
  environment variable that is missing or invalid in that environment — a fail-fast config
  validator names it in the first lines of the log. Set it on the service and redeploy; do not
  "fix" it by weakening the validator.
- **An internal package fails to resolve during the build** (unresolved workspace import,
  module-not-found on a first-party package). The build ran from a subdirectory instead of the
  repo root, so the workspace was never installed — or the image's ignore file was weakened and a
  host `node_modules` leaked in, shadowing the real install. Check the configured build root and
  the ignore file before touching code.
- **A custom domain 404s while the platform URL works.** The domain's DNS is half-configured.
  These platforms typically need *both* the routing record (CNAME/ALIAS) *and* a verification or
  certificate TXT record; with the TXT missing the routing record still resolves, so the failure
  is a silent 404 rather than an error anyone notices.
- **A hostname that only resolves inside the platform network.** Internal service hostnames are
  unreachable from a laptop and from CI. Use the public host for anything checked from outside.
- **Environment drift.** A variable set in one environment and not the other produces a change
  that works in staging and 502s in production. When a deploy adds a variable, check the other
  environments before promoting.

## Definition of done

Report each, with the value you actually observed:

1. The SHA you pushed, and the CI conclusion **for that SHA**.
2. Every service checked, its environment, and its latest deployment status.
3. The status code from each public surface, plus the health endpoint.
4. For a visible change: the marker you grepped for and its exit code.
5. Anything you could not check, named explicitly.

If any layer is red, fix it and re-check before reporting done. "It should be live" is not a
result.
