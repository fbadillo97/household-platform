# Current authentication cutover

Website: https://fbadillo97.github.io/household-platform/ . The owner has completed signup and enrolled two passkeys. The app now offers only passkey login. The database requires a live, approved, server-recorded passkey session for all household records and approval administration. Email-only sessions can see only their own access status and request membership.

**Remaining owner Dashboard action:** Authentication → Sign In / Providers → Email → turn off Enable Email provider and save. Do not turn off Confirm email instead, and do not disable Passkeys. This cannot be changed by the connected project tools. Afterward use Account security → Sign out all devices and sign back in with a passkey. Verify direct email OTP/password sign-in is disabled before calling the provider cutover complete. Disabling Email prevents the direct Auth enrollment route from being used as a routine email-based fallback; the app/database changes alone do not close that provider route.

Normal recovery is a second independent passkey. If all keys are lost, an administrator must deliberately verify identity and arrange controlled re-enrollment. No automatic email recovery is offered. Future household members require controlled initial enrollment; public self-service registration is paused while Email is disabled. Do not casually re-enable Email for recovery, since that can restore direct Auth credential-enrollment paths. New identity/recovery work needs its own reviewed procedure.

## Fixed Auth values

- Site URL and allowed callback: `https://fbadillo97.github.io/household-platform/`
- Passkey display name: `Household Platform`
- Passkey RP ID: `fbadillo97.github.io`
- Passkey origin: `https://fbadillo97.github.io`

The RP ID and origin have no project path. Keep the RP ID stable. Supabase currently labels passkeys experimental. The direct Auth credential-management APIs remain governed by Supabase; app database rules are not an Auth-provider hook.

## Deployment

The repository is public by the owner's choice. Changes to main trigger Publish GitHub Pages, which tests/builds with the project-site base and public Supabase configuration before uploading only dist/. Manual publication remains available. No service-role or secret key is bundled. `_headers` is not applied by GitHub Pages; meta CSP/referrer controls are present, while response-level frame/cache headers remain a hosting limitation. Real household records are never committed or built into the site.

## Acceptance still required

Complete the provider toggle and verify passkey sign-in after global sign-out. Exercise owner-approved/removed-user behavior in real browsers with mock records, and perform a separate encrypted backup/restore drill before real data. Do not expose household_private in Data API settings or give browser roles direct table privileges.
