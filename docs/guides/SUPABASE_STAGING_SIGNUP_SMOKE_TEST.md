# CampusShare-Staging signup smoke test

Use this guide only with the staging project. Do not use a real personal account or the production project.

## Before signup

1. In Supabase Dashboard, confirm the selected project name is **CampusShare-Staging** and its reference is `jxndjuslvccxgayoachm`.
2. In `FRONTEND/config.js`, check that the configured project URL is the staging URL `https://jxndjuslvccxgayoachm.supabase.co` and that the publishable key belongs to that same staging project. Do not copy a secret or `service_role` key into the frontend.
3. Check `BACKEND/.env` locally: `SUPABASE_URL` and `SUPABASE_ANON_KEY` must point to this same staging project. Keep `.env` private and untracked. Do not paste keys in chat.
4. Start the backend and serve `FRONTEND` at the configured local origin, normally `http://localhost:5500`. The backend CORS allowlist must include that exact origin.
5. Confirm the staging Auth email/password provider and whether email confirmation is enabled. Do not change production Auth settings.

## Create one fresh test account

1. Use a fresh test email inbox that you control and that has never been registered in this project. Do not use your everyday/personal account.
2. Open the local CampusShare application after confirming its configuration points to staging.
3. Register with the fresh test email, a locally managed test password, and a test display name. Do not send the password to anyone or put it in a file or chat.
4. If email confirmation is enabled, open the message for the test inbox and complete confirmation. Then sign in if the application did not establish a session automatically.
5. In the staging dashboard, open **Authentication → Users**, find the new test account, and copy its user UUID locally for the verification query. Do not share the UUID or user record in chat.

## Verify that the profile trigger ran

1. Open `SUPABASE_STAGING_VALIDATION_NEXT.sql` in a text editor. In **QUERY 1**, replace only `PASTE_FRESH_STAGING_TEST_USER_UUID_HERE` with the test account UUID from the staging Auth dashboard.
2. Confirm the dashboard still shows **CampusShare-Staging** with reference `jxndjuslvccxgayoachm` before opening its SQL Editor.
3. Paste and run only **QUERY 1** in that staging project's SQL Editor. It returns four true/false values and does not display the test email or any user rows.
4. Expected result after successful signup: `auth_user_found=true`, `profile_found=true`, `profile_id_matches=true`, and `profile_email_matches=true`.
5. If `auth_user_found` is false, recheck that the UUID was copied correctly from the staging Auth user. If the Auth user exists but `profile_found` or either match is false, treat trigger provisioning as failed and stop testing resource/request operations. Do not manually insert a profile, weaken RLS, or delete the Auth user to hide the failure. Report only which booleans were false; do not send credentials or user details.

## What this test establishes

Passing this check demonstrates that this particular staging signup has a corresponding profile with a matching Auth UUID and email. It does not by itself audit RLS, grants, token verification, or the three status RPCs. The trigger screenshot evidence confirms trigger metadata, but runtime profile creation remains unverified until this smoke test is performed.
