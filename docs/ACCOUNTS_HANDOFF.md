# Accounts foundation handoff

Completed: Accounts tab, grouped account types, per-currency known-balance subtotals, dated manual snapshots, inclusion setting, revision-checked names/balances, recoverable archiving and ledger drill-through. Creation moved from Settings. Source data/transactions and the existing passkey-only access model remain separate. No actual household balances are in this repository.

Next agreed chunk: dashboard net worth/assets/debts/cash-available cards, assets-versus-debts bars and asset allocation visual. Follow with snapshot-based history charts in a later chunk. Do not invent earlier values or derive balances from the partial ledger.

Owning files: src/accounts.js, src/pages/AccountsPage.jsx, src/Finance.jsx, src/navigation.js; migration 20261108060703_account_balances.sql; supabase/tests/accounts.sql; tests/accounts.test.js and tests/accounts-ui.test.js. API details and limits are in docs/API.md; outstanding validation in docs/VALIDATION.md.

list_accounts returns balance_snapshot or null. Values use integer cents, account currency, as_of date and estimate flag. Latest snapshot is greatest as_of then newest sequence. All revisions/older same-day corrections remain in account_balance_snapshots; there is no browser history-list endpoint yet. Future charts need a checked history query and latest-per-date handling. A history point must state which accounts have balances and carry-forward ages, rather than silently treating missing values as zero.

For future current net worth, exclude archived and include_in_net_worth=false accounts. Sum checking/savings/investment/asset/legacy-other as assets and subtract signed credit/loan/mortgage amounts owed. Negative liabilities are credits; negative bank balances reduce assets. Checking and savings are cash, not investments/property. Never combine currencies without a deliberate verified FX feature. Show partial/missing and stale coverage prominently. The current section subtotals intentionally show all active listed balances, including excluded accounts; these are not net worth totals.

Types and currency are immutable after account creation to protect history and card-payment semantics. Source account metadata may mark currency as assumed; do not silently relabel or convert balances. Property/other values are estimates, investments use Market Value, bank accounts Balance, debts Amount owed. Existing source imports retain their earlier contract and do not populate balance snapshots. Archive is a recoverable visibility/net-worth setting, not deletion of historical ledger data or a ban on old imports.

Deployment: public GitHub repository fbadillo97/household-platform; GitHub Pages https://fbadillo97.github.io/household-platform/; separate Supabase project bmdautqjcjekztnbegfl in Canada Central. Use the existing approved-passkey checked RPC dispatcher, private schema/RLS and SessionFence. Tests remain fabricated; do not commit real records, credentials or balance exports.
