# Household Platform

Private household finance foundation, with property identifiers ready for future maintenance and document modules. React/Vite frontend, Supabase PostgreSQL, approved-member access, passkey controls, reviewed CSV imports. Real records are held only in the private database; repository fixtures remain fabricated.

## Current state

- This public repository contains code, migrations and fabricated fixtures only; real imported records stay in the private database.
- The dedicated Household Platform database is active in Canada Central (`ca-central-1`).
- All six SQL migrations are already applied to that project. Do not rerun them manually.
- The owner email reservation is configured privately in the database. The owner subsequently completed verified signup and passkey enrollment. No real email is seeded in migrations.
- The frontend deploys to GitHub Pages after successful tests/builds on main, or a manual Publish GitHub Pages run.
- The GitHub Pages website is published at https://fbadillo97.github.io/household-platform/ . The owner has completed passkey sign-in and disabled the Email provider. Statement reconciliation and a backup/restore drill remain outstanding.

The older FastAPI/SQLite Docker starter remains a separate local deliverable; this hosted app replaces that runtime with controlled Supabase database operations. There are no Docker or Python services to host for this version.

## Run the frontend

Use Node 22 and npm. From the repository root:

```sh
cp .env.example .env
# Set the project's URL and modern publishable key in .env.
npm ci
npm test
npm run dev
```

Get the public project URL and publishable key from Supabase's Connect/API settings. Never use a secret or service-role key in a `VITE_` variable. All `VITE_` values are public in the built site. `.env` is ignored by Git. The build deliberately accepts only the modern `sb_publishable_` key format. `VITE_APP_BASE` is `/` for a root-domain deployment; use the appropriate trailing-slash subpath for a project site.

`npm run build` writes `dist/`. Host that directory on an HTTPS static host. This repository is public for GitHub Pages hosting; keep all household records and receipt files out of it. The included `_headers` file applies on hosts that support that convention; configure equivalent response headers on other hosts. It is not a substitute for database authorization. Do not deploy preview URLs as passkey enrollment origins.

See [deployment and sign-in setup](docs/DEPLOYMENT.md) before the first owner sign-in.

## How access works

Routine login is passkey-only. The database checks the verified user's live session, its **server-stored** `auth.mfa_amr_claims.authentication_method = 'passkey'`, and current approved membership on every data/admin operation. A user-controlled JWT metadata field, AAL1, a verified email, or an approved owner role is not sufficient. The only operations permitted without a passkey are reading one's own membership status and requesting approval; they expose no household records or approval queue.

The frontend provides only a passkey sign-in button and no email-link form. Automatic URL session acceptance is disabled. An email-authenticated session is not shown Finance or owner controls. Sessions remain in browser memory only, and late protected responses are invalidated on sign-out/revocation. Current access is rechecked every 30 seconds and on visibility changes. Already viewed information cannot be recalled.

**Auth-provider cutover (completed for this project):** on a new deployment, disable the Email provider in the Household Platform Dashboard (not the email-confirmation option), retain passkeys, and use Account security → Sign out all devices, then sign back in with a passkey. The connector cannot change provider settings. Until Email is disabled, Supabase's direct Auth APIs may still issue email sessions and permit credential enrollment; hiding the email form or blocking data alone is not the full provider cutover. Do not describe the project as fully passkey-only before this is completed and verified.

Keep at least two independently usable passkeys. Keep independent backups. The UI prevents removing the last listed key, but this is a convenience guard rather than a restriction on Supabase's direct credential-management APIs. Recovery after loss of all keys requires deliberate administrator assistance, identity verification and re-enrollment; there is no automatic email recovery. Protect the Supabase administrator account itself.

Membership approval remains separate from identity authentication: pending/rejected/removed accounts cannot read records, even with a passkey; only the current owner may approve/remove members. User-editable JWT metadata does not assign roles. Future-member initial enrollment needs a controlled administrator-assisted flow while Email is disabled; no public self-service passkey registration/recovery flow is supplied by this cutover. Approval APIs remain ready for enrolled users.

There is one household per project. All approved members currently share finance read/write access. The wishlist remains on a separate Supabase project. Passkeys are an experimental Supabase feature; keep the client pinned and retest on upgrades.

## Finance workflow

The app has three pages: Dashboard for overview totals, leading categories, account activity counts and import coverage; Transactions for sortable/filterable ledger columns, description/account overrides, category edits and CSV review; Settings for accounts, categories, passkeys and household access. Property controls are parked for a later rental module. The ledger separates Date, Description, Account, Amount, Category and Tags. Click a column heading to sort. The Filters accordion starts collapsed and groups month/search, dates, descriptions, accounts, signed amount ranges, categories and tags; its summary shows the active-filter count. Closing it preserves filters, while Clear all filters removes them. Results are paginated in groups of 50. Description/account overrides can be reset and never alter raw imported fields or source identity. Cross-currency account overrides are rejected. Account/month selections and staged CSV reviews survive page changes; transaction search does not alter dashboard totals. Hash links (`#dashboard`, `#transactions`, `#settings`) support bookmarks and browser navigation on GitHub Pages. Only account activity is totaled, never balances or mixed currencies. [Monarch import contract](docs/MONARCH.md) documents repeat-import behavior, preserved fields and limitations.


Click any transaction row (or Open) for the detail panel. Edit description, same-currency account, category, notes, Reviewed/Needs attention flags and local tags. Save changes explicitly. Original imported details are collapsed for reconciliation; source values and IDs remain immutable. Date and amount are read-only. Active and Trash views share the existing filters. Trash excludes the record from overview totals and preserves notes, receipts and import identity; Restore brings it back. Repeat imports cannot resurrect a trashed source ID.

Receipt files use the private `household-receipts` Storage bucket, with approved-passkey checks on every object operation. PDF/JPEG/PNG/WebP, 10 MB per file, 20 per transaction. Files are content-checked in the client and type/size-checked on the server; this is not antivirus scanning. SHA-256 deduplication is scoped to a transaction. Paths contain generated IDs, not filenames. Viewing downloads through authenticated Storage (no public or signed sharing links), then creates a temporary browser preview URL, revoked on close/sign-out. PDF preview support varies by browser; Download remains available. Removing a receipt is permanent and requires confirmation; moving a transaction to Trash retains its files.

Uploads/removals span Storage and database requests, so they are retryable rather than one atomic transaction. An interrupted upload remains Pending: reattach the same file or Remove it. Removal deletes the blob before tombstoning metadata; if the final request fails, retry Remove. Trashed receipts can be read but cannot be changed until the transaction is restored. All approved household members share receipt read/write access. Downloaded files remain on the user's device.


For a fresh demo, add a mock account and optional categories. Upload `public/mock-transactions.csv`, which intentionally contains an identical payment and an invalid date. Preview validation and duplicate warnings, then explicitly confirm selected rows. Open a transaction to edit its category and local details.

CSV: UTF-8, exact ordered headers `date,description,amount`, ISO dates, positive inflows/negative outflows, at most two decimal places. Client CSV limit is 1 MB / 5,000 rows; server independently checks structured payload size, types and each amount/date/description. Amounts are stored as integer cents. Only currencies with two decimal places are supported. No currency conversion or balances are inferred. Imports retain normalized staged rows, not original files or invalid raw values.

Duplicate warnings are scoped to one account and match date, normalized description and cents. Default selection excludes them. Explicit selection sends duplicate acknowledgments. Commits lock the batch and account, recheck duplicates, validate all selected IDs, and atomically insert transactions. A newly detected duplicate fails for renewed review. Identical legitimate payments can be deliberately retained. This is duplicate assistance, not statement reconciliation. Imported batches cannot be committed twice. Import previews/commits are restricted to the staging user.

Dashboard uses the latest 500 effective transactions; the Transactions page filters/sorts all matching records on the server and loads 50 at a time. Monarch imports preserve their source IDs, categories, returned tag metadata and other returned source details. Source notes/attachments/split details are not assumed present when the connector omits them. No balances or document files are imported. The API supports account/property filtering and limit/offset pagination. Assignment updates and approval decisions require a revision to reject stale edits. A private audit table records successful record creation, imports, assignments and access decisions; there is no audit viewer yet.

This remains a transaction-ledger foundation: no reconciliation, opening balances, transfers, double-entry bookkeeping, tax reports, budgets, bank feeds, imports history UI or permanent retention/purge UI. Documents and maintenance have extension points through property UUIDs but are not implemented.

## Database ownership and API

All records live in unexposed `household_private` tables with RLS enabled and no direct browser table grants. RLS intentionally has no allow policies: direct access is denied. The sole public endpoint is `household_v1(operation,payload)`, a SECURITY INVOKER wrapper around a checked private entry function and dispatcher. The private definer functions have fixed empty search paths, schema-qualified references, no dynamic SQL and restricted EXECUTE grants. They do not trust user-editable JWT metadata for approval/roles. See [API contract](docs/API.md).

Do not expose `household_private` in the Data API settings. Do not grant direct table access to `anon` or `authenticated`. Database administrators and project secret keys remain privileged; protect the Supabase and GitHub accounts with MFA.

Migrations are versioned in `supabase/migrations`. The first creates the foundation; the second qualifies staged-row columns in the import commit function; the third requires server-recorded passkey authentication; the fourth adds private source snapshots and external-ID deduplication; the fifth adds local overrides and the paginated ledger query; the sixth adds transaction notes, review flags, tags, recoverable Trash and private receipt storage. Those filenames match the project's applied migration history. Future changes need new migrations, database tests and advisor review. Supabase CLI 2.81.3 was used only to create migration files; hosted migrations were applied through the Supabase connector. CLI 3 has different target/confirmation behavior: read its help and current docs before deploying with it. No workflow automatically deploys database changes or requires a database secret.

## Verification and backups

`npm test` checks CSV parsing, explicit duplicate acknowledgement and late-response invalidation. `npm run build` validates the production bundle. `supabase/tests/security.sql` runs a full database verification inside a rollback transaction using fabricated Auth identities/sessions. It requires an administrative connection to a prepared Supabase database; never remove its final rollback or replace fixtures with real users. [Validation results](docs/VALIDATION.md) distinguish verified behavior from outstanding deployment checks.

Set up an independent encrypted backup/export and perform a restore drill before using real records. Verify your Supabase plan's backup/retention options rather than assuming they are included. Back up the database AND the private Storage objects separately; database dumps alone do not contain receipt files. Keep both outside Git. Project region controls primary data location; it does not guarantee that every log, email, static asset or service remains in Canada. Review any broader residency requirements before adding sensitive records.

Official references: [passkeys](https://supabase.com/docs/guides/auth/passkeys), [database functions](https://supabase.com/docs/guides/database/functions), [regions](https://supabase.com/docs/guides/platform/regions).
