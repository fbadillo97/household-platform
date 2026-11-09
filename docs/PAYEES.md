# Payees

Payees identify the business, institution or person on the other side of a
transaction, including incoming payments. They are separate from categories,
accounts and transfer matching. A payee never determines accounting behavior.

## Everyday use

Open **Payees → Add payee**, or add one directly from a transaction's side panel.
Assign it under **Transaction payee**. A lone payee/category edit autosaves;
when any other field is dirty, use **Save changes** for the complete draft.
Failed saves preserve the draft. Renaming a payee updates the directory label
without rewriting imported descriptions.

Use **Recognize this imported description next time** after an assignment, or
edit a payee's aliases (one description per line). Aliases match the original
imported description exactly, ignoring letter case and repeated spaces. No
prefix, substring or fuzzy matching is performed. Canonical names alone do not
create a rule. Each normalized alias can belong to only one payee; conflicting
rules are rejected atomically.

Confirmed aliases recognize **future imports**. Existing unassigned records may
show an exact-alias suggestion in their detail panel; acceptance is explicit.
Deployment does not backfill existing records. Manually clearing a payee also
suppresses that record's suggestion. Editing notes/category on its own preserves
payee assignment and recognition provenance. Repeated source-ID imports do not
replace the saved local payee.

For existing records, select up to 50 transactions on the current page, choose
**Set payee**, review the before/after preview and confirm. Assignments/clearing
use the existing atomic, revision-checked bulk operation. Stale selections fail
as a whole. Bulk assignment does not create aliases.

Transactions includes an optional Payee column, sorting, quick-search matches
against canonical payee names and an advanced Payee filter (including Unassigned
and archived names). The directory's Transactions button opens all active
transactions for that payee, clearing the previous account/month/search scope.

Archive a payee in its editor to stop new assignment/recognition. Existing
assignments, aliases and historical filtering remain intact. Show archived
payees and clear Archived to restore it. Remove an alias in the editor before
reassigning it to another payee. There is no permanent-delete or merge action.

## Database and access

`20261108172028_payees.sql` is applied to the dedicated Household Platform
project. The file was created with Supabase CLI 2.81.3, then aligned with the
hosted migration version returned by Supabase. Do not rerun applied migrations.

Payees and aliases live in `household_private`, with RLS enabled and no browser
role table grants or allow policies, matching the existing deny-direct-access
architecture. New private helpers have fixed empty search paths and revoked
PUBLIC/anon/authenticated execution. The checked `household_v1` RPC retains
live approved-member, verified-user and server-recorded passkey requirements.
Updates use revisions and write audit events. The import trigger only sets
payee metadata on new rows, using approved exact aliases. Source identity,
amounts, category behavior, dates, balances, receipts and reciprocal transfer
links are unchanged.

API additions:

- `list_payees {}` → canonical directory with aliases and revisions.
- `create_payee {name, kind, aliases}` → `{id}`.
- `update_payee {id, revision, name, kind, aliases, archived}` → `{id}`.
- `remember_payee_alias {id, revision}` → remembers the transaction's original
  description for its currently assigned active payee.
- `update_ledger_transaction` accepts nullable `payee_id`.
- `bulk_update_transactions` supports action `payee`, with UUID or null value.
- Ledger query accepts nullable `payee_id`, `__unassigned`, and sort `payee`.
- Transaction detail adds `payee_id`, `payee_assignment` and an optional
  `suggested_payee_id`. Ledger rows also include `payee_name`.

Limits: 2,000 payees; 50 aliases each; 120-character names; 500-character aliases.
Lists fail explicitly if the directory exceeds the supported bound. There is no
public URL parameter containing names or other household records.

## Verification

- 27 Node/DOM tests and production Vite build passed.
- 16 desktop/mobile Chromium cases passed (14 full-suite cases plus focused checks
  for two added inline-creation cases), including axe scans, layout overflow,
  autosave, create-error recovery, recognition, bulk previews, filtering and archive.
- Desktop directory and mobile transaction screenshots visually inspected.
- Migration and fabricated payee tests first passed inside a rollback transaction.
- After applying, payee, ledger, detail/receipt, bulk and security SQL suites all
  passed inside rollback transactions; no mock data was retained.
- Payee SQL checks include imported/accounting invariants, exact future recognition,
  source-ID deduplication, linked-transfer preservation, stale/atomic bulk edits,
  archive history, Trash/restore, OTP/sessionless/removed-member denial and private grants.
- Security advisor reports the intentional private-table RLS/no-policy notices,
  including the two new tables. The existing leaked-password-protection warning
  is unchanged ([Supabase guidance](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection)).
  No auth/provider settings were changed by this feature. Performance review found
  only the nine existing unused-index informational notices, with no new missing
  foreign-key index issues.

Payee-specific financial reports and fuzzy suggestions remain future work.
Cash Flow reporting has not been implemented by this release.

## Payee tags and directory tools

Settings → Payee tags creates, renames, archives and restores classification
labels independently of transaction tags. Multiple tags may describe a payee;
these never determine accounting behavior. Household member names can be labels,
but are not yet foreign keys to membership profiles. Starter labels and curated
assignments are private runtime data, not embedded in this public repository.

The directory filters by name/alias/tag search, type, tag (including Untagged)
and archive state; sorts by name, type, active transaction count or most recent
transaction date; and paginates 50 rows. Existing archived tag assignments remain
visible and filterable. The payee editor saves tags with the rest of its draft.
Page selections can add/remove one tag atomically with revision checks. Settings
renames preserve tag IDs and links. Archive stops new assignment, retaining links;
there is no destructive tag-delete operation.

Private tables `payee_tags` and `payee_tag_links` have RLS and no direct browser
privileges. The existing approved passkey RPC routes `list_payee_tags`,
`create_payee_tag`, `update_payee_tag` and `bulk_payee_tag`; create/update payee
add optional `tag_ids`. Limits: 200 tag definitions, 30 tags per payee, 100 payees
per bulk request. Stale bulk requests roll back in full. Directory activity counts
exclude Trash. Monetary totals are intentionally omitted because currencies,
report periods and transfer treatment require explicit context.

Verification uses fabricated SQL/browser fixtures for tag CRUD, archive retention,
revision failures, atomic bulk edits, original-ledger preservation and passkey/
private-grant boundaries. Personal relationships must not be guessed from names.
