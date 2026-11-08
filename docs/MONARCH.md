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
