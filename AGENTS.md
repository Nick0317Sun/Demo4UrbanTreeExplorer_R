# R Urban Tree Explorer — project rules

## Environment
- Use only the current Docker/dev container environment.
- Use /usr/bin/R only.
- Do not create or use conda environments.
- Do not assume native Windows R for this project.

## Project root
- Repository root in container: /workspaces/R_UrbanTreeExplorer

## Primary spec
- The authoritative product specification is:
  docs/R_UrbanTreeExplorer_Codex_Spec.md
- Read that file before making architecture or UI decisions.

## Scope
- Build the R-first Shiny urban tree explorer.
- Focus on visualization first.
- Data Assistant remains placeholder-only in V1.

## Constraints
- Do not continue the old React/FastAPI path as the main implementation.
- Do not build a complex dashboard.
- Do not expose explicit hex-click analysis in V1.
- Prefer preprocessed runtime data over raw CSV reads at interaction time.

## Working style
- Propose a short plan before major changes.
- Implement in small verifiable phases.
- After each phase, explain what was created, how to run it, and what remains.