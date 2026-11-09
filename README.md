# Household Platform

**UI / product standard:** [Household Platform Design Standard v1.0](docs/DESIGN_STANDARD.md) (adopted). Future development should follow [AGENTS.md](AGENTS.md) and the design acceptance checklist.

Private household finance foundation, with property identifiers ready for future maintenance and document modules. React/Vite frontend, Supabase PostgreSQL, approved-member access, passkey controls, reviewed CSV imports. Real records are held only in the private database; repository fixtures remain fabricated.

## Current state

- This public repository contains code, migrations and fabricated fixtures only; real imported records stay in the private database.
- The dedicated Household Platform database is active in Canada Central (`ca-central-1`).
- The versioned SQL migrations in this repository are already applied to that project. Do not rerun them manually.
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

The app has four pages: Accounts for grouped dated balances, inclusion settings and archive/restore; Dashboard for net worth/saved-balance visuals, transaction activity and import coverage; Transactions for sortable/filterable ledger columns, description/account overrides, category edits and CSV review; Settings for categories, passkeys and household access. Property controls are parked for a later rental module. The ledger separates Date, Description, Account, Amount, Category and Tags. Click a column heading to sort. The Filters accordion starts collapsed and groups month/search, dates, descriptions, accounts, signed amount ranges, categories and tags; its summary shows the active-filter count. Closing it preserves filters, while Clear all filters removes them. Results are paginated in groups of 50. Description/account overrides can be reset and never alter raw imported fields or source identity. Cross-currency account overrides are rejected. Account/month selections and staged CSV reviews survive page changes; transaction search does not alter dashboard totals. Hash links (`#dashboard`, `#accounts`, `#transactions`, `#settings`) support bookmarks and browser navigation on GitHub Pages. Only account activity is totaled, never balances or mixed currencies. [Monarch import contract](docs/MONARCH.md) documents repeat-import behavior, preserved fields and limitations.


Click any transaction row (or Open) for the detail panel. Edit description, same-currency account, category, notes, Reviewed/Needs attention flags and local tags. Save changes explicitly. Original imported details are collapsed for reconciliation; source values and IDs remain immutable. Date and amount are read-only. Active and Trash views share the existing filters. Trash excludes the record from overview totals and preserves notes, receipts and import identity; Restore brings it back. Repeat imports cannot resurrect a trashed source ID.

### Accounts foundation

Accounts groups active records under Checking, Savings, Credit cards, Loans (including mortgages), Investments, and Property & Other Assets. Empty groups stay hidden. Each card shows its balance/value, currency, as-of date, net worth inclusion and a Manage account control. Missing values say Not provided; zero is a real saved balance. Section subtotals include all listed balances (including excluded accounts), report missing counts and never combine currencies. Balances over 30 calendar days old are flagged. This does not infer balances from ledger transactions or pull them from Monarch.

Create accounts in Accounts rather than Settings. Existing types/identities are retained; new loan, investment and asset types are supported. Types and currencies are fixed after creation so old balances or card payments cannot be silently reinterpreted. Account names and Include in net worth can be edited with revision checks. The existing source currency-assumed flag remains visible: verify currency before saving balances. Only two-decimal currencies are supported.

Manage account provides a separate dated-balance form. Bank accounts use Balance, investments Market Value, and assets Estimated Market Value. Cards/loans use Amount owed: positive is debt, negative is a credit/overpayment (displayed as Credit balance). Ordinary bank/investment balances may be negative; estimated asset values may not. Snapshot currency comes from the account, and asset values are flagged estimates server-side. Dates must be valid, not future, and no earlier than 1900; amounts are exact integer cents within ±100000000000000. Each save appends an immutable private snapshot. Latest means greatest as-of date, then newest sequence for same-date corrections; backdated entries do not replace a newer dated balance. Earlier corrections remain stored for future history views.

Archive hides an account from the active Accounts groups and excludes it from the planned current net worth overview; the inclusion preference, balances, ledger transactions, source IDs and receipts remain intact. Restore returns it to the active list. Archived accounts cannot receive a manual balance until restored. Historical ledger/filter/import behavior is retained, so archiving is not a data deletion or a global freeze on historical imports. View transactions opens the account's ledger with date/column/type filters cleared. Net worth summary cards, current-balance visuals and expandable saved-balance history are on Dashboard. Individual account history is under Manage account. See [Accounts handoff](docs/ACCOUNTS_HANDOFF.md).


