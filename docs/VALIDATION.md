# Validation

Verified against the dedicated Canada Central project using rollback-only fabricated Auth identities and records:

- Pending users cannot read or write records; direct private table/helper access is denied. User-editable owner metadata does not grant access.
- Only the privately reserved, verified email bootstraps the owner. Owner-only decisions, stale-revision rejection and owner-removal protection pass.
- Rejected users stay rejected and cannot self-reset their decision.
- Approved members cannot read the access queue or approve other users.
- Unverified and anonymous Auth users are denied, including anonymous users carrying the authenticated database role.
- Removed users lose data access with an existing JWT; tokens referring to missing/revoked server-side sessions are denied even for an owner.
- Signed-out RPC execution and table access are denied.
- Integer cents, strict date/amount validation, normalization and account-scoped duplicate warnings pass.
- Staging changes no transactions; invalid/foreign selections roll back; repeat commits fail; newly introduced duplicates require renewed explicit acknowledgement; an explicitly acknowledged legitimate repeat can commit.
- Transaction property/category assignment, revision conflict checks and property filters pass. Staged batches are restricted to their creator.

The SQL file reports nine verification groups; several groups contain multiple assertions. All fixtures are rolled back. Follow-up counts confirmed zero Auth users, memberships, transactions and import batches, with the private owner reservation preserved.

Live public-endpoint checks also passed: anonymous business RPC returned 401; direct public account-table lookup returned 404. Auth settings confirm email confirmation is required, signup is enabled and anonymous sign-ins are disabled. These reads do not verify SMTP delivery or passkey configuration.

Frontend: three Node test groups pass (CSV parser, default selection/explicit duplicate acknowledgement, delayed-result invalidation). Production Vite build passes. Python/SQLite tests from the older starter do not validate this hosted version.

Security advisor reports nine informational `RLS enabled without policies` findings, one per private table. These are intentional deny-all tables with revoked direct browser privileges, accessed only through checked private functions. [Advisor explanation](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).

npm audit reports zero known vulnerabilities for the pinned frontend dependency tree at verification time. Performance advisor reports only four unused-index informational notices on the empty database; these indexes support foreign keys and are retained. [Unused-index advisor](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index).

Outstanding: actual browser layout, real email delivery, website headers/redirect configuration, device passkey enrollment/sign-in/recovery, simultaneous multi-connection import testing and a backup/restore drill. Nothing here claims those checks passed. No real finance data was accessed, and setup sent no email or invitations.


## Passkey-only cutover verification

The full rollback suite passes eleven groups. Added assertions deny all thirteen household data/admin operations to an approved owner's OTP-only session even when the test JWT AMR and user metadata claim passkey authentication. A server-recorded passkey session passes. The test fixtures now create their own temporary sessions/AMR records; when an owner exists they use that owner's UUID in a rollback-only test session, without changing the owner's membership, credentials or identity. Transaction reads are filtered to generated mock accounts. Mock sessions, AMR records and finance rows are rolled back.

The fourth frontend test verifies that the protected view requires the server's strict boolean passkey_verified, with no user-metadata fallback. Provider configuration and the native WebAuthn ceremony are outside these automated checks. The Email provider must still be disabled in the Dashboard, then sessions signed out globally; no test here claims that toggle has already happened.


## Source snapshot and finance screen verification

The Monarch migration adds account/transaction external identity constraints and a private source-snapshot table. Four rollback test groups verify validation, integer cents/metadata, same-snapshot and cross-snapshot deduplication, changed-record conflicts with atomic rollback, and passkey/private-helper boundaries. An authorized one-account snapshot was loaded privately and its row count, unique IDs and signed integer totals checked against the retrieved source. Those private values are deliberately omitted from this document and all fixtures.

The finance screen adds account/month/category/tag filtering, signed activity summaries, source metadata/coverage and working account/property/category forms. DOM simulation checks loading mocked private responses, tag filtering and successful account submission. A separate unit test checks exact cents and filter scope. These simulated checks do not establish native-browser passkey behavior or bank statement reconciliation. Supabase security review adds the intended informational deny-all RLS/no-policy finding for the new private table; its leaked-password-protection warning remains a provider setting, and the app requires passkey sessions for records.


## Page navigation

