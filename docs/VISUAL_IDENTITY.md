# Icons, logos and empty states

The agreed direction combines soft category badges, identity-first institution/merchant
images, matching Lucide outline navigation/actions, and small static empty-state scenes.
Labels remain visible; icons are decorative and hidden from assistive technology. There
are no new transaction actions or changes to accounting behavior.

## Everyday use

Settings → Icons & logos lets approved household members select a category, account or
payee and save its appearance. Category icon/color preferences apply in Transactions,
Settings, Reports and Budget. Account cards and transaction rows use institution images;
transaction descriptions and the Payee directory use payee images. Initials, account-type
icons and generic category shapes provide fallbacks. Account-type and category labels
remain available even when an image is missing. Empty-state illustrations appear for
search results, accounts, budgeting, tax setup and receipts.

Automatic account logo matching uses whole words in institution metadata or the account
name. Payee matching requires an exact normalized saved alias. Multiple matching brands
leave the fallback in place. Choosing a saved brand overrides inference; fallback-only
suppresses it. Restore automatic appearance removes visual overrides without altering the
record. Appearance writes have independent revisions and fail visibly on conflicts.

## Logo storage and future AI requests

Logo images and matching aliases live in the private database, separate from the public
code and from financial records. A small PNG catalog is deliberate: each image is capped
at 256×256 and 64 KB, and the collection at 128 brands. No public bucket, external logo
service, arbitrary URL renderer or browser request to a merchant is involved. The app
reads the catalog through its existing approved, server-verified passkey/session boundary;
images use only PNG data URLs allowed by the existing CSP. No images, account names,
merchant identities or icon selections are saved in browser persistent storage.

New logos require no code release: save a brand and refresh images (or reopen the app).
Start with explicit requests such as “Find official logos for missing merchants/accounts.”
An assistant should read the approved catalog and only necessary identity fields, source
an official image, rasterize/re-encode to a small PNG and strip metadata locally. Preserve
brand proportions/colors. Record the official HTTPS source, stable brand key and narrow
aliases. Never guess a match from an ambiguous name, alter imported records, or publish a
household-specific institution/payee list in GitHub. An unverified or unavailable image
keeps the fallback; images do not imply affiliation.

`household_visuals_v1` supports `visuals_get_catalog`, `visuals_save_preference` and
owner-only `visuals_save_brand`. The latter accepts key, name, aliases, png_base64 (null
clears the image), source_url and revision (0 creates; otherwise current revision).
Read the current revision before replacement. Direct table access is revoked; RLS remains
deny-by-default. Administrative connector updates can insert/update the same private
catalog after validation; do not invent user sessions or passkey claims to call owner RPCs.
Use a transaction, check the existing key/revision and read back the resulting metadata.
Never write storage.objects rows to pretend an image file has been uploaded.

## Validation

The SQL fixture uses fabricated users/records and rolls back. It checks shared brand
save/update/clear, PNG bounds, stale writes, appearance reset, original account invariants,
actual authenticated-role reads, owner/member separation and passkey/membership denial.
Model tests cover word boundaries, exact aliases, ambiguous matching and safe image URLs.
Browser checks use synthetic records to verify cross-page overrides, failed-save drafts,
reset, refreshable catalog and fallbacks, plus keyboard/accessibility and mobile overflow.
The full pre-existing financial workflow suite runs alongside these checks.

Payees now also support an explicitly fetched website icon; see
[Payee websites](PAYEES.md#websites-and-website-icons). Website images are private
small PNGs with source provenance. Manual appearance overrides retain priority.
