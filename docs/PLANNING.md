# Taxes and shared household budgets

Both modules use the same approved, stored-passkey household membership as Finance.
Tax-person labels organize records; they are not separate accounts or permission boundaries.
All approved household members share these records. No private budgets, profiles, tax
records, receipts or credentials belong in this public repository.

## Taxes

Choose a tax year, add a person and select Canada, US and/or FBAR workstreams. Add the
checklist items that apply, track Missing / In progress / Collected / Reviewed / Not
applicable, and enter optional dates. Collection progress does not change filing status.
This module organizes preparation; it does not calculate eligibility, file returns or FBARs,
fill tax forms, infer obligations or replace filing software.

Flag transactions from the year-based, server-paginated picker, singly or up to 50 at a
time. Tax purpose, review state and receipt requirements are independent of spending
categories. Repeated flags preserve existing notes/purpose and skip rather than overwrite.
Archived items can be restored. Trashed ledger records keep evidence but leave active
expense/receipt counts. Original imported records remain intact.

Documents support PDF, JPEG, PNG and WebP, up to 10 MB. Uploads require a prepared exact
private-bucket path, checked membership and a finish step verifying stored size/MIME.
SHA-256 values from client content validation deduplicate files within a year; the server
finish step does not independently hash or inspect file bytes. Pending uploads can be
retried using the same file. Ready files can support multiple records within the same year.
Unlinking preserves the stored file and link history; there is no permanent-delete action.
Downloads use authenticated blobs with temporary URLs revoked on close/unmount.

Reusing an earlier year's checklist copies active titles for the selected person/workstream
only. Statuses reset to Missing; notes, dates, expenses and documents stay in the original
year. A stable source-item reference makes retries idempotent without overwriting work.

## Budget

Start a month in the desired currency and choose refund timing. Set category amounts as
spending or income. Categories can reset monthly or carry positive unused money, optionally
capped. Fixed and variable costs can independently choose rollover behavior. A new month
can copy the previous plan's amounts/settings; actual spending is always read from the ledger.

Remaining allowance includes known rollover and subtracts recorded net spending, including
spending without an assigned allowance. Income is shown separately. Transfers and card
payments follow the existing accounting classifications and are excluded. Unclassified
positive credits are highlighted instead of guessed as income or automatically offset.
Currencies are reported independently, with no conversion or mixed-currency totals.

Link a positive credit to one or more purchases to reduce the purchase category's spending.
A $120 purchase and $40 refund produce $80 net spending. Both bank records remain intact.
Allocations cannot exceed the purchase or credit, require the same effective currency and
use sorted source-row locks plus revisions. Unlinking retains history and is reversible.
Changed/trashed sources create an issue; a surviving known refund is not silently income.

Refunds can affect the month received or the original purchase month. Changing this
currency-wide policy recalculates historical reports and later rollover. Budget source
views include linked cross-month records, with bank date/amount and separate budget impact.

Rollover begins with zero at the currency's explicit anchor month. Creating a plan before
that anchor currently requires a separate reviewed anchor change; choose the desired first
month before starting. Positive unused balances carry; overspending does not become next
month's budget debt. The cap applies to carry, not the base monthly allowance.

Coverage is never inferred from the latest dashboard sample or empty imports. Completed
months can be confirmed after checking all household accounts; the confirmation stores its
actor/time and account-scope fingerprint. Scope changes invalidate it. An incomplete earlier
month, plan gap or reappearing category has unknown carry, rather than an invented zero.
Current recorded remaining is explicitly provisional until coverage is confirmed. Goals,
forecasting, inflation adjustment and automatic budget recommendations are deferred.

## Public comparison baseline

[Statistics Canada Table 11-10-0223-01](https://www150.statcan.gc.ca/t1/tbl1/en/tv.action?pid=1110022301)
provides the bundled public baseline: reference 2023, 312 series across 78 published
geography/before-tax-household-income groups. Selected categories are food purchased from
stores, food purchased from restaurants, clothing/accessories and recreation.

The snapshot retains source URL, labels, vector/coordinate, units, quality/suppression flags,
reference year, retrieval date and official ZIP SHA-256. Missing/suppressed is unavailable,
not zero. Monthly presentation divides the annual nominal CAD average by 12, rounded to
cents, and is not inflation adjusted. No USD comparison is implied.

Select an actual published group and map equivalent household categories explicitly. A
suggested budget amount opens an editor and does not change the plan until Save. Household
size and tenure can be recorded privately for future comparisons; this dataset does not
jointly match those fields or occupations. No household profile is sent to Statistics Canada.
No combined peer group, percentile, local-city estimate or recommended target is invented.
Do not equate groceries with all food or full mortgage payments with shelter consumption.

Regenerate the public subset with `python3 tools/prepare-budget-benchmarks.py`. The importer
accepts no household data. Review changed source years/definitions before replacing a snapshot.

## Interfaces and boundaries

`src/planning.js` routes explicit operation allowlists to `household_tax_v1` and
`household_budget_v1`; other Finance operations retain their existing router. Both public
functions are security invoker wrappers over private entry points that verify a live stored
session, stored passkey authentication and approved household membership. Unknown fields,
stale revisions and invalid ranges fail. All private tables have RLS and no browser grants;
private read helpers/views are not executable/selectable by browser roles.

Tax API: workspace/year reads; server-paginated transaction selection; person/workstream
setup; checklist/filing/expense saves; archive/restore; atomic bulk flags; prepared document
upload/finish and same-year link/unlink. Budget API: workspace/month reports; month/line
saves; refund timing and coverage confirmation; paginated credit/purchase candidates;
revision-checked link/unlink; optional private profile; reviewed public category mappings;
paginated category source activity. See the planning migration for exact allowed keys.

All operations run through SessionFence. Authorization failures clear access; late results
cannot repopulate protected screens after sign-out/revocation. Tax document storage shares
that fence but uses a separate private bucket. Reports use complete server-side ledger and
linked-source context, never dashboard's latest-500 rows. Planned amounts, refunds, totals
and carry use exact integer/numeric arithmetic with safe-range checks. Saved actual/carry
snapshots are not used as authoritative balances.

Limits fail explicitly rather than silently truncate: 50 selected transactions, 50-row
source pages, 5,000 tax records/documents per collection/year, 8 MB workspace result, 50,000
currency ledger records and 600 monthly plans for a budget chain. These are foundation
limits, not filing or banking limits.

## Tests

`npm test` covers calculation/reference/UI behavior; `npm run test:browser` exercises the
integrated mock-only app on desktop/mobile, with accessibility checks. Production fixtures
are excluded from the published build.

`npm run test:planning:sql` starts isolated PGlite PostgreSQL, recreates a fabricated
Supabase auth/storage boundary and the repository schema, applies the planning migration,
and runs rollback-only planning SQL fixtures. It covers stored session/passkey membership,
actual authenticated-role grants/RLS, private prepared paths, annual copies, stale/atomic
writes, refund caps, source preservation, histories, profiles and category mappings. It does
not simulate multiple concurrent database clients or real Supabase Storage HTTP uploads.
Run the same rollback-only fixtures through an authorized administrative connection when
verifying hosted PostgreSQL. Never load the local auth/storage bootstrap into a live project.