### Net worth overview and visuals

Dashboard starts with Where you stand: Net worth, Assets, Debts and Cash available, computed from latest saved balances of active, included accounts in the chosen currency. This overview is separate from the account/month transaction filters below it. Archived and explicitly excluded accounts do not contribute. Cash uses included checking/savings balances and does not deduct future bills or credit card payments. Assets sum signed non-debt balances; Debts sum signed card/loan/mortgage amounts owed, so overdrafts reduce Assets and credit balances reduce Debts. Net worth is Assets minus Debts. No FX conversion, market-price lookup, new account snapshots or ledger-derived balances are performed.

Coverage shows provided versus included accounts, date span, balances over 30 days old, assumed currencies and excluded/archive counts. Missing or invalid/future/mismatched-currency snapshots are omitted and mark the view Partial; they never become fake zero balances. All-missing totals say Not provided, genuine saved zeros display zero, absent account types show a dash. Unsafe aggregate integer amounts show unavailable rather than rounded totals. Totals describe only the accounts the user chose to include, not a guarantee of complete household coverage.

Two responsive SVG visuals show one fully filled bar dividing total assets into Liabilities on the left and Equity on the right, with Net worth centered above, plus a positive-equity breakdown donut. Equity deducts explicitly linked secured debts from the corresponding asset values. Exact amounts remain in labelled buttons/legend entries and accessible SVG descriptions. Negative equity and unallocated debt/credits are reported outside the donut; no negative slices are drawn. Missing linked-debt balances mark equity incomplete rather than using gross value. All-zero or missing data produces an honest empty state. The charts use presentation attributes and external CSS compatible with the existing CSP, with no external chart scripts or tracking.

Totals/chart controls open the relevant account subset with a visible Show all accounts reset. An included-account balance list opens individual account management directly. Account creation clears a subset so the new record is visible. Normal Accounts navigation returns the full list. These subsets are in session memory, not public URL parameters. Save a dated balance and return to Dashboard to see the updated overview. Open Net worth history for the saved-balance timeline, described below.


### Saved-balance history

Expand Net worth history on Dashboard, or Balance/Amount owed/Market Value history under Manage account. Controls offer the last 30/90/365 days, all saved dates and custom start/end dates. Expanding loads the checked history query; closing unmounts it and ignores late responses. History is loaded separately so it does not slow initial sign-in or require ledger-derived estimates.

A point uses the latest saved balance on or before that date. No value is carried backward before its first saved date. Latest same-date corrections replace older versions in the view; storage retains the earlier entries. Values are drawn as steps, not interpolated daily prices. One saved date and ranges with no new observations explicitly explain carry-forward. Unknown dates are gaps, genuine saved zeros stay zero, partial coverage is dashed, and changes in which accounts have balances break the line. Date inspection shows known/missing counts, carried values and balances over 30 days old relative to the inspected date. Keyboard timeline/date controls, exact-value tables, pagination and notes/correction indicators are provided. Large charts are simplified with bucket extremes and coverage changes retained; tables/inspection use exact records.

Net worth history consistently uses today's active, included accounts in the selected currency for the entire range. Current archive/inclusion choices restate that cohort; it is not a reconstruction of historical account membership. Individual account history remains available for archived or excluded accounts. A currency change never merges or converts balances. Saved-balance change is shown only with complete, safe-valued endpoints; a percentage needs a positive starting value. This is not an investment-return calculation. Missing balances are never filled from transactions or external market prices.

The read API returns at most 500 accounts and 10000 effective snapshot entries (including one carry-in seed per account), with an 8 MB response ceiling. Larger requests fail with guidance to narrow the range; nothing is silently truncated. The history view and its test fixtures cannot mutate stored balances. See [quality report](docs/HISTORY_QUALITY_REPORT.md) for verification and limits.

### Browser quality checks

