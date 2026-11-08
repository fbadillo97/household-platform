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
