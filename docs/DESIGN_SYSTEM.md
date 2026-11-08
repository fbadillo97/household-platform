# Household Platform — Design System v1.0

**Status:** Initial implementation · 2026-11-08  
**Reference:** [Design Standard v1.0](DESIGN_STANDARD.md)

## Implementation

The platform's semantic design variables and shared visual rules are in [`src/design-system.css`](../src/design-system.css). It is loaded *after* `src/style.css` in `src/main.jsx` as an incremental migration layer. New components should use the semantic tokens below instead of copying hard-coded colours from legacy CSS.

### Semantic tokens

| Token | Purpose |
|---|---|
| `--hp-bg` | Application background |
| `--hp-sidebar` | Sidebar and recessed input backgrounds |
| `--hp-surface` | Panels and main content surfaces |
| `--hp-surface-raised` | Elevated cards and secondary surfaces |
| `--hp-surface-hover` | Interactive hover and selection surfaces |
| `--hp-text` | Primary high-contrast text |
| `--hp-muted` | Supporting labels and descriptions |
| `--hp-subtle` | Low-priority metadata |
| `--hp-border` | Dividers and control outlines |
| `--hp-accent` / `--hp-accent-strong` / `--hp-accent-tint` | Primary action and selection |
| `--hp-positive` / `--hp-negative` / `--hp-warning` / `--hp-danger` | Semantic states |
| `--hp-violet` | Secondary analytics series |
| `--hp-focus` | Visible keyboard focus |
| `--hp-radius` / `--hp-radius-lg` | Rounded corners |
| `--hp-space-1` through `--hp-space-5` | Reusable compact spacing scale |

Dark mode is the authoritative initial theme. Any future light mode should override the *same* semantic tokens rather than creating a second parallel set of per-component styles.

### Layout

- `platform-layout`: desktop two-column workspace with 216px persistent sidebar.
- `platform-sidebar`: vertical module navigation, compact identity, active state and accessible nav.
- `platform-workspace`: fluid content area, constrained to 1900px maximum for very wide screens.
- Under 900px the sidebar narrows; under 700px it becomes a compact horizontal navigation band.
- Existing hash routes and page identities remain unchanged.

### Reusable patterns

- `.panel`: content surface for forms, reports and dashboards.
- `.cards` and `.worth-cards`: compact analytics cards with semantic data accents.
- `table`, `.ledger-table`: compact tabular display with tabular numerals.
- `.secondary`, `.text-button`, `.danger`: semantic action variants.
- `.transaction-dialog`, `.account-dialog`: contextual right-side detail panel.
- `.error`: prominent actionable failure notice.
- `.transaction-filters`: expandable advanced filtering.
- `.history-*`, `.worth-*`: existing analysis widgets with shared dark styling.

### Boundaries and next increments

This is **the foundation of the design system**, not a full UX rewrite. It does not change financial data, API contracts, access rules, transactions, reconciliation, or the current editing/saving model.

Future work should:
1. Extract shared React primitives (buttons, cards, inputs, side panels and empty states) when existing patterns are stable.
2. Migrate legacy `src/style.css` selectors progressively into token-aware component styles and remove duplicate declarations.
3. Apply side-panel editing, hybrid save and contextual controls where existing features still diverge from the adopted standard.
4. Build chart palette and reusable chart/metric components for future modules.
5. Add actual accessible visual-regression checks for dark desktop and mobile layouts.

No new application module should independently invent its own colour palette, spacing scale or navigation pattern.

## Refined Finance patterns

The compact scale now includes font-size, control-height and chart-series tokens.
`src/components/ui.jsx` supplies Panel, SectionHeading, InlineNotice, EmptyState
and MetricCard; dashboard activity metrics and ledger feedback use these primitives.
The persistent platform sidebar remains the desktop navigation anchor.

Transactions uses a 520px contextual panel with a sticky heading. A lone category
change autosaves through the revision-checked API; if other fields are dirty,
the whole draft requires explicit Save. Failed saves retain the draft and expose
Reload details with discard protection. Routine save success is quiet. Existing
linked pairs retain priority over category defaults. Matching controls appear
for movement categories or existing links, never ordinary purchases.

Search/month/review are quick filters; amount/date/category/account/tag and
accounting scope remain under Advanced filters. Column visibility is stored only
as an allowlisted set of column names in browser localStorage, with a safe fallback
when storage is unavailable. No household data or search terms are persisted.
Description and amount remain visible. Sorting and 50-row server pagination are
unchanged. Category bars drill into the ledger while retaining account/month.

The browser fixture loads the same dark stylesheet as production. Desktop/mobile
checks cover accessibility, overflow, saving conflicts, draft recovery, column
preferences, category drill-down and modal keyboard behavior using fabricated data.
No database migration, production record update or authorization change is part
of this refinement. Column ordering/width, saved views and deeper legacy CSS
migration remain future increments.
