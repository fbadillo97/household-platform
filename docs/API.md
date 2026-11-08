# Household API v1

Supabase RPC: `POST /rest/v1/rpc/household_v1`. Headers: public project `apikey`, `Authorization: Bearer <user access token>`, JSON content type. In JavaScript use `client.rpc('household_v1', {operation, payload})`. The browser needs only a publishable key and the user's session. Anonymous requests cannot EXECUTE this endpoint.

All operations require a verified, non-anonymous user and active server-side session. Only `access_state` and `request_access` allow a not-yet-approved identity. Remaining operations require approved membership AND server-recorded passkey authentication for the current live session; approval administration additionally requires the owner role.

| Operation | Payload | Result |
|---|---|---|
| access_state | `{}` | Own status, role, revision, passkey_verified; no request is created |
| request_access | `{}` | Own status and passkey_verified; creates pending request or reserved owner bootstrap |
| list_requests | `{}` | Owner-only list of user_id/email/status/role/revision |
| decide_access | `{user_id,status,revision}` | Owner-only approved/rejected/removed decision |
| list_accounts / list_properties / list_categories | `{}` | Shared household resource arrays |
| create_account | `{name,kind,currency}` | Account UUID and fields |
| create_property | `{name,kind}` | Property UUID and fields |
| create_category | `{name}` | Category UUID and fields |
| list_transactions | `{account_id?,property_id?,limit?,offset?}` | Ordered transactions, max limit 500 |
| assign_transaction | `{id,revision,property_id,category_id}` | Updated transaction; null removes assignment |
| stage_import | `{account_id,rows:[{date,description,amount}]}` | Batch preview with errors/duplicate flags |
| preview_import | `{id}` | Creator-only batch preview |
| commit_import | `{id,row_ids,duplicate_ids:[]}` | Atomic inserted count; explicit duplicate acknowledgement |

Amounts are signed integer `amount_minor` cents in transaction responses; CSV amount inputs are decimal strings. IDs are UUIDs. Transactions have an integer revision. Import row IDs and duplicate acknowledgements must come from a current preview. All IDs and validation are checked independently in the database.

A successful `request_access` is not proof of approval: inspect `status`. Do not use user-editable JWT metadata, email suffixes or frontend state as authorization. No client-facing operation can set the owner email, assign owner role, access arbitrary tables or run SQL.

Permission failures use SQLSTATE 42501; invalid payloads 22023; missing imports P0002; stale revision/replay/duplicate-review conflicts 40001. Constraints may also reject malformed resource fields. Refresh before retrying a conflict, and clear protected views on authorization failure. There is no token/key in this document.


## Source snapshots

See [Monarch snapshot contract](MONARCH.md). `stage_monarch_snapshot` and `commit_monarch_snapshot` require an approved passkey-authenticated owner. `list_source_snapshots` requires approved passkey membership. All records remain in household_private. Transactions returned by list_transactions can include `source`, `external_id` and `source_data`; accounts may include source metadata and an explicit currency assumption.


## Accounting ledger

`list_ledger_transactions` requires an approved passkey session and returns `{rows,total,limit,offset}`. Filters: account_id (effective account), month (YYYY-MM), query, description, category_id (`__unassigned` for null), date_from/date_to, min_minor/max_minor (signed integer cents), tags. Sort: date/description/account/amount/category/tags; direction: asc/desc; deterministic UUID tie-breaker. Limit 1–500, default 50. No dynamic SQL is used. Dashboard uses the same effective row format, with a latest-500 overview limit.

Rows include effective description/account_id, original_description/original_account_id and override flags. These original fields support reset controls; source details and property columns are absent from the transaction UI.

`update_ledger_transaction` accepts id/revision and optional description_override, account_override_id, category_id. Explicit null clears an override. Missing keys preserve existing values. Description is 1–500 nonblank characters. Account must exist and have the original account's currency; amounts are never converted. Saves lock the transaction, reject stale revisions and add an audit event. Raw description, account_id, amount, fingerprint, source identity, source metadata and parked property assignments are untouched. Reimports compare raw source values, so local overrides do not cause duplicate source records or false source-change conflicts. Existing legacy API operations remain available for compatibility.


## Transaction details, review and receipts

`get_transaction_detail` `{id}` returns effective fields, originals, notes, tags_override (null uses original_tags), review_status, needs_attention, reviewed_at, deleted_at and active receipt metadata. `update_ledger_transaction` additionally accepts notes (0–10000 chars), review_status (unreviewed/reviewed), needs_attention (boolean), tags_override (null or up to 20 unique case-insensitive labels, each 1–60 chars). Existing revision locking applies; trashed transactions reject edits. Reviewed timestamps/actor are maintained server-side.

`list_ledger_transactions` also accepts review (`unreviewed`, `reviewed`, `needs_attention`) and trash_only (default false); it returns trash_total plus notes/review/receipt_count in rows. Search includes local notes and effective tags. `list_transactions` excludes Trash; legacy assignment rejects trashed IDs.

