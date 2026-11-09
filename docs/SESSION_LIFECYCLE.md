# Session lifecycle and tab focus

Supabase can emit SIGNED_IN when an existing session is recovered on tab focus.
Repeated INITIAL_SESSION, SIGNED_IN, TOKEN_REFRESHED and USER_UPDATED events for
the same user and session must not invalidate SessionFence, change the Finance
component key or remount open editors. Unsaved drafts stay in memory during
ordinary tab switching and token rotation.

The lifecycle identity compares the user ID and JWT session_id. Decoding these
claims is only for UI lifecycle comparison, never authorization. Invalid or absent
identity claims take the conservative reset path. A different user, different
session or sign-out invalidates in-flight responses and discards the previous
workspace. Browser session persistence remains disabled; no drafts or tokens are
added to local/session storage by this change.

Access checks still run every 30 seconds while visible and when the document
becomes visible, through the existing server access_state operation. Rejected,
removed or non-passkey access and protected API authorization failures continue
to clear the workspace. Hidden-document notifications no longer trigger extra
background checks. Existing database approval, live-session, passkey and role
checks are unchanged.

The App component is shared by the production entry and a separate mock browser
entry. Regression checks exercise real App/Finance components with synthetic auth
events and fabricated records, including tab switching, rotated tokens, new
sessions/users, revoked approval and missing passkey verification. The browser
fixture is not an authentication mode in the production build.

SDK behavior: https://supabase.com/docs/reference/javascript/auth-onauthstatechange
