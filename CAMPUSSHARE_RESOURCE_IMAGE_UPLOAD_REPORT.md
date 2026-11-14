# CampusShare Resource Image Upload — Implementation Report

## Summary

CampusShare already had a real upload path: the browser uses the configured Supabase JavaScript client and the signed-in user's session to upload image bytes to the private `campusshare-resource-images` bucket; the C++ backend stores and reads image metadata; signed URLs restore images after refresh. This task hardened deletion, added primary-image selection for new uploads, rendered the ordered gallery in resource and request views, and prepared a staging-only Storage policy script.

This is **not live-verified**. No Supabase project was accessed, no SQL was executed, and no credentials or feature flags were changed. The repository's `SUPABASE_STAGING_MARKETPLACE_MIGRATION.sql` is currently **0 bytes**, so it cannot create the required `resource_images` table or the rest of the marketplace extension. Do not apply that empty file.

## Implemented behavior

- The form accepts multiple JPEG/JPG, PNG, and WebP files, previews them, allows removal and reordering before save, and lets the student choose the primary image. The first stored `sort_order` is the primary image.
- The browser enforces up to 10 photos and 5 MiB per file. Supabase bucket limits and Storage RLS remain the authoritative server-side controls.
- Uploads use a unique `<authenticated-user-id>/<resource-id>/<random-file>` path, the user's Supabase session, and `upsert: false`. The browser sends metadata through the existing authenticated C++ route; the API key and user Bearer token remain separate. No service-role key is used.
- If an upload or metadata save fails, the browser attempts to remove every attempted object path. If cleanup is denied, the UI reports that cleanup needs attention.
- Resource cards, details, My Resources, borrowing request cards, and sale/donation request cards load ordered metadata and short-lived signed URLs. The first image is styled as the main image; remaining images form the gallery.
- Saved-image deletion now goes through the authenticated C++ endpoint. It verifies the Auth user, reads the image metadata under the user's RLS, validates that the path is under that user's resource folder, removes the object through the Storage API using the same user JWT, then deletes the metadata under RLS. Resource deletion uses this path for each image before deleting the resource.
- The new [staging Storage policy proposal](</C:/Users/Anup Uikey/CampusShare/SUPABASE_STAGING_RESOURCE_IMAGES_STORAGE_POLICIES.sql>) configures authenticated reads for images attached to readable resources, owner-only uploads/deletes, no object update/upsert permission, and preflight checks. It assumes the reviewed `resources` and `resource_images` tables already exist. It was not executed.

## Files changed for this task

- [BACKEND/main.cpp](</C:/Users/Anup Uikey/CampusShare/BACKEND/main.cpp>) — authenticated Storage object deletion before metadata deletion.
- [BACKEND/tests/test_api.py](</C:/Users/Anup Uikey/CampusShare/BACKEND/tests/test_api.py>) — mock Storage deletion ordering, forwarding, and denial checks.
- [BACKEND/README.md](</C:/Users/Anup Uikey/CampusShare/BACKEND/README.md>) — updated image DELETE contract.
- [FRONTEND/app.js](</C:/Users/Anup Uikey/CampusShare/FRONTEND/app.js>) — primary selection, ordered galleries, cleanup, request-card photos, and backend-coordinated deletion.
- [FRONTEND/index.html](</C:/Users/Anup Uikey/CampusShare/FRONTEND/index.html>) — primary-photo form hint.
- [FRONTEND/style.css](</C:/Users/Anup Uikey/CampusShare/FRONTEND/style.css>) — main-photo and primary badge styling.
- [FRONTEND/tests/app.test.cjs](</C:/Users/Anup Uikey/CampusShare/FRONTEND/tests/app.test.cjs>) — multi-upload ordering, refresh gallery, request galleries, cleanup and deletion behavior.
- [SUPABASE_STAGING_MARKETPLACE_GUIDE.md](</C:/Users/Anup Uikey/CampusShare/SUPABASE_STAGING_MARKETPLACE_GUIDE.md>) — staging order and empty-migration warning.
- [SUPABASE_STAGING_RESOURCE_IMAGES_STORAGE_POLICIES.sql](</C:/Users/Anup Uikey/CampusShare/SUPABASE_STAGING_RESOURCE_IMAGES_STORAGE_POLICIES.sql>) — new, unexecuted staging-only policy proposal.
- [CAMPUSSHARE_RESOURCE_IMAGE_UPLOAD_REPORT.md](</C:/Users/Anup Uikey/CampusShare/CAMPUSSHARE_RESOURCE_IMAGE_UPLOAD_REPORT.md>) — this report.

