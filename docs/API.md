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
