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
