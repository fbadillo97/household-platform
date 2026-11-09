# Filtered transaction summary and Administration

The Transactions summary is returned in the same ledger response as its rows. Counts,
first/last records, attention flags and per-currency amounts use the complete filtered set,
not the current page or the dashboard sample. Sort and pagination do not change summary
values. Currency groups remain separate. Changing filters hides stale figures immediately;
failed requests and unsafe totals never display old or fabricated values.

## Calculations

- Count, first/last records and needs-attention flags include every matching entry.
- Money statistics exclude confirmed transfer/card-payment entries.
- Income/inflows counts regular credits and subtracts negative corrections in categories
  designated as Budget income in that posting month. This is not taxable income.
- Net spending counts regular posted purchases less valid allocated linked refunds.
  Known refund remainders and invalid linked credits are excluded from income and flagged.
- This is a bank-date table summary. Only matching transaction IDs contribute, including
  credits posted in the selected period/account/category. A refund filtered out of the
  table does not reduce the selected purchases. Budget purchase-date/account attribution
  can therefore produce a different planning/reporting figure.
- Net cash flow is income/inflows minus net spending.
- Average transaction is mean absolute posted amount of regular entries, including ordinary
  income and credits. Average expense and expense extremes use posted purchases before
  refunds, excluding income corrections. Both averages round to integer minor units.
- Expense ties use posted amount, date and ID for stable record links. First/last ties use
  date and ID. Empty denominators/extremes are absent, not invented zero transactions.
- A refunded category planned as income produces a visible monetary-calculation error;
  the matching table, counts and dates remain available for correction.
- Trash has an explicitly labelled historical preview and does not affect active reporting.

No original, balance, classification, receipt, refund allocation or import metadata is
changed by the summary. Currency/amount/date/review/payee/category/account/automation/
search/tag filters are the existing ledger predicates, shared before aggregation.

## Navigation and logs

Administration is an expandable sidebar group with Settings and Import / export logs.
Selecting another main section collapses it; selecting an administration child retains
its context. Direct links automatically open the group. Existing #settings and
#settings/automations links remain valid; new links use #administration/settings and
#administration/settings/automations. Logs use #administration/transfers.

Import coverage is removed from Dashboard and displayed under import logs. The paged
read-only log combines staged/completed CSV batches and source snapshots, with account,
source, range, time, status, counts and validation errors. Details stay in private storage;
no source payloads or user email addresses are returned. CSV counts come from saved
staging/commit metadata and original imported rows, including rows later moved to Trash.

The Exports tab reads recorded export_transactions, export_csv and export_tax_documents
operations from the protected audit log. Existing document downloads do not write those
events and are explicitly not represented as complete export history. The page does not
invent past events or introduce an export function. Future export workflows must record
these operations after successful export.

The public invoker wrapper household_admin_v1 exposes only admin_get_transfer_logs to
approved, server-verified passkey sessions. It has strict stream/pagination fields and
no direct browser table grants. Administration organization preserves existing household
permissions; it does not grant owner capabilities to another member.

## Verification

The rollback-only SQL fixture checks full-set totals beyond one page; income, partial
refunds/remainders, transfers, currencies, future records, date/account/category/review
filters, stable pagination/sorting, Trash, no-match states, income/refund conflicts,
original-record preservation, paged logs and authenticated/removed-member/anonymous grants.
Browser fixtures are fabricated. They cover summary filtering, record drill-down, stale
requests, accordion navigation, old deep links, relocated coverage, log retry/sign-out,
keyboard access, accessibility and page overflow on desktop and mobile.
