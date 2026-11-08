# Household Platform development instructions

## Design standard

For any frontend, user experience, dashboard, data presentation, or integration work, **read and follow [docs/DESIGN_STANDARD.md](docs/DESIGN_STANDARD.md)**. It is the adopted Household Platform Design Standard v1.0, not an optional suggestion.

Apply these defaults:
- Intelligent simplicity: show purposeful information, no redundant fields or routine explanatory clutter.
- Professional, compact, dark-first, expressive and accessible.
- Persistent sidebar and consistent platform navigation; use contextual side-panel editing.
- Aggressive automation for predictable tasks; reserve confirmation for destructive or high-impact changes.
- Hybrid saving, quiet success, prominent and actionable errors, and reversible ordinary changes.
- Smart customizable tables, quick filters with expandable advanced options, analytics-first dashboards and drill-down charts.
- Shared design tokens/components and consistent patterns across Finance, Maintenance, Properties and future modules.
- AI-assisted reports through controlled components and read-only reporting interfaces, not arbitrary execution.

Before changing UI, check the acceptance checklist in section 14. Keep financial calculations, permissions, imported originals, reconciliation and audit history correct. Do not change production financial data solely to implement a visual preference.

## Repository workflow

The owner prefers direct commits to `main` for routine low-stakes changes, rather than draft pull requests. Run available tests/build checks and report failures accurately. Database migrations and security-sensitive operations still require careful verification. Never put private household records or secrets into this public repository.
