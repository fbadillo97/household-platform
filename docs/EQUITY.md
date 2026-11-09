# Net worth and secured-asset equity

The overview uses the accounting identity **assets = liabilities + equity**.
Liabilities fill the left segment and Equity labels the right, in
proportion to total assets. There is no unused background track. Net worth stays
centered above the bar and total assets label the whole. Negative equity or other
signed balances that cannot form positive proportions show exact signed totals
without a misleading stacked bar. Missing/invalid balances and currencies remain
separate. These are saved balances, not transaction-derived balances or quotes.

The **Equity breakdown** uses each included asset's saved value **minus the signed
balances of its included, linked debts**. Multiple debts can link to one asset;
each debt can link to one asset. Negative debt credits increase that asset's equity.
Positive equity alone creates donut slices. Negative equity is reported separately;
zero equity creates no slice. Missing linked balances make an asset's equity
incomplete, rather than showing its gross market value as known equity. Unsafe
integer aggregates are unavailable, never rounded into a chart.

Unlinked debts, debts linked to an excluded/archived asset, and unsecured credit
cards remain outside the slices but still contribute to total net worth. The
chart shows this unallocated debt/credit amount and known/missing counts explicitly.
It is not a proportional allocation of every liability across every asset. Category
percentages describe positive included equity, not shares of total net worth.
Different saved balance dates can affect the comparison. Link changes do not
rewrite dated balance history or alter net worth totals.

## Linking and correction

In **Accounts → Manage account**, a debt has an optional **Secured asset** field.
You can choose a non-debt asset in the same currency, or None / unsecured. New
debts also support this choice during creation. Saving is direct, without a second
review screen. Asset names, balances and account inclusion remain separate fields.
Equity-category drill-down opens both the assets and their linked debts for tracing.

AI-assisted data entry should create/resolve the asset first and set the debt's
`secured_asset_id` automatically from the supplied context. The user has approved
these links without a separate review step. For existing accounts, the assistant
can use private `household_private.set_account_security(payload, true)` with
`{id, revision, secured_asset_id}`. For an approved-passkey session, the public
RPC operation `set_account_security` passes administrative=false. Normal
`create_account`/`update_account` also accept nullable `secured_asset_id`.

Resolve the relationship from the provided asset/debt descriptions or source
identifiers. Do not distribute unrelated card debt or invent a relationship when
there are several plausible assets. Uncertain/unsecured debts remain visible as
unallocated and editable. This does not require a review queue or confirmation.
No paid in-app model or inference service is introduced by these entry interfaces.

The administrative helper is SECURITY INVOKER with browser-role execution revoked;
the public dispatcher cannot select administrative mode. Both entry paths validate
same-currency, non-debt target, no self-link and current revision. The database also
prevents changing a target's currency/type in a way that invalidates child links.
Private link events retain previous/new relationships and honest assistant/member
provenance. The history table has RLS and no browser grants. No financial snapshots,
transactions, source metadata or transfer links are rewritten by linking.

## Verification

`20261108185622_secured_asset_links.sql` is applied. Its filename was created with
the Supabase CLI and aligned with the hosted migration version. Migration plus
fabricated tests passed in a rollback transaction before application. Afterward,
secured-link, account, saved-history, automation and security SQL suites passed
with rollback fixtures. They cover stale writes, cross-currency/non-debt validation,
source/snapshot invariants, automatic administrative entry, audit provenance and
the approved-passkey/private-helper boundaries.

32 unit/DOM tests, 20 desktop/mobile Chromium cases and production builds passed.
New cases verify mortgage/vehicle equity, multiple debt links, credits, negative
and zero equity, missing linked balances, excluded cohorts and unchanged net worth.
Browser checks include accessible combined-bar labels, linking in the account
panel, equity rather than market value, drill-down, axe scans and page overflow.
Desktop/mobile chart screenshots were visually inspected.

Security advisors retain intentional private-table no-policy informational notices
and the existing [Auth leaked-password-protection warning](https://supabase.com/docs/guides/auth/password-security#password-strength-and-leaked-password-protection).
Performance review reports unused-index informational notices, including recent
history indexes, without missing foreign-key indexes. No Auth settings changed.