The frontend is split into Dashboard, Transactions and Settings views. Automated DOM checks cover view isolation, active navigation, shared account/month filters, search retention, dashboard totals independent of transaction search, overview drill-through, preserved staged CSV selections, working account creation under Settings, and hash/history navigation. Route unit tests check static-hosting deep links and invalid-route fallback. Existing private API and database records are unchanged by this frontend-only refactor. Browser/device visual review remains separate from DOM simulation.


## Ledger refinement

`supabase/tests/ledger.sql` runs rolled-back fixtures to verify effective account/description overrides, resets, same-currency enforcement, stale-revision rejection, raw source/property/fingerprint preservation, source reimport deduplication after overrides, numeric/date sorting, pagination and column filters, invalid query rejection and passkey/helper-privilege boundaries. The migration adds nullable override fields; deployment changes no existing descriptions or account assignments.

Frontend tests cover ledger server-query payloads, signed amount parsing, sort controls, amount filters, editable description/account overrides and resets, plus existing navigation/CSV staging behavior. Property creation and transaction property/source-detail columns are removed from the active UI; private schema fields remain for future use.


Transaction filters are grouped in a collapsed-by-default native details/summary accordion. DOM regression checks verify the table keeps its sort headings, active filters remain applied while collapsed, clear-all removes every filter, and a refresh after an edit does not restore a deliberately cleared month. No ledger/backend behavior or records are changed by this layout adjustment.


## Transaction detail panel and receipts

Migration six adds notes, local tags, review flags, recoverable Trash and a private receipts bucket without changing imported dates, amounts, descriptions, accounts or source IDs. `supabase/tests/details.sql` passes three rollback groups: field validation/source preservation; exact prepared Storage paths, authenticated RLS and hash deduplication; Trash/Restore, repeat-import exclusion, missing-object/removal ordering and OTP/public/direct-table denial. Tests use a mock account/transactions and temporary session for the existing owner, rolled back. Storage fixtures contain metadata only; no real receipt or file is uploaded/deleted by the SQL suite.

DOM tests cover opening/editing the panel, unsaved-close confirmation, notes/flags/tags, interrupted receipt upload/removal and retry, duplicate attachments, Trash and Restore. File tests reject oversize, unsafe names and unsupported content. Existing navigation, filter/sort, overrides/reset and CSV staging checks pass. Production build passes. These are simulated browser/storage operations; native authenticated file transfer, PDF preview and mobile visual acceptance still require a signed-in browser check.

