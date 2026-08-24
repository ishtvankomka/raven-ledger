---
name: design-taste-motion
type: stack-module
description: On-demand visual polish and motion mastery — animation easing, timing, typography, layout refinement, and micro-interaction taste. Vendored design skills (emil-design-eng, review-animations, animation-vocabulary, impeccable, taste-skill) load selectively; load ONE skill per session to preserve context. Trigger only when actively polishing UI or debugging visual/animation quality.
model: haiku
always_on: false
activation: "ACTIVATE ONLY IF building or polishing UI — trigger-loaded, never in the always-on set"
context_cost: high
inherits: ../GLOBAL_PREFERENCES.md
---

## When to Load

- Actively polishing animations, easing curves, or motion timing
- Debugging visual inconsistencies (typography, layout, spacing)
- Refining micro-interactions or state transitions
- Assessing animation vocabulary (spring, bounce, anticipation)
- Fine-tuning a design system or component library for production quality

**Never load the full set at once.** Load ONE skill per session based on the task.

## Available Skills (Vendored)

All in `../skills/design/`. Per-skill index in `MANIFEST.md`, attribution in `ATTRIBUTION.md`.

| Skill | Size | Use When |
|-------|------|----------|
| **emil-design-eng** | 679L | Layout, typography, spacing grids, design fundamentals |
| **review-animations** + STANDARDS.md | 112L + 188L | Animation review, easing, frame-timing, performance |
| **animation-vocabulary** | 173L | Spring/bounce/ease nomenclature, motion language |
| **impeccable** (pbakaus) | 174L | Polish auditing — pixel-perfection, contrast, alignment |
| **taste-skill** (leonxlnx) | 1206L | Landing/portfolio/marketing pages — deep visual taste for final polish |

## Scope Guards

- **taste-skill**: landing pages, portfolios, and marketing sites ONLY — never product UI.
- **Product-UI polish** (dashboards, app screens, components): use emil-design-eng or review-animations.
- **Native mobile** (React Native/Expo): no vendored skill covers it yet — apply only the Motion & Animation Baseline below.
- Invoke emil-design-eng only with a concrete question — never as ambient "make it better" context.

## Arbitration

When skills disagree on motion, the emil-design-eng / review-animations motion doctrine wins.
Always narrow `transition: all` to the explicit properties being animated.

## Load Pattern

```
When user asks for animation or visual polish:
→ Identify the need (easing? typography? micro-interaction?)
→ Load ONE skill from the table above
→ Work in that skill's language
→ Reload only if pivoting to a different category
```

## Motion & Animation Baseline

- **Easing**: cubic-bezier preferred over linear; no abrupt step functions in user-facing interactions
- **Duration**: 200–400ms for UI transitions; 600–1200ms for entrance/exit
- **Delay**: Stagger overlapping animations by 50–100ms increments
- **Frame rate**: Target 60fps; test on lower-end devices
- **Accessibility**: Respect `prefers-reduced-motion`; disable heavy animations on slow connections

## Design System Handoff

- **design-system-engineer** role: defer motion questions to this module
- **frontend-developer** role: ask for taste-skill review before shipping styled-components or Framer Motion builds
- Document easing curves, timing constants, and motion language in design tokens

## Context Management

- Load taste-skill (1206L) only for final-stage visual review of landing/portfolio/marketing pages
- Load review-animations (112L + 188L STANDARDS.md) for easing/timing questions
- Load animation-vocabulary (173L) for nomenclature clarification
- Once work is done, unload to free context