`trash_transaction` / `restore_transaction` `{id,revision}` change state, increment revision and audit the action. Both retain the raw row/source identity. No permanent transaction-delete endpoint exists.

`prepare_receipt` `{transaction_id,filename,mime_type,byte_size,sha256}` reserves an exact generated object_path, returning receipt id/revision/state and already_exists for a duplicate ready hash. Upload with the signed-in client's Storage bucket `household-receipts`, upsert false, at that path. Then `finish_receipt_upload` `{id,revision}` verifies the object exists with matching type/size before marking Ready. Pending duplicate retries reuse the same reserved path. Metadata changes do not increment the transaction revision.

To remove, first call authenticated Storage.remove for the path, then `finish_receipt_removal` `{id,revision}`. The latter refuses while a blob exists. Retry interrupted operations; do not delete `storage.objects` with SQL. `receipt_permission(text,text)` is the only authenticated private helper grant added for Storage RLS; it authorizes only exact prepared paths after checking the live verified passkey session and approval. Pending files are writable only by their uploader; Ready files are shared with approved household members. No update/upsert policy exists. Trash keeps reads but blocks upload/remove/finalization until restored. Direct receipt metadata table access remains denied.


## Transfer handling

All new operations require current approved passkey membership. Private helper EXECUTE is revoked from browser roles. Transactions add `flow_type` (`regular` default, `transfer`, `credit_card_payment`) and nullable unique self-reference `transfer_peer_id`; detail responses include a minimal `transfer_peer` with its current revision. Ledger responses include the fields and accept `flow`: regular/transfer/credit_card_payment/unlinked_transfer. Originals/source identity are unchanged.

- `list_transfer_candidates` `{id,days?:7|31,query?}` returns `{rows,total,days}`. Matches are active, unlinked, different effective accounts, same currency, nonzero equal/opposite amounts within the chosen date window. Text searches effective description/account name. Nearest 50 returned, ordered by date distance/date/UUID. Each includes revision and suggested_type. Matching never mutates data.
- `set_transaction_flow` `{id,revision,flow_type}` changes only an active unlinked record and increments revision. Card-payment classification must be an outflow from a non-credit account or inflow on a credit account. A classified single-side card payment cannot be moved to an incompatible account by ledger_update.
- `link_transfer` `{id,revision,peer_id,peer_revision,flow_type}` accepts transfer/credit_card_payment. It locks both rows in UUID order, revalidates both revisions, and checks active/unlinked, different effective accounts, same currency, equal/opposite nonzero amounts and <=31 days. Card-payment pairs must flow from a non-credit funding account to a credit account. Both rows receive reciprocal IDs, the chosen type, incremented revisions and audit events in one transaction.
- `unlink_transfer` `{id,revision,peer_id,peer_revision}` requires the exact current reciprocal link and revisions, locks both rows in UUID order, clears both peer IDs and restores both to regular with incremented revisions/audit events.

The three mutation operations return the initiating transaction detail. Pair operations do not infer amounts or rewrite source categories. Ledger account moves and Trash reject linked records until unlinked; ordinary details/receipt changes remain supported. Restore retains a standalone classification. No generic ledger payload key can update flow/peer fields. Dashboard excludes each non-regular entry before aggregating, including single-side records and pairs crossing account/month boundaries. Transfer matching is same-currency only; it does not reconcile statements or support split/FX/fee matching.


## Bulk metadata edits and Trash/Restore

`bulk_update_transactions` accepts `{items:[{id,revision}],action,value}`. It requires the same live, verified, approved passkey membership as individual changes. Items must be 1–50 unique UUIDs with positive integer revisions; duplicate/missing IDs, unknown request/item fields, invalid action/value and payloads over 20 KB are rejected. The UI selects the current page only; the API operates strictly on the explicitly supplied IDs, never all filter matches.

Actions/values:

| Action | Value |
|---|---|
| category | Existing category UUID or explicit null for Unassigned |
| review | reviewed / unreviewed |
| attention | JSON boolean |
| add_tag / remove_tag | One nonblank tag label, 1–60 characters |
| trash / restore | Ignored; client sends null |

All IDs are locked in UUID order, then existence, every revision and active/Trash state are checked before any write. Metadata edits require active rows. Trash rejects any linked transfer; Restore requires every selected row in Trash. No item is silently skipped for an error. Existing checked ledger/trash helpers perform the updates and auditing in the same transaction; any exception rolls back the entire batch, including earlier loop iterations. No-op values preserve revisions. Response: `{action,selected_count,updated_count}`. An extra per-updated-row `bulk_<action>` audit event records bulk intent. Private bulk helper EXECUTE is revoked from public/anon/authenticated.

