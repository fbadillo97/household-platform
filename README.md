# Household Platform

Private household finance foundation, with property identifiers ready for future maintenance and document modules. React/Vite frontend, Supabase PostgreSQL, approved-member access, passkey controls, reviewed CSV imports. Mock records only until the remaining deployment and Auth checks pass.

## Current state

- This private repository contains code, migrations and fabricated fixtures only.
- The dedicated Household Platform database is active in Canada Central (`ca-central-1`).
- Both SQL migrations are already applied to that project. Do not rerun them manually.
- The owner email reservation is configured privately in the database. No owner identity was created and no email was sent by this setup.
- The frontend is ready to build; it is **not deployed** to a website yet.
- Email delivery, Auth URL configuration and passkey settings must be completed after choosing the permanent website address.

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

`npm run build` writes `dist/`. Host that directory on an HTTPS static host. Connect this private repository to a host that supports private GitHub repositories, or verify your GitHub Pages plan entitlement before using Pages. The included `_headers` file applies on hosts that support that convention; configure equivalent response headers on other hosts. It is not a substitute for database authorization. Do not deploy preview URLs as passkey enrollment origins.

See [deployment and sign-in setup](docs/DEPLOYMENT.md) before the first owner sign-in.

## How access works

1. A visitor requests an email sign-in link. Supabase verifies email ownership.
2. The app requests household access after verified sign-in. Ordinary new accounts are `pending` and receive no records.
3. The privately reserved owner email can bootstrap the single owner on its first verified sign-in. The first arbitrary registrant never becomes owner.
4. The owner sees pending requests and approves/rejects them. Approved members share finance read/write access. Members cannot see the approval queue or manage membership. The owner cannot be demoted/removed through the browser API.
5. Approved members can enroll and manage passkeys; sign-in links remain the recovery path. A passkey proves identity, **not** household approval. Supabase's passkey feature is experimental and must be enabled in the Dashboard.
6. Protected operations check the current verified non-anonymous Auth identity, live server-side session and current database membership. A removed account's old token cannot read records. A rejected/removed user cannot reset their own status by requesting again.

Passkey APIs are provided by Supabase Auth directly. The app restricts enrollment UI to approved members; an unapproved Auth account registering a credential directly would still have no household access. The owner approval gate is for application data, not an Auth-provider-level ban on creating identities.

There is one household per project. All approved members currently have the same finance write capabilities; no read-only role or granular property-level sharing is implemented. Do not approve people who should only see wishlist content. The wishlist uses a different project and membership list.

The browser keeps Auth sessions only in memory, so a reload requires another sign-in (or a newly opened email-link callback). It clears the protected view on sign-out or failed access checks and invalidates late responses. Access is rechecked every 30 seconds and on visibility changes. Already viewed records cannot be recalled. No financial data is placed in browser localStorage or service-worker caches.

## Finance workflow

Add a mock account, mock home/rental properties and optional categories. Upload `public/mock-transactions.csv`, which intentionally contains an identical payment and an invalid date. Preview validation and duplicate warnings, then explicitly confirm selected rows. Assign property/category references in the transaction table.

CSV: UTF-8, exact ordered headers `date,description,amount`, ISO dates, positive inflows/negative outflows, at most two decimal places. Client CSV limit is 1 MB / 5,000 rows; server independently checks structured payload size, types and each amount/date/description. Amounts are stored as integer cents. Only currencies with two decimal places are supported. No currency conversion or balances are inferred. Imports retain normalized staged rows, not original files or invalid raw values.

Duplicate warnings are scoped to one account and match date, normalized description and cents. Default selection excludes them. Explicit selection sends duplicate acknowledgments. Commits lock the batch and account, recheck duplicates, validate all selected IDs, and atomically insert transactions. A newly detected duplicate fails for renewed review. Identical legitimate payments can be deliberately retained. This is duplicate assistance, not statement reconciliation. Imported batches cannot be committed twice. Import previews/commits are restricted to the staging user.

Transactions are listed in date order, up to the latest 500 in the UI. The API supports account/property filtering and limit/offset pagination. Assignment updates and approval decisions require a revision to reject stale edits. A private audit table records successful record creation, imports, assignments and access decisions; there is no audit viewer yet.

This remains a transaction-ledger foundation: no reconciliation, opening balances, transfers, double-entry bookkeeping, tax reports, budgets, bank feeds, attachments, imports history UI or retention/purge UI. Documents and maintenance have extension points through property UUIDs but are not implemented.

## Database ownership and API

All records live in unexposed `household_private` tables with RLS enabled and no direct browser table grants. RLS intentionally has no allow policies: direct access is denied. The sole public endpoint is `household_v1(operation,payload)`, a SECURITY INVOKER wrapper around a checked private dispatcher. The private definer functions have fixed empty search paths, schema-qualified references, no dynamic SQL and restricted EXECUTE grants. They do not trust user-editable JWT metadata for approval/roles. See [API contract](docs/API.md).

Do not expose `household_private` in the Data API settings. Do not grant direct table access to `anon` or `authenticated`. Database administrators and project secret keys remain privileged; protect the Supabase and GitHub accounts with MFA.

Migrations are versioned in `supabase/migrations`. The first creates the foundation; the second qualifies staged-row columns in the import commit function. Those filenames match the project's applied migration history. Future changes need new migrations, database tests and advisor review. Supabase CLI 2.81.3 was used only to create migration files; hosted migrations were applied through the Supabase connector. CLI 3 has different target/confirmation behavior: read its help and current docs before deploying with it. No workflow automatically deploys database changes or requires a database secret.

## Verification and backups

`npm test` checks CSV parsing, explicit duplicate acknowledgement and late-response invalidation. `npm run build` validates the production bundle. `supabase/tests/security.sql` runs a full database verification inside a rollback transaction using fabricated Auth identities/sessions. It requires an administrative connection to a prepared Supabase database; never remove its final rollback or replace fixtures with real users. [Validation results](docs/VALIDATION.md) distinguish verified behavior from outstanding deployment checks.

Set up an independent encrypted backup/export and perform a restore drill before using real records. Verify your Supabase plan's backup/retention options rather than assuming they are included. Keep database dumps and receipt files outside Git. Project region controls primary data location; it does not guarantee that every log, email, static asset or service remains in Canada. Review any broader residency requirements before adding sensitive records.

Official references: [passkeys](https://supabase.com/docs/guides/auth/passkeys), [database functions](https://supabase.com/docs/guides/database/functions), [regions](https://supabase.com/docs/guides/platform/regions).
