# CampusShare authentication contract

## Current repository state

The current frontend has a small `CampusShareApi` helper for health and category GET requests. The page's “Login” button is presentational; there is no Supabase Auth client, sign-in/session flow, or access-token handling in the checked-in frontend. The C++ backend currently calls the Supabase Data API for categories using its configured publishable/anon key and does not authenticate application users. Resource CRUD, borrowing, and profile endpoints therefore must not be treated as implemented or protected today.

## Recommended boundary

1. Supabase Auth manages sign-in, passwords, session storage, access-token refresh, and sign-out in the browser.
2. The frontend sends the current short-lived access token as `Authorization: Bearer <access-token>` only to endpoints that require a signed-in user.
3. The C++ backend verifies the token's signature and relevant claims (including issuer, expiry, and subject) before using its subject as the caller identity. It must never treat a decoded-but-unverified JWT as authentication.
4. The backend derives the caller's user ID from the verified token. It must not accept a request-body or query-string user ID as proof of identity, and it must enforce ownership and role checks on the server for every protected operation.
5. Authorization must not rely on user-editable `user_metadata`. If app roles are needed, their trusted source and freshness rules must be agreed and documented.
6. Keep passwords, access tokens, refresh tokens, provider secrets, database passwords, and Supabase secret/service-role keys out of source control and browser bundles. A publishable/legacy anon key is public configuration, not an authorization control; database access still depends on grants and RLS.

For asymmetric JWT signing, the backend can verify signatures against the project's published JWKS. If the project uses legacy HS256 signing, use the Auth user-verification endpoint with the public API key and bearer token, or otherwise configure a safe verifier; do not copy the project's shared JWT signing secret into the application. Verify the project-specific issuer and accepted algorithms from its Auth/JWT configuration. See [Supabase sessions](https://supabase.com/docs/guides/auth/sessions) and [JWT signing keys](https://supabase.com/docs/guides/auth/jwts).

## Decisions needed before implementation

Please provide these policy choices (descriptions only; no secret values):

- Which sign-in methods are enabled: email/password, magic link/OTP, OAuth providers, or another method.
- Whether email confirmation is required, signup is open or invite-only, and how password reset should work.
- The approved application origin(s) and Auth callback/redirect URLs.
- Whether the frontend will use the official Supabase JavaScript client and its supported session persistence/refresh behavior.
- Which API operations are public versus authenticated, and which authenticated users may create, update, delete, or request/approve borrowing.
- Whether users can act on their own profile only, and how any admin/moderator role is assigned and verified.
- Whether a profile is created by a database trigger, by an authenticated application operation, or not required. The actual profile schema and trigger must be confirmed from the schema export before coding against it.
- Whether the C++ backend is intended to call Supabase as the signed-in user (forwarding the bearer token so RLS applies) or through another explicitly reviewed server-side authorization design. Do not configure a service-role key merely to bypass RLS.

Do not send actual login credentials, passwords, provider client secrets, tokens, or API keys in chat. Configure publishable frontend settings and server-only settings through local environment configuration, and keep them out of Git. A real access token is never needed for design or code review.

## Implementation status

This document defines a recommended contract only. Authentication is not implemented or live-tested. The project-specific auth settings, signing algorithm, actual profile relationship, grants, and RLS policies remain unverified because Supabase project access returned permission denied and no schema/migration files are present in the repository.
