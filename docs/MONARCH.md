# Monarch snapshot import

This is an on-demand assistant-assisted import, not a bank feed or a background sync. The assistant reads an explicitly scoped source account and date range through the connected Monarch tools, validates and stages the snapshot, then commits it through the authorized administrative database connection. No Monarch credentials or real source data are stored in Git, build artifacts or GitHub workflow logs. The website reads the imported records from the existing passkey-protected household API.

## Scope and coverage

- Use exact account-name filtering supported by the connector, then independently check every transaction's stable account ID, dates and posted status. Account-ID filters were not reliable in the tested connector.
- Fetch every page and verify the unique returned ID count matches the scoped advertised count. Do not label a truncated snapshot complete. Connector-excluded institutions must be listed in private coverage notes, not silently omitted or treated as zero.
- Current balance values are not imported or reconstructed. A month of transactions is not enough to infer an opening/closing balance or reconcile a bank statement.
- The connector may omit currency. If a currency is inferred, retain that assumption in private account metadata and coverage notes and display it for confirmation.
- Preserve source transaction/account/category IDs and the returned source metadata. Notes, splits, attachments and cleaned descriptions may be absent even when details are requested. Do not claim they were retrieved when they were not. The current imported sample contains no split transactions; a broader split-import workflow still needs review of parent/child semantics.

## Database contract

`accounts.source/external_id` identifies an imported account. `transactions.source/external_id` uniquely identifies an imported source transaction. Original returned metadata is held in `source_data`; the app's property/category assignments remain independent and can be edited with revision checks. The private source snapshot stores its period, normalized payload, coverage notes, actor, origin (`assistant` or `browser`), committed timestamp and inserted/skipped counts.

The administrative helpers are private and not executable by browser roles. Assistant imports are recorded explicitly as assistant-origin actions; they do not impersonate a browser passkey session. Browser entry points require current approved passkey sessions; stage/commit additionally require the owner role.

RPC operations:

- `stage_monarch_snapshot`: normalized `{account,period_start,period_end,expected_count,coverage_notes,transactions}`. Each row must match the account, lie in the period, be posted, have a unique external ID, valid signed integer cents and source metadata. Staging adds no ledger entries.
- `commit_monarch_snapshot`: `{id}`. Locks the snapshot and target account, atomically creates the account/categories/transactions and records provenance. Repeating the same snapshot inserts zero rows. Repeating IDs across different snapshots skips unchanged entries; a changed amount/date/description or different source account fails for review rather than silently replacing an existing record. Existing assignments are preserved.
- `list_source_snapshots`: approved passkey members can read coverage summaries. Raw source payloads are not returned by this summary operation.

A possible matching CSV fingerprint blocks the source commit for review. Cross-format matching remains heuristic; do not claim statement reconciliation. Source snapshots currently have no purge/cancel UI. Updating source-side changes, attachment downloads, balances, historical holdings and a dedicated browser connector are outside this first import.

## Tests and privacy

`supabase/tests/monarch.sql` uses mock values in one rollback transaction to check staging, counts, cents, metadata, repeat IDs, changed-source conflicts, validation and passkey/privilege boundaries. Do not replace the mock values with real source data. Finance UI tests use fabricated accounts and cover rendering/filtering/source coverage and account creation. Real account names, IDs, balances, transactions and notes must never be copied into tests, migrations, GitHub issues, workflow output or screenshots committed to the repository.

## Broad history imports

Full-history imports may use exhaustive global pagination when name filters are
ambiguous. Verify each row's stable account ID, deduplicate all pages, and account
explicitly for provider-excluded rows in the advertised count. Historical account
IDs missing from the current inventory remain separate accounts, excluded from
net worth until resolved. Do not merge accounts merely because their names match.

The importer accepts every supported account kind. Source notes initialize notes
on new entries only; replays preserve all local edits. Source tags, recurring
markers, merchant/category IDs, cleaned descriptions and attachment metadata stay
in `source_data`. Attachment metadata is not a downloaded receipt.

Match existing manually entered assets and debts before creating source accounts.
Attach source identity with revision guards and assistant audit entries, preserving
names, dated balances and secured-asset links. Currency inference remains flagged.
Do not reconstruct balances from transactions or trust property equity that omits
linked loans. Newly imported transfer-group categories must retain cash-flow
exclusion. Reverse-direction card payments use an explicit payment-reversal
transfer category; their original category remains in source metadata.

`monarch_catalog_snapshots` privately archives accounts, category/tag catalogs,
real estate, recurring streams, source rules, returned net-worth history,
investments, goals, budgets and coverage. Archives are bounded, content-addressed,
RLS protected and inaccessible to browser roles. They are not active app budgets,
goals, valuations or automations. Never execute source rule text. No public API
exposes these raw catalogs. Record assistant provenance and an audit event on each
administrative archive write. Raw transaction snapshots remain separately scoped
by account/year and idempotent through source IDs.

The connector can exclude institutions, omit receipt URLs, return limited history
or incomplete holdings. Preserve those limitations in private coverage metadata;
never describe the import as a complete bank reconciliation or complete backup.
