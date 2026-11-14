# CampusShare authentication contract

## Current repository state

The frontend now loads the pinned Supabase JavaScript v2 client, supports email/password sign-up and sign-in, restores the SDK-managed browser session, and signs out through Supabase Auth. `FRONTEND/auth.js` supplies the current access token to `FRONTEND/api.js`; it does not create a second session store or log tokens. Protected backend routes verify the bearer token by calling Supabase Auth `GET /auth/v1/user` with the public API key. They use the returned `id` and forward the original bearer token to PostgREST, which enforces database grants and RLS. Local mocks exercise this contract only; live authentication has not been tested.

The reported RLS findings are preliminary rather than a complete security audit. Incomplete expressions and remaining policy/grant questions are recorded in [`SUPABASE_SCHEMA_REQUIREMENTS.md`](SUPABASE_SCHEMA_REQUIREMENTS.md). The backend must not use a service-role key or bypass RLS.

## Recommended boundary

1. Supabase Auth manages sign-in, passwords, session storage, access-token refresh, and sign-out in the browser.
2. The frontend sends the current short-lived access token as `Authorization: Bearer <access-token>` only to endpoints that require a signed-in user.
3. The C++ backend asks Supabase Auth to validate the bearer token and obtain the Auth user record before using its ID as caller identity. It fails closed if verification fails or is unavailable. It does not locally decode and trust JWT claims.
4. The backend derives the caller's user ID from the verified Auth response. It must not accept a request-body or query-string user ID as proof of identity; forward the caller token so Postgres grants and RLS enforce row access.
5. Authorization must not rely on user-editable `user_metadata`. If app roles are needed, their trusted source and freshness rules must be agreed and documented.
6. Keep passwords, access tokens, refresh tokens, provider secrets, database passwords, and Supabase secret/service-role keys out of source control and browser bundles. A publishable/legacy anon key is public configuration, not an authorization control; database access still depends on grants and RLS.

For database requests made on behalf of a signed-in user, the backend sends the verified caller's bearer token along with the public API key so Supabase evaluates the operation as that user. `profiles.id` has been confirmed to reference `auth.users(id)`, but profile provisioning still needs confirmation. The backend derives `owner_id` and `borrower_id`; it never trusts request-supplied identity fields. Resource updates are owner-scoped by verified RLS `USING` and `WITH CHECK` expressions. Borrow-request reads rely on the confirmed borrower and resource-owner SELECT policies, with RLS filtering rows. Borrow-request status changes remain disabled because `authenticated` has no UPDATE grant or UPDATE policy.

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

The frontend Auth session is connected to the API helper. Resource CRUD and borrowing request create/read are protected and covered by local mocks, not by live Auth or Data API calls. Borrow submission checks resource ownership/availability and the caller's own pending/approved request using the caller token; these prechecks are not an atomic global conflict guarantee. Read-only queries confirmed the absence of an authenticated borrowing-request UPDATE grant and UPDATE policy, so approve/reject/return operations are not implemented. Project sign-in settings, profile provisioning, remaining required columns/defaults, and live Data API behavior remain to be confirmed.