Tag changes operate on each record's effective tags, case-insensitively adding once or removing the requested label while preserving other labels/order and raw source metadata. The existing 20-tag limit can reject an addition. No bulk payload can change raw source fields, description, account, date/amount, notes, receipt files or flow/link fields. Trash uses recoverable tombstones and keeps receipt files/source identity; restores retain standalone flow classification. Permission denial is 42501, invalid payload 22023, missing ID P0002 and stale/state/linked-Trash conflict 40001. On conflict refresh and explicitly select again.


## Account metadata and dated balances

`list_accounts` now returns all accounts, including archived ones for historical ledger references. Each has revision, include_in_net_worth, archived_at and nullable balance_snapshot `{id,as_of,amount_minor,currency,is_estimate,note}`. Latest is selected by as_of descending, then sequence descending with an indexed per-account lookup. A null snapshot means missing, never zero. Read still requires approved live-passkey membership.

- `create_account` `{name,kind,currency?,include_in_net_worth?}` supports checking/savings/credit/mortgage/loan/investment/asset plus legacy other. Currency defaults CAD, inclusion defaults true; no balance is synthesized.
- `update_account` `{id,revision,name?,include_in_net_worth?}` edits name/inclusion only. Type and currency cannot be rewritten. Imported source identity/metadata is preserved.
- `archive_account` / `restore_account` `{id,revision}` toggle recoverable archive state. Both retain all records and inclusion preference; same-state replay conflicts.
- `save_account_balance` `{id,revision,amount_minor,as_of,note?}` appends a snapshot and increments the account revision under the account row lock. Active accounts only. Whole cents within ±100000000000000; asset/other values nonnegative. Strict ISO dates from 1900 through server current_date; browser limits to local today. Note max 1000 chars. Currency and estimate flag derive from immutable account type/currency, never caller-provided values. No update/delete snapshot API is exposed.

The five mutations return the updated account record with its latest snapshot. They share existing 42501/P0002/22023/40001 authorization, missing, validation and stale-revision errors. Snapshots, their identity sequence and both new private helper functions have no browser grants; the unexposed table has deny-all RLS. Each successful mutation adds an audit event. None generates or recalculates ledger transactions. Account balance history is stored for the next UI phase; no net worth total/FX conversion is supplied by this foundation API.


## Balance history reader

`get_balance_history` is an approved-live-passkey-only, read-only dispatcher operation. Payload: `{scope:"net_worth"|"account",currency?,account_id?,from?,to?}`. Net worth requires a single three-letter currency and rejects account_id; account scope requires an existing UUID and derives currency (a supplied mismatch is rejected). Account scope may read archived/excluded records. Unknown fields are rejected. ISO dates must be valid, from >=1900, from<=to and to<=server current_date. The client passes local today explicitly. Missing from defaults to 90 days; explicit null means the earliest actual entry on/before to in the cohort.

The response contains scope/currency/from/to/earliest_available/cohort_policy/generated_at, minimal account metadata, and effective entries `{id,account_id,as_of,amount_minor,currency,is_estimate,note,correction_count,carry_in}`. Net-worth notes are null; individual notes retain the latest saved note. Current included/unarchived same-currency accounts define net worth cohort; the policy value is current_inclusion. Account policy is individual_account. Latest sequence wins for equal account/as_of dates. The response includes entries within the range plus one latest strict-before-range seed per account. Seed as-of dates stay original; no daily points or fake zero balances are stored or generated by SQL.

The existing `(account_id,as_of desc,sequence desc)` index supports lookups. More than 500 accounts, 10000 returned effective entries or an 8 MB JSON response is rejected (22023), never silently paginated/truncated. Missing account is P0002; permission denial remains 42501. The helper is in the unexposed schema with fixed empty search_path and no browser EXECUTE grant; access is only through the existing checked public wrapper. No table, Auth-provider or existing business grants change, and no snapshots/audit rows are written by the reader.

## Category-driven accounting behavior

Categories have an `accounting_behavior` of `regular` (default), `transfer`, or `credit_card_payment`. The Settings page edits this through `update_category_behavior` with `{id,accounting_behavior}`. New categories default to regular. The database applies the category default when a transaction is categorized, and applies category-rule changes to unlinked active transactions. Invalid credit-card direction is rejected atomically. Unassigned transactions are regular when their category is cleared. Explicit linked transfers retain their paired classification until unlinked; then category defaults apply. Original imported fields, amounts and source IDs are untouched. The existing `set_transaction_flow` dispatcher remains for backward compatibility but is no longer exposed in the user interface. The transaction detail form no longer has a separate transaction-type editor. Existing standalone classifications without a category change are preserved for audit until categorized or the relevant category rule changes.

## Payee directory and assignments

See [Payees](PAYEES.md#database-and-access) for the new private RPC operations,
ledger fields, recognition rules and atomic bulk payee action.

## Automations

See [Automations](AUTOMATIONS.md) for closed definition schemas, private assistant
configuration, on/off controls, activity and guarded Undo APIs.