`npm test` runs Node/DOM tests; `npm run test:browser` runs real Chromium at desktop and mobile sizes with Playwright and axe. After `npm ci`, install the browser runtime with `npx playwright install --with-deps chromium --only-shell` (system dependencies may need administrator installation on a local restricted machine). The suite builds an isolated mock household fixture and the production signed-out app on loopback ports 4175/4176. All non-loopback browser requests are blocked. No Supabase credentials, real sign-in or actual household records are used. Browser traces/screenshots are ignored locally and uploaded for failed CI runs only, with seven-day retention. Both check and publish workflows gate deployment on these tests.

The fixture is built into ignored `.browser-dist`, while shipping files remain in `dist`. It is not a production authentication route. Production bundling splits React, Supabase, CSV and lazy history code; exact cent formatting avoids floating-point division errors for very large totals. Source dependency versions remain pinned.


### Bulk review and Trash

Use transaction checkboxes to select up to 50 rows on the current page; the header checkbox selects that page only, with a mixed-state indicator for a partial selection. The action bar shows the selected count. Choose category (including Unassigned), Reviewed/Unreviewed, Needs attention on/off, Add tag or Remove tag. Tags are matched without regard to case and other labels remain in place. Review the change and per-row before/after preview, then confirm. The confirmation uses the exact selected IDs and loaded revisions, never an unbounded filter/query.

Bulk Move to Trash requires explicit confirmation and preserves notes, receipt files and source identity. Linked transfers block the whole Trash request; deselect them with the provided shortcut or undo their links individually first. The Trash view offers only bulk Restore. No permanent transaction-delete action is supplied. Account, description, amount, date, notes, receipts and transfer classification/linking remain individual actions in this version.

Each batch is one database transaction. The server locks all selected rows in stable UUID order and checks every revision/state before writing; missing, stale or invalid selections, a linked Trash target, and even a later tag-limit error leave the whole batch unchanged. Existing limits apply (20 effective tags, 60 characters per label). Matching values are skipped without revising records; success reports selected and actually updated counts. If a conflict occurs, refresh and select again rather than silently retrying changed records. Selection clears on filter/sort/page/view changes, refresh and successful completion. Imported originals and source IDs remain unchanged.


### Transfers and credit card payments

The detail panel has a Transfer or card payment section. You can explicitly classify one entry when the other side is not imported, or use Find the other side to review equal/opposite amounts in a different effective account with the same currency. Suggestions default to within 7 posting days, expandable to 31, with description/account search (nearest 50 results). Confirming a match links and classifies both entries atomically. A suggested card payment must leave a non-card funding account and arrive on a credit card; other movements use Transfer. Only use Transfer for movements between your own accounts, never merely because a description says transfer.

Nothing is matched or classified automatically, including existing source categories named Transfer. Existing rows begin Regular. Confirmed transfer/card-payment entries, including unlinked ones, are excluded independently from dashboard money in, money out, net activity and category totals. This also applies when the other side falls outside the selected month/account. The ledger retains both rows with Linked/Unlinked and Excluded indicators, and filters for type or unlinked transfers. Dashboard highlights unlinked entries for review. These figures remain signed activity, not balances or complete accounting reports; the existing latest-500 overview cap remains visible.

Undo linked transfer restores both entries to Regular and includes them in totals again. If only one side should remain excluded, undo and classify that side explicitly. Unlink before changing a paired account or moving either side to Trash. Notes, category, tags and receipts stay editable on linked active transactions. All changes use revisions; stale peers, already-linked records, same-account/same-sign/mismatched amounts, different currencies and posting dates beyond 31 days are rejected. Fees, splits, foreign-exchange and unequal/partial payments need separate records and are not linked by this version. Linking/classification does not change imported values or source IDs; repeat imports preserve it. No existing financial entries are auto-classified during deployment.


Receipt files use the private `household-receipts` Storage bucket, with approved-passkey checks on every object operation. PDF/JPEG/PNG/WebP, 10 MB per file, 20 per transaction. Files are content-checked in the client and type/size-checked on the server; this is not antivirus scanning. SHA-256 deduplication is scoped to a transaction. Paths contain generated IDs, not filenames. Viewing downloads through authenticated Storage (no public or signed sharing links), then creates a temporary browser preview URL, revoked on close/sign-out. PDF preview support varies by browser; Download remains available. Removing a receipt is permanent and requires confirmation; moving a transaction to Trash retains its files.

