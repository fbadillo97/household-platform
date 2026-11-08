# Website and Auth setup

No website has been published by this change. Choose a permanent HTTPS hostname before enrolling passkeys; changing the relying-party ID requires new passkey enrollment. GitHub stores code; Supabase runs the data and authentication services; a static host serves `dist/`.

## Frontend host

Connect the private `household-platform` GitHub repository to an HTTPS static host with private-repository support. Build command: `npm ci && npm run build`; output directory: `dist`; Node: 22. Set `VITE_SUPABASE_URL`, `VITE_SUPABASE_PUBLISHABLE_KEY` and optional `VITE_APP_BASE` in the host's build environment. Use the dedicated Canada Central project. No secret/service-role keys are needed for this app.

Inspect the deployed response headers. `_headers` is supplied for compatible hosts; otherwise set equivalent CSP, no-referrer, nosniff, deny-framing and no-store headers in the host's configuration. Assets and page are still publicly downloadable, which is expected; they contain no household records. Private data is fetched only after authorization.

## Supabase Auth Dashboard

Use the Household Platform project, not the wishlist project:

1. Authentication → URL Configuration: set Site URL to the exact production website URL and add the exact email callback URL, including its path/trailing slash. Add localhost separately only for development. Do not allow broad wildcard redirect URLs for production.
2. Keep email confirmation enabled. Keep anonymous sign-ins disabled. The intended request flow allows new email identities while household approval remains database-enforced. Do not treat enabling signups as granting household access.
3. Configure custom SMTP for email sign-in/recovery, with provider credentials stored only in Supabase. Supabase's default mail service is restricted; test real delivery once the website is ready. This change sends no emails and does not copy SMTP credentials from the wishlist.
4. Authentication → Passkeys: enable Passkey authentication. Display name: Household Platform. RP ID: the production bare hostname (no https, port or path). Allowed origin: the exact production HTTPS origin. Development can use localhost with separate development settings; avoid changing production RP ID after enrollment. Do not use the Supabase API hostname as the RP ID.
5. Review Auth rate limits and abuse protection before making account requests public. If SMTP or Auth settings cannot be verified, keep the app mock-only and unpublished.

## First owner sign-in and acceptance checks

The owner email is already reserved privately; it is absent from repository files. Once the live address and SMTP are configured, the owner requests their own sign-in link on the site and completes email verification. The checked database endpoint then creates the single approved owner membership. No first-user-wins bootstrap exists.

From the approved account, add a passkey, sign out, and sign in using it. Test an additional recovery route and a second device before relying on one credential. Supabase currently labels passkeys experimental; keep email recovery operational. Native enrollment/sign-in prompts must be tested on the user's real browser and password manager.

Use a separate approved test email account to request access. Confirm the pending screen displays without record requests, approve it from the owner account, then confirm records are available. Remove its access while it remains signed in and verify the next database operation fails and the protected screen clears. Rejected accounts should remain rejected after signing in again. Test only with mock records.

Do not paste database passwords, SMTP credentials, secret keys, email-link tokens or passkey responses into GitHub or chat. The connected setup does not need those secrets to inspect project state or apply approved schema changes.