The advisor adds one intentional deny-all RLS/no-policy informational receipt-table notice. No missing-FK-index or function-search-path warning was added. The pre-existing leaked-password warning concerns the disabled Email/password provider; passkey and membership gates remain required. New indexes are retained despite unused-index notices on this small ledger. See [RLS advisor](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy), [password advisor](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) and [index advisor](https://supabase.com/docs/guides/database/database-linter?lint=0005_unused_index).


## Transfers and card payments

Migration seven adds default-Regular local classification and reciprocal transfer peers. `supabase/tests/transfers.sql` uses a fabricated approved member, Auth session and accounts/transactions, plus a rollback-only source snapshot using the existing owner's ID for the private admin helper. Four assertion groups verify candidate amount/currency/date/account scope; invalid/stale/self pairs; atomic reciprocal linking and original-source preservation; reimport retaining links/notes; linked account/Trash guards; standalone classification/direction and restore; undo restoring both records; and denial of all four new operations to an OTP-only session. Direct browser access to both new private helpers remains revoked. All test writes roll back.

Unit tests verify both payment sides and standalone transfers are excluded from totals even across month/account filters, with regular purchases retained. DOM tests exercise the complete Dashboard → classify single side → review unlinked → find/review/confirm pair → updated totals → undo flow, plus the unsaved-details guard and flow query filter. Existing notes/receipt, navigation, sorting/filtering and CSV tests remain in the suite. Native browser visual acceptance and simultaneous multi-connection pairing are separate from these simulated/revision checks. Matching suggestions never apply changes automatically, and deployment does not classify existing real records.

All 13 frontend tests and the production build passed for this change. The four earlier security/source/ledger/receipt rollback suites also passed against migration seven. Signed-out HTTP calls to each of the four new operations returned 401. Security advisor findings were unchanged: intentional deny-all private-table notices and the existing disabled-password-provider warning, with no new function/search-path or FK-index warning. A post-test count confirmed existing records were not classified or linked by deployment.


## Bulk selection, metadata and recovery

Migration eight adds the checked bulk helper/dispatcher operation without changing existing tables or financial values. `supabase/tests/bulk.sql` uses a fabricated approved member, live passkey and mock finance records, all rolled back. Four assertion groups cover category assignment/clear, review timestamps and clearing, attention toggles, case-insensitive tag add/remove with preservation of other/source fields, no-op counts, stale/missing/duplicate/empty/oversized selections, unsupported fields/values, and an error on a later tag update rolling back an earlier update. Linked metadata edits work; linked Trash blocks the entire batch. Bulk Trash/Restore keeps notes and receipt metadata, rejects edits in Trash and stale replay. OTP-only and removed members are denied; the private helper has no browser EXECUTE grant.

The DOM test uses 55 fabricated rows to verify page-only selection, header mixed state, the 50-item limit and untouched second-page entries; explicit preview/cancel/confirmation; category/review/attention actions; tag preservation; stale failure and refresh/reselection; selection clearing across filters/pages; linked-transfer deselection; and bulk Trash/Restore with retained mock receipts/notes. These are simulated browser/Storage data, not real finance changes or native-browser visual acceptance.

All 14 frontend tests, the production build and all six database rollback suites passed against migration eight. A signed-out HTTP bulk request returned 401. Security/performance advisor findings were unchanged (intentional deny-all table notices, the existing disabled-password-provider warning and unused-index information). Post-test checks confirmed no remaining mock bulk rows; no existing financial values or receipt files were changed by the implementation/tests.


## Accounts foundation

Migration nine adds account revision/inclusion/archive fields and the private append-only account_balance_snapshots table. `supabase/tests/accounts.sql` rolls back fabricated member/session/account/snapshot fixtures. Three groups verify every supported type, absent versus zero, positive debt/negative credits, estimate/currency derivation, backdated and same-date latest selection with preserved earlier snapshots; stale/invalid/future/precision rejection; immutable account type/currency; name/inclusion/source preservation; archive/restore without balance loss; and denial to OTP/removed users and direct private-table/helper access. Snapshot creation produces no ledger rows.

Unit checks cover exact cents, invalid precision/range, per-currency subtotals, missing versus zero, mortgage grouping and the 30-day threshold. DOM checks cover grouped balances/labels, missing and zero displays, stale estimates, account creation, metadata saves preserving an unsaved balance draft, dated balances, inclusion, archive confirmation/restore, card overpayments, stale edits/reload and account transaction drill-through. Existing navigation tests now create accounts under Accounts while keeping security/categories in Settings. Native browser layout and a real balance update remain user acceptance checks; no real balance is seeded or imported by implementation.

All 16 frontend tests, the production build and all seven database rollback suites passed for this foundation. Signed-out account read/update/balance/archive/restore HTTP calls returned 401. Post-test checks found no seeded balances or remaining mock accounts, with existing ledger records preserved. Advisor review adds the expected informational deny-all RLS finding for the new private table and unused-index information; it adds no security warning beyond the existing disabled-password-provider notice. See [RLS advisor](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy). Vite emits its bundle-size advisory at approximately 505 KB minified (145 KB gzip); the build completes. Route/vendor splitting can be handled separately as the app grows.


## Current net worth and balance visuals

This phase changes frontend calculation/presentation only; no schema, auth, RPC or stored household record changes. Pure tests verify currency separation, archived/excluded omissions, exact signed Assets/Debts/Net worth/Cash, credit balances and overdrafts, positive-only allocation and adjustments, missing versus zero, stale/date coverage, invalid snapshot omission, aggregate overflow and negative net worth. DOM checks verify summary cards/charts and partial coverage, chart/total account subsets and reset, direct account editing with updated overview, independent activity filters/currency selection, and honest missing/zero chart states. Existing finance/account/bulk/transfer/receipt tests remain in the suite.

The graphics use SVG geometry/presentation attributes with exact values in ordinary HTML and SVG descriptions, with no inline style attributes or external chart library. DOM simulation does not establish native-browser SVG appearance, CSP enforcement or mobile visual acceptance; those remain user-facing acceptance checks. No fake historic series is plotted and no real household balances are used in fixtures.

All 20 frontend tests and the production build passed. The existing Vite bundle-size advisory remains (about 517 KB minified, 149 KB gzip); no new dependencies, database migrations or authenticated production data changes were required. Tests use fabricated snapshots and mocked RPCs.