Uploads/removals span Storage and database requests, so they are retryable rather than one atomic transaction. An interrupted upload remains Pending: reattach the same file or Remove it. Removal deletes the blob before tombstoning metadata; if the final request fails, retry Remove. Trashed receipts can be read but cannot be changed until the transaction is restored. All approved household members share receipt read/write access. Downloaded files remain on the user's device.


For a fresh demo, add a mock account and optional categories. Upload `public/mock-transactions.csv`, which intentionally contains an identical payment and an invalid date. Preview validation and duplicate warnings, then explicitly confirm selected rows. Open a transaction to edit its category and local details.

CSV: UTF-8, exact ordered headers `date,description,amount`, ISO dates, positive inflows/negative outflows, at most two decimal places. Client CSV limit is 1 MB / 5,000 rows; server independently checks structured payload size, types and each amount/date/description. Amounts are stored as integer cents. Only currencies with two decimal places are supported. No currency conversion or balances are inferred. Imports retain normalized staged rows, not original files or invalid raw values.

Duplicate warnings are scoped to one account and match date, normalized description and cents. Default selection excludes them. Explicit selection sends duplicate acknowledgments. Commits lock the batch and account, recheck duplicates, validate all selected IDs, and atomically insert transactions. A newly detected duplicate fails for renewed review. Identical legitimate payments can be deliberately retained. This is duplicate assistance, not statement reconciliation. Imported batches cannot be committed twice. Import previews/commits are restricted to the staging user.

Dashboard uses the latest 500 effective transactions; the Transactions page filters/sorts all matching records on the server and loads 50 at a time. Monarch imports preserve their source IDs, categories, returned tag metadata and other returned source details. Source notes/attachments/split details are not assumed present when the connector omits them. No balances or document files are imported. The API supports account/property filtering and limit/offset pagination. Assignment updates and approval decisions require a revision to reject stale edits. A private audit table records successful record creation, imports, assignments and access decisions; there is no audit viewer yet.

This remains a transaction-ledger foundation: no reconciliation, opening balances, split transfers, cross-currency transfers, double-entry bookkeeping, tax reports, budgets, bank feeds, imports history UI or permanent retention/purge UI. Documents and maintenance have extension points through property UUIDs but are not implemented.

## Database ownership and API

All records live in unexposed `household_private` tables with RLS enabled and no direct browser table grants. RLS intentionally has no allow policies: direct access is denied. Public APIs use SECURITY INVOKER wrappers around checked private entry functions and dispatchers; visual preferences use `household_visuals_v1`. The private definer functions have fixed empty search paths, schema-qualified references, no dynamic SQL and restricted EXECUTE grants. They do not trust user-editable JWT metadata for approval/roles. See [API contract](docs/API.md).

Do not expose `household_private` in the Data API settings. Do not grant direct table access to `anon` or `authenticated`. Database administrators and project secret keys remain privileged; protect the Supabase and GitHub accounts with MFA.

Migrations are versioned in `supabase/migrations`. The first creates the foundation; the second qualifies staged-row columns in the import commit function; the third requires server-recorded passkey authentication; the fourth adds private source snapshots and external-ID deduplication; the fifth adds local overrides and the paginated ledger query; the sixth adds transaction notes, review flags, tags, recoverable Trash and private receipt storage; the seventh adds local transfer/card-payment classification and reciprocal links; the eighth adds atomic bulk metadata edits and Trash/Restore; the ninth adds extended account types, inclusion/archive metadata and private dated balance snapshots; the tenth adds a bounded checked history reader. Those filenames match the project's applied migration history. Future changes need new migrations, database tests and advisor review. Supabase CLI 2.81.3 was used only to create migration files; hosted migrations were applied through the Supabase connector. CLI 3 has different target/confirmation behavior: read its help and current docs before deploying with it. No workflow automatically deploys database changes or requires a database secret.

## Verification and backups

