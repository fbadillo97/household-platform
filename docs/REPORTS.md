# Recorded income and spending reports

Reports is a read-only workspace for monthly income/inflows, net spending, surplus or deficit,
category totals and an optional preceding equal-length comparison. Click a summary, monthly
bar or category to see the contributing records, then open the existing transaction editor.
All originals and existing edit protections are retained.

## Calculations

- Income/inflows includes regular positive incoming money, excluding linked refunds and
  remaining credits on a known refund. It is not a taxable-income calculation. Unmatched
  deposits can still be refunds; link those in Budget to reduce spending correctly.
- Regular negative transactions are spending. Negative corrections in a category explicitly
  designated as income in that month's Budget reduce income instead. Budget income itself
  uses selected income categories, so its income figure can differ from Reports inflows.
- Net spending is purchases less valid linked refunds. Full and partial refunds reuse Budget's
  exact allocations and per-currency refund timing (received date by default). Under purchase
  timing, credits are assigned to the original purchase date. Refunds follow the purchase
  category and account, including a credit received in another account.
- Transfers, card payments and Trash are excluded. Remaining linked credits are shown as
  needing review, not income. Invalid links raise a review notice; a refunded category planned
  as income must be corrected before a misleading report can be returned.
- Surplus is income/inflows minus net spending. Amounts remain integer minor units, checked
  against the safe client range. Currencies are never converted or combined.

Ranges are inclusive and limited to 732 days, ending today or earlier. Presets distinguish
this month so far from the last full month. Comparison uses the immediately preceding equal
number of days, with its dates shown; it is not necessarily the same calendar months.
Custom dates require Apply dates. Account filters include archived accounts and stay in memory.

## Coverage and source records

Totals use the complete supported currency ledger, not the dashboard's recent sample.
Missing imports are not assumed to mean zero household activity. Each month carries Budget's
explicit completed-month coverage confirmation only while its account-scope fingerprint still
matches. Selected partial months are labelled separately. Unconfirmed periods and comparisons
remain clearly identified as recorded activity. No percentage household-change claims are made.

The monthly chart has keyboard-selectable bars, exact accessible figures and independent scroll
containment. Category bars show net credits left of zero and spending right. Source pages show
bank date/amount alongside report date/impact and link to both refund and original purchase.
Pages contain up to 50 contributing entries; aggregate totals are not paginated. A purchase with
multiple allocations can contribute more than one entry. Supported ledgers are capped at 50,000
transactions per currency, responses at 8 MB and account selections at 100; exceeding limits
fails visibly instead of silently truncating totals.

## API and security

`household_reports_v1` routes only `reports_overview` and `reports_activity`. Strict payload
validation, server-recorded passkey/session verification and approved household membership
precede reads. Helpers have an empty search path and are not directly executable by browser
roles; the public invoker wrapper exposes only the guarded dispatcher to authenticated users.
There are no new tables or direct table grants. Reports never changes transactions, settings,
coverage confirmations, balances or imported data. Filters and financial values are not placed
in URLs or persistent browser storage. Stale requests are discarded on navigation/sign-out.

## Verification

`npm test` covers date boundaries, safe arithmetic and operation routing, alongside existing
features. `npm run test:planning:sql` compiles all migrations and runs synthetic rollback SQL
fixtures for planning and Reports. The Reports fixture checks exact totals, cross-month partial
refunds, purchase-account attribution, currencies, transfer exclusion, source pagination,
coverage, payload validation and session/member/role boundaries. Browser tests use fabricated
records only, exercise filters, charts, sources, keyboard access, retry/late responses and
sign-out, and scan desktop/mobile views for accessibility and page overflow.

## Trends & Forecasts starter

The Trends & Forecasts view uses the same account/currency filters and checked read-only
report API. Its chart shows the six calendar months before the current month. Exact figures
and source drill-down remain available. Latest-month changes are absolute recorded changes,
with unconfirmed imports labelled; partial current-month activity is excluded from history.

The simple forecast averages the three calendar months immediately before the current month,
then repeats those averages for three whole months starting with the current month. Current-
month actuals are not added to the estimates. It predicts recorded income/inflows, net
spending and net cash flow, not account balances, scheduled transactions or net worth.

Three consecutive full baseline months must each contain imported activity or an explicit
valid confirmation of zero activity. Missing/unconfirmed empty or partial months produce
“More history needed.” Invalid refund links require review first. Estimates based on
unconfirmed-but-present imports are provisional. Refund review exclusions, net-refund
baselines and the absence of seasonality, goals and one-off adjustments are disclosed.
No statistical confidence interval or guaranteed outcome is inferred. Arithmetic uses
BigInt-safe integer cents, checked before rendering, and rounds the mean to the nearest cent.

Future work may add recurring items, scenarios and goals after the desired scope is decided.
The starter does not create transactions or change balances/plans.
