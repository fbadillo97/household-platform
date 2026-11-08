# Planning release verification

Taxes and Budget were integrated over the completed payee, automation and secured-asset
work. The final Net worth labeling adjustment was also preserved before publication.

## Passed

- 51 frontend calculation/DOM tests, including planning endpoint allowlists, exact money,
  refunds, category rollover, unknown coverage, years, evidence reuse and failed drafts.
- 24 integrated Chromium browser tests across desktop and Pixel 7, including the existing
  finance/payee/automation/equity workflows, plus Taxes/Budget navigation and editing,
  mock PDF upload/finish, atomic-flag preview, source views, refund link/unlink and public
  comparison mappings. Accessibility scans and horizontal-overflow checks passed.
- Production build with lazy Taxes/Budget modules and correct GitHub Pages subpath.
- Seven isolated PostgreSQL test groups passed against the actual repository migrations,
  using fabricated Supabase auth/storage boundaries and rollback-only records.
- The same seven groups passed on hosted Supabase with actual authenticated-role/RLS
  checks, prepared paths, stored passkey/session checks, denied OTP/revoked/missing
  sessions, annual copies, atomic/stale writes, source invariants, refund caps, history,
  profiles and mappings. Test records were rolled back.
- Hosted metadata confirmed private document bucket, anonymous RPC denial and no direct
  authenticated table access. New tax/budget tables were empty after verification.
- Source snapshot includes only public Statistics Canada data and fabricated test fixtures.

## Migration accounting

Applied planning version: `20261108234445_household_planning`. The locally generated
migration was aligned with the version recorded by Supabase. The existing category
accounting filename was aligned to its already-applied `20261108141844` version; that
classification migration was not rerun on hosted records.

## Practical limits

Browser document transport uses a mock store in automated UI tests; hosted checks verify
actual database/storage RLS and prepared-object metadata but do not upload bytes through
a live signed-in Supabase Storage HTTP session. No live household sign-in or real finance
data was used. Concurrent over-allocation is guarded by sorted source-row locks/revisions,
but these tests do not simulate multiple concurrent database clients.

The security advisor adds informational notices for the new intentionally deny-by-default
private tables, matching the existing API-only pattern. It found no new security warning.
The existing leaked-password-protection advisory remains; this change does not alter Auth
provider settings. See [the advisor explanation](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection) and
[private-table RLS notice](https://supabase.com/docs/guides/database/database-linter?lint=0008_rls_enabled_no_policy).

Goals, tax filing/form completion, inflation adjustment, FX conversion and inferred
composite peer groups remain outside this foundation.
