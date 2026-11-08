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
