# Household Platform — Design Standard v1.0

**Status:** Adopted · 2026-11-08  
**Scope:** Household Finance, Home Maintenance, Properties, Documents, and future platform applications.

## 1. Design philosophy

**Intelligent simplicity:** Present useful information clearly, automate predictable work, and reveal complexity only when necessary.

The platform should feel like one professional application rather than a collection of unrelated tools.

### Core principles

1. **Purpose over decoration.** Every visible element should convey useful information, enable an action, or clarify an important state.
2. **Automate by default.** Infer predictable values and behaviours rather than requiring redundant user input.
3. **Context over clutter.** Show controls when they become relevant.
4. **Quiet success.** Routine successful operations should not interrupt the user.
5. **Analytics over activity.** Prioritize meaningful measurements, trends, comparisons, and relationships.
6. **Consistency without rigidity.** Share platform-wide design patterns while allowing each module to meet its specific needs.
7. **Recoverability.** Prefer reversible actions, reliable history, and explicit handling of consequential changes.

## 2. Visual design

### Overall style

- Professional application aesthetic.
- Compact layouts optimized for desktop productivity.
- Dark mode as the primary design target.
- Expressive but purposeful use of colour.
- Clear visual hierarchy with restrained borders, shadows, and decorative elements.
- Responsive layouts for mobile and tablet use.

### Colour system

Use semantic design tokens rather than assigning arbitrary colours to individual components.

Colour should communicate:
- Application/module identity.
- Financial and analytical data series.
- Positive, negative, and neutral states.
- Warnings, errors, and items requiring attention.
- Interactive selection and focus.

Avoid using colour alone to communicate meaning. Labels, icons, values, or accessible descriptions must provide equivalent information.

Charts should use consistent, distinguishable series colours. Financial outflows should not automatically be treated as errors.

### Typography and spacing

- Compact tables, forms, and navigation.
- Strong distinction between headings, labels, primary values, and secondary metadata.
- Consistent alignment of numeric values.
- Tabular numerals for amounts, percentages, and measurements.
- Clear interactive targets even when visual spacing is compact.
- Avoid sacrificing readability for density.

Define spacing, typography, radii, surfaces, and colours through shared design tokens.

## 3. Platform layout and navigation

### Desktop navigation

Use a persistent sidebar containing the primary platform modules.

The main content area should prioritize analytics, tables, dashboards, and task-specific workflows.

Module-specific navigation should remain inside the selected module.

### Mobile navigation

Adapt the sidebar to a compact drawer or equivalent mobile navigation pattern.

Do not require horizontal scrolling of the entire page. Individual dense tables may scroll when necessary.

### Navigation rules

- Preserve the user's current context when opening record details.
- Keep navigation consistent across modules.
- Provide clear active-page indicators.
- Avoid duplicating navigation controls.
- Support direct links to meaningful pages and records.
- Do not introduce extra navigation levels without a functional reason.

## 4. Information hierarchy

Use balanced information density.

### Default display

Show the information necessary to understand the current screen and perform its common tasks.

### Secondary information

Place optional details, advanced settings, historical metadata, and unusual workflows behind contextual actions or expandable sections.

### Redundancy rule

Do not show a field, status, or explanation when the same information is already conveyed clearly elsewhere.

**Example:** A transaction's category determines its accounting behaviour. Do not require or display a redundant editable transaction-type field.

### Important exception

Expose information when it affects a consequential decision, explains an unusual result, or communicates an actionable problem.

Technical information should remain accessible for troubleshooting without occupying ordinary workflows.

## 5. Interaction and editing

### Editing pattern

Use contextual side panels as the primary editing interface.

- Keep the underlying table or dashboard visible where practical.
- Preserve scroll position, search, and filters.
- Avoid full-page navigation for simple record edits.
- Use dedicated pages for genuinely complex workflows.
- Use modal dialogs sparingly.

### Saving

Adopt a hybrid approach.

**Auto-save:**
- Simple category changes.
- Personal preferences.
- Individual low-risk fields.
- Reversible adjustments.

**Explicit Save:**
- Multi-field forms.
- Complex record modifications.
- Significant financial or structural changes.

Show an unobtrusive saving state when needed.

Failed saves must be visible and must not be represented as successful.

### Confirmations

Require confirmations primarily for destructive, irreversible, security-sensitive, or high-impact operations.

Avoid confirmations for ordinary reversible actions.

### Recovery

- Support Undo where technically feasible.
- Prefer recoverable deletion or Trash.
- Preserve relevant history and audit information.
- Preview large or consequential bulk operations.
- Prevent partial completion of operations intended to be atomic.

## 6. Automation

The application should automate predictable decisions aggressively.

Examples include:
- Categorization based on established rules.
- Detecting likely duplicate imports.
- Applying saved user preferences.
- Recognizing recurring transactions.
- Suggesting related records.
- Identifying likely transfers.
- Highlighting unusual patterns.

### Automation safeguards

- Prefer deterministic rules when behaviour is well-defined.
- Distinguish confirmed results from suggestions.
- Require review when an uncertain decision has consequential effects.
- Provide correction mechanisms.
- Preserve original source records where relevant.
- Never silently perform irreversible financial changes.

Routine automation should be quiet. Exceptions should be actionable.

## 7. Tables and records

### Default table behaviour