`FRONTEND/api.js` already contained the authenticated image metadata methods, so it was reviewed but not changed in this task. Local `.env` and frontend local configuration were not opened or modified.

## Verification performed

- `node --test FRONTEND/tests/*.test.cjs` — **67 passed, 0 failed**.
- `node --check` on `FRONTEND/app.js`, `api.js`, `auth.js`, and `ui-model.js` — **passed**.
- Python AST parse of `BACKEND/tests/test_api.py` — **passed**.
- CMake/MSVC Release compilation of the changed C++ object — **passed**.
- Normal CMake Release link — **did not complete**: MSVC reported `LNK1104` because `campusshare_backend.exe` was locked by a running process. No process was stopped.
- The freshly compiled object was linked to a separate ignored `campusshare_image_validation.exe`; the full backend mock API suite against that executable — **passed**. This validates the code with mocks only, not Supabase.
- `git diff --check` — **passed**; Git printed existing LF-to-CRLF conversion warnings only.
- Staging SQL lexical checks (transaction boundary, required policy names, no service-role key pattern) — **passed**. No PostgreSQL parser was run; SQL syntax, grants, RLS behavior and Storage behavior remain unverified.
- `SUPABASE_STAGING_MARKETPLACE_MIGRATION.sql` — inspected by file length only: **0 bytes**. It was not changed or executed.

## Limitations and remaining risks

1. **Staging database is not ready from this checkout.** Restore the complete reviewed Task 12 schema/RPC migration before setting `SUPABASE_MARKETPLACE_ENABLED=true`. The empty migration is not usable.
2. The new Storage policies depend on a private bucket and the existing `resource_images` table plus its reviewed metadata RLS/grants. None were checked live. The script drops/recreates only the three named CampusShare Storage policies; a staging owner must inspect current definitions first.
3. The existing image metadata route checks count/order before insertion, but does not serialize concurrent uploads in PostgreSQL. Two simultaneous uploads can race the 10-image/order limit until an approved database constraint or transactional RPC is deployed. The local UI and backend validation do not prove concurrency safety.
4. Object deletion and metadata deletion span Storage and PostgREST, so they cannot be one transaction. The backend deletes the object first. If metadata deletion then fails, the metadata row remains and points to a missing object; retry the owner-authorized deletion to finish cleanup. If upload cleanup is denied, remove the listed orphan through the owner's authenticated session or the staging dashboard after review.
5. A newly selected photo can be made primary before upload. To replace an existing primary, remove the current primary, then add the replacement; changing the order of already-saved secondary photos is not implemented because the current verified database/API contract contains no reviewed atomic reorder operation.
6. No real Storage upload, signed-URL read, owner/non-owner staging check, post-refresh live display, or browser-to-staging integration test was performed.

## Manual staging steps

1. Confirm the dashboard project is **CampusShare-Staging** (`jxndjuslvccxgayoachm`). Do not use production credentials.
2. Restore and review the full staging marketplace migration. Do not run the current empty `SUPABASE_STAGING_MARKETPLACE_MIGRATION.sql`.
3. In the staging dashboard, create `campusshare-resource-images` as a **private** bucket, maximum size **5 MiB**, allowed MIME types `image/jpeg`, `image/png`, and `image/webp`.
4. Review the new policy proposal against the actual staging grants, policies and table definitions; then apply it to staging only after the `resource_images` table exists. Run the read-only marketplace verification queries afterward.
5. Keep RPC flags false. Only after schema, policies, and two-account RLS checks pass, set the local backend's marketplace flag for a staging-only run; keep all RPC flags disabled unless each RPC has separately passed staging review.
6. Sign in as the resource owner, create a listing with multiple photos, select a primary image, then edit it to add/remove photos. Refresh and sign out/in to confirm the ordered gallery returns. Try deletion from a second student account and confirm Storage denies it. Test an invalid type and a file larger than 5 MiB.
7. Stop the backend process before rebuilding its normal executable if the linker still reports that the target is in use.

No commit or push was made. The 24 pre-existing staged generated-file deletions remain staged and unchanged; unrelated working-tree changes were preserved.
