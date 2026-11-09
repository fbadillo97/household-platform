# Finance roadmap

## Recurring and subscriptions — retained requirement

A dedicated **Finance → Recurring** page will track subscriptions, bills, income
and other repeated activity. Do not treat a tag or a rule as a recurring record.

Planned recurring records include payee, expected amount/range, currency,
frequency, next expected date, active/paused/ended status and linked transactions.
Transactions should link to their recurring record. Pattern detection can suggest
an item for tracking; confirmed deterministic recognition belongs in Settings →
Automations. Variable bills need ranges and exception handling. Disabling matching
and ending tracking are distinct; neither cancels the provider's service.

The current automation engine deliberately has no recurring classification action
until these records exist. A future action can link a recurring record through
another validated operation. AI should propose/configure the behavior while the
runtime remains inspectable and bounded. Preserve the distinction during future
Cash Flow and subscription reporting work.

## Cash Flow

Dedicated full-period statistics, separate from the latest-500 dashboard activity:
inflow/outflow/net trends, period comparisons, category/payee breakdowns and
transaction drill-down. Keep currencies separate and exclude transfers/card
payments consistently. No Cash Flow or Recurring page ships with Automations.

## Agreed follow-ups after visual identity

- Completed: Transactions date presets for calendar months/quarters/years, rolling
  six-month, one/two/five-year windows, all time and custom dates.
- Completed starter: Reports historical trends and a provisional three-month average
  forecast. Recurring items, scenarios, seasonality and goals remain future scope.
Date presets and the forecast starter were added after visual identity.
