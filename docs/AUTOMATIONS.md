# Automations

Open **Settings → Automations** (`#settings/automations`) to see saved statements,
on/off switches, latest results, errors and affected transactions. Existing
payee-description recognition appears in the same directory. The interface is an
inspection/control surface; ask the assistant in the connected chat to create
or revise a definition. There is no paid model call, API key or AI chat embedded
in the app. Execution uses a closed, validated database interpreter.

## Scope and behavior

- New imports only. Definitions and toggles never backfill old records.
- Payee recognition runs first. Other rules run by priority, creation time and ID,
  in the same order shown in Settings. Conditions use the fixed imported snapshot
  after recognition. Actions do not trigger new matches in other rules. Later
  matching rules may update the same fields; tags are merged case-insensitively.
- Amount predicates use signed integer cents and require an explicit currency.
  Outflows are negative. No currency conversion or absolute-amount inference.
- Conditions: payee ID, effective account ID, original-description substring,
  inclusive minimum/maximum amount, currency. All supplied conditions must match.
- Actions: assign/clear payee, assign/clear a normal income/expense category,
  add 1–5 tags, set review status or attention flag. No amounts, dates, accounts,
  imported descriptions, source identity, receipts, balances, deletion or transfer
  linking/classification actions are accepted. Unsupported keys/code are rejected.
- Category actions reject transfer/card-payment categories; category changes on
  classified or linked transfers require individual review. A category rule that
  later becomes unsafe fails visibly instead of altering accounting semantics.
- A failing rule rolls back its own work, records the error and permits the import
  and other rules to continue. There is no silent retry or fuzzy inference.
- Source-ID deduplication prevents repeated imports from running actions again.
- Activity starts at feature deployment. Applied/unchanged/error results include
  definition snapshots. Affected lists include previously applied results, even
  when undone. Deleted aliases retain their activity snapshots.
- Undo restores the exact changed metadata only while the transaction revision is
  unchanged and it is active. Later edits, subsequent rules or Trash disable Undo
  rather than overwrite work. Undo is not an automatic rerun. Earlier results in
  a chain may therefore require individual correction.
- Payee edits retain unchanged alias IDs and switches. Removing/readding an alias
  creates a new rule. Archived payees cannot resume recognition until restored.

## Creating or revising through an assistant

Use the controlled writer rather than arbitrary SQL updates or generated code.
Normal approved-passkey RPC: `household_v1('save_automation', definition)`.
A connected administrative assistant can call the **private SECURITY INVOKER**
`household_private.save_automation(definition, true)`. PUBLIC, anon and authenticated
execution are revoked; the public dispatcher always passes `false`. Administrative
writes are recorded as `assistant_admin`, with no impersonated household user.

Definition (fabricated example; resolve actual IDs privately):

```json
{
  "name": "Tag monthly insurance charge",
  "conditions": {
    "payee_id": "<resolved payee UUID>",
    "amount_min_minor": -12500,
    "amount_max_minor": -12500,
    "currency": "CAD"
  },
  "actions": {"add_tags": ["Insurance"]},
  "priority": 100,
  "enabled": true
}
```

New definitions default to **off** unless enabled explicitly. Updates require
`id` and current `revision` along with the definition. Use bound/structured SQL
parameters or a properly escaped JSON literal; never interpolate user prose as
SQL. Check returned definition and use rollback fixtures for new action patterns.
No real rule is seeded by this deployment; existing aliases keep their state.

API additions: `list_automations {offset}` (100/page), `toggle_automation
{kind,id,revision,enabled}`, `automation_history {source_key,offset}` (50/page),
`undo_automation {id,transaction_revision}`. Ledger query adds `automation_source`
and `automation_event` filters; the UI labels and clears these scopes explicitly.
Maximum 100 general rules; conditions/actions up to 8 KB, definitions up to 10 KB.
Payee aliases retain their existing limits. Definition versions and activity are
private runtime data, not source files. No automated historical application is
provided; a future historical runner must preview a bounded selection and require
explicit confirmation.

## Verification and security

The CLI-created migrations were aligned with hosted versions:
`20261108184529_automations.sql`, `20261108184607_automation_history_scope.sql`.
The second fixes a reader-variable ambiguity found during database regression.
Schema validation ran in a rollback transaction before application. Automated
behavior, permissions and existing ledger/import operations were then verified
on the hosted database using rollback-only fabricated fixtures.

30 unit/DOM tests and 18 desktop/mobile browser cases passed, including axe scans,
toggle conflicts, visible errors, Undo, deep links and affected-record scopes.
Automation, payee, ledger, bulk, detail/receipt and security SQL suites passed.
Private tables have RLS, no allow policies and no browser grants. Helpers use
fixed empty search paths and revoked execution; public reads/writes still require
live approved-passkey access. Versions record actor/provenance; execution results
record before/after values. Schema changes do not expose a new public endpoint.

The security advisor's private-table RLS/no-policy notices are intentional. Its
existing [leaked-password-protection warning](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)
is unchanged; no Auth provider settings were changed.

Recurring tracking remains a separate planned Finance capability; see [Roadmap](ROADMAP.md).
