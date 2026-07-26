# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## Before exploring, read these

- **`CONTEXT.md`** at the repo root.
- **`CONTEXT-MAP.md`** at the repo root if it exists; read each relevant context.
- **`docs/adr/`**; read ADRs that touch the area being changed.

If these files don't exist, proceed silently. The `/domain-modeling` skill creates them lazily when terms or decisions are resolved.

## File structure

This repository uses the single-context layout:

/
├── CONTEXT.md
├── docs/adr/
└── source directories

## Use the glossary's vocabulary

Use domain terms as defined in `CONTEXT.md`. Don’t drift to synonyms the glossary explicitly avoids.

If a needed concept is absent, reconsider whether it belongs or note the gap for `/domain-modeling`.

## Flag ADR conflicts

If proposed work contradicts an existing ADR, surface the conflict explicitly rather than silently overriding it.