`npm test` checks CSV parsing, explicit duplicate acknowledgement and late-response invalidation. `npm run build` validates the production bundle. `supabase/tests/security.sql` runs a full database verification inside a rollback transaction using fabricated Auth identities/sessions. It requires an administrative connection to a prepared Supabase database; never remove its final rollback or replace fixtures with real users. [Validation results](docs/VALIDATION.md) distinguish verified behavior from outstanding deployment checks.

Set up an independent encrypted backup/export and perform a restore drill before using real records. Verify your Supabase plan's backup/retention options rather than assuming they are included. Back up the database AND the private Storage objects separately; database dumps alone do not contain receipt files. Keep both outside Git. Project region controls primary data location; it does not guarantee that every log, email, static asset or service remains in Canada. Review any broader residency requirements before adding sensitive records.

Official references: [passkeys](https://supabase.com/docs/guides/auth/passkeys), [database functions](https://supabase.com/docs/guides/database/functions), [regions](https://supabase.com/docs/guides/platform/regions).

### Compact Finance editing

Transactions keeps search, month and review shortcuts visible, with other filters
under Advanced filters. Columns lets each browser remember optional column
visibility. Category-only edits autosave; multi-field drafts use Save changes.
Errors keep the draft available for correction or guarded reload. Matching is
shown only for transfer/card-payment categories or existing links. Largest
outflow category bars open their source transactions in the current account/month.
These UI changes use the existing checked API and do not rewrite imported values.

### Payees

Use **Payees** to manage businesses, institutions and people, then assign them
in transaction details or through reviewed bulk edits. Exact imported-description
aliases recognize future imports; existing records are suggested for explicit
review. Payees stay independent of categories and transfer accounting.
See [Payee setup and API](docs/PAYEES.md) for filtering, archiving, limits and checks.

### Automations

**Settings → Automations** lists plain-language definitions, on/off switches,
activity, errors, guarded Undo and affected transactions. Ask the connected
assistant to create or revise a definition; imports execute validated actions
without per-transaction AI calls. Existing payee aliases appear in the same
directory. See [Automations](docs/AUTOMATIONS.md) and the retained
[Recurring/Cash Flow roadmap](docs/ROADMAP.md).

### Secured assets and equity

Link a mortgage/loan to its asset under **Accounts → Manage account → Secured
asset**. AI-assisted entry can set this relationship directly without a separate
review. The overview shows equity rather than gross values in its breakdown,
while unallocated debt still counts toward net worth. See [Equity](docs/EQUITY.md).

## Taxes and Budget

The Taxes workspace organizes yearly checklists, private supporting documents and flagged
expenses for Canada, US and FBAR preparation. Budget supports monthly household plans,
category rollover, linked full/partial refunds, separate currencies and sourced public
Statistics Canada comparisons. Both use existing approved passkey access.

See [Planning workflows and API boundaries](docs/PLANNING.md) for setup, calculations,
coverage, limits and tests. Start with a tax-year workspace or choose the first budget month;
no household budgets, profiles, tax records or financial defaults are seeded.

## Reports

Reports shows monthly income/inflows versus net spending, category charts, surplus/deficit
and a preceding equal-length comparison, with separate currencies and account filters.
Select a total or chart to inspect contributing records. Coverage warnings distinguish
imported activity from confirmed household totals. See [Reports calculations and tests](docs/REPORTS.md).

## Icons and logos

Soft category badges, identity-first account/payee images and static empty-state
illustrations share the platform's compact dark design. Customize records under
Settings → Icons & logos. Logos live privately outside the app code, so future AI-assisted
logo additions need no code release. See [Visual identity and logo workflow](docs/VISUAL_IDENTITY.md).

## Transaction summary and Administration

Transactions includes a full filtered summary with separate currency totals, averages,
record links and refund/transfer handling. Administration expands to Settings and import/
export logs; import coverage is located there. See [Calculations and log boundaries](docs/TRANSACTION_SUMMARY_ADMIN.md).

Reports includes a Trends & Forecasts starter with six complete months of history and
provisional three-month estimates based on a three-month average. Missing history stays
explicit; see [Reports](docs/REPORTS.md).

Reports Overview includes category income/spending donuts with ranked exact
amounts, a cash-flow savings rate, and category changes against the previous
same-length period. Chart slices and comparison amounts open their source
records; currencies and incomplete import coverage remain explicit.