- Use sensible columns and sorting for each screen.
- Favor compact rows and clear alignment.
- Make column headings descriptive.
- Support useful sorting and filtering.
- Use pagination or efficient loading for large datasets.

### Personalization

Allow users to customize relevant aspects of a table:
- Visible columns.
- Column order.
- Column width where practical.
- Sort order.
- Saved filters and views.

Store preferences per page while retaining platform-wide defaults.

### Bulk operations

Support both manual record selection and intelligent suggestions.

Bulk actions should be contextual to the selected records, with a clear summary before high-impact operations.

Avoid cluttering normal tables with controls for unusual bulk workflows.

## 8. Search and filtering

Provide quick search and the most useful common filters directly.

Place advanced filtering behind an expandable control.

### Filtering rules

- Show active filters clearly.
- Provide a simple Clear filters action.
- Preserve filter state when opening and closing a record.
- Avoid unnecessary filter panels.
- Allow saved views where they provide meaningful value.
- Remember page-specific preferences without unexpectedly applying stale filters to unrelated workflows.

Search and filtering should operate predictably and not silently change financial calculations elsewhere.

## 9. Dashboards and analytics

### Priority

Dashboards should be analytics-first, emphasizing:
1. Important KPIs.
2. Trends and comparisons.
3. Interactive visualizations.
4. Meaningful insights or exceptions.
5. Supporting detail when requested.

Do not fill dashboards with activity feeds simply because events are available.

### Customization

Start with well-designed default dashboards.

Allow dashboard content and layout to evolve through AI-assisted requests and controlled configuration.

Users should be able to describe desired reports in plain language.

### Charts

- Provide meaningful axis labels, units, legends, and periods.
- Support interactive drill-down into source records.
- Respect current report filters and context.
- Display missing or incomplete data honestly.
- Avoid misleading scales or unsupported precision.
- Use consistent analytical conventions across modules.

### Financial reporting

Keep account balances, cash flow, transfers, expenses, and net worth conceptually distinct.

Charts and summaries should clearly identify what they measure.

## 10. AI-assisted capabilities

AI should simplify configuration, reporting, and analysis rather than become a mandatory dependency for routine application functions.

### Preferred use cases

- Natural-language report creation.
- Dashboard customization.
- Categorization suggestions.
- Unusual-pattern detection.
- Cross-module questions.
- Report explanations.
- Generating reusable analytical views.

### Boundaries

- Use validated APIs and approved reporting queries.
- Prefer read-only access for AI-generated analytics.
- Do not permit unrestricted database mutations or arbitrary generated code execution.
- Require appropriate authorization and confirmation for sensitive actions.
- Keep core application functionality available without AI.
- Make generated reports inspectable, editable, and removable.

AI-generated dashboards should use the platform's established visual components and design tokens.

## 11. Notifications and insights

Adopt **quiet success, prominent failure**.

### Routine success

Avoid unnecessary toast messages, confirmation dialogs, and persistent status indicators.

### Failures

Make errors visible, specific, and actionable.

Preserve unsaved work where possible.

### Insights

Surface meaningful, relevant observations such as unexpected expenses, missed imports, unusual trends, or upcoming obligations.

Avoid repetitive suggestions, constant alerts, and low-value notifications.

Insights should be dismissible and should not dominate the dashboard.

## 12. Cross-application consistency

All modules should share:
- Design tokens.
- Navigation conventions.
- Input controls.
- Table and filtering patterns.
- Editing interactions.
- Confirmation and recovery conventions.
- Notification behaviour.
- Accessibility standards.
- Common terminology where applicable.

Individual modules may introduce specialized interactions when justified by their function.

### Integration architecture

Maintain clear ownership of data between applications.

Use documented APIs, stable identifiers, and authorized integrations rather than duplicating records unnecessarily.

Shared data should not require users to manage redundant fields across applications.

## 13. Accessibility and quality

- Support keyboard navigation.
- Preserve visible keyboard focus.
- Use meaningful labels and accessible control names.
- Ensure adequate text and control contrast.
- Avoid relying exclusively on colour.
- Support screen readers for tables, forms, and charts.
- Keep compact interfaces usable on touchscreens.
- Test responsive layouts and important workflows.
- Respect loading, empty, error, and partial-data states.

## 14. Development acceptance checklist

Before introducing or modifying an interface, verify:

- [ ] Is every visible field necessary?
- [ ] Can the application infer any of the requested information?
- [ ] Is complexity exposed only when relevant?
- [ ] Does the layout follow shared platform standards?
- [ ] Does it remain usable in dark mode?
- [ ] Are tables and forms appropriately compact?
- [ ] Are routine actions efficient?
- [ ] Can the user recover from common mistakes?
- [ ] Are important errors and exceptions clearly communicated?
- [ ] Are reports accurate and traceable to source data?
- [ ] Does the feature respect existing preferences?
- [ ] Are accessibility and mobile behaviour covered?
- [ ] Does the feature avoid unnecessary dependencies between modules?

## 15. Governance and evolution

This document is the baseline for future platform development.

Changes should follow the established principles unless an explicit functional requirement justifies an exception.

Prefer extending shared components over creating inconsistent replacements.

New application modules should adopt this standard from their initial implementation.

Revisit the standard when repeated exceptions reveal a genuine need for a new design principle.

**Guiding rule:** Make the application powerful underneath, simple in everyday use, and flexible when the user needs more.
