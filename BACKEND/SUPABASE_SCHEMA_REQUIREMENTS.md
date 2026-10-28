# Supabase schema information required for CampusShare

## Inspection result

The repository currently contains no first-party SQL schema, migration, or database definition files. Its backend has a categories request that refers to `categories`; that is only an existing code reference and is not verified against the project database. Supabase MCP inspection of project `kieihfixgbfiormlqhmi` returned a permission-denied error, so no live schema was read.

## Preferred schema-only export

If this repository has migrations, provide every ordered file under `supabase/migrations/` and any schema-definition files under `supabase/schemas/`. Include relevant migration files even if they only create functions, triggers, enums, policies, or grants. Do not include seed files or table rows.

If migrations are unavailable, from the linked project run:

```sh
supabase db dump --linked -f supabase/schema-only.sql
```

This exports schema DDL without table data and does not apply changes to the live database. Keep ACL statements: do not add `--no-acl` or `--no-privileges`, because grants are needed to understand API access. Review the export before sharing and remove connection strings or other credentials if any appear. Supabase CLI dump behavior and scope are documented in the [CLI reference](https://supabase.com/docs/reference/cli/supabase-db-dump).

The default dump excludes Supabase-managed schemas such as `auth` and `storage`. If CampusShare customizes those schemas, separately provide only the relevant migration or schema-only DDL for its auth-user triggers/functions and storage policies/references; never include `auth.users` records. See the [Supabase migration guide](https://supabase.com/docs/guides/local-development/overview).

## Required schema details

The migration files or export should make these details reviewable:

- Tables and columns, including types, nullability, defaults, generated/identity behavior, and comments where they describe intent.
- Primary keys, unique constraints, foreign keys, delete/update actions, check constraints, indexes, enums, domains, and composite relationships.
- The resource/category relationship and any resource owner/profile relationship, without assuming names or cardinality.
- Profile linkage to Supabase Auth users, including any trigger/function that provisions or updates a profile.
- Borrowing/request entities, participants, resource linkage, status type or constraint, and any permitted transition logic.
- `GRANT`/`REVOKE`, default privileges, RLS enabled/forced state, and each policy's command, target roles, `USING`, and `WITH CHECK` expressions.
- Relevant views and their security mode; functions and triggers that affect authorization or data lifecycle.
- Storage buckets only if the app uses them, with object policies and the schema's references to stored paths/IDs.

Do not provide row data, user records, passwords, access/refresh tokens, database URLs, API keys, or service-role/secret keys. A schema-only artifact is enough; if it contains comments or function bodies with secrets, redact those before sharing while retaining the access-control logic.

## Authentication contract still needed

Please also state the intended sign-in providers, whether email confirmation is required, password reset behavior, signup policy, callback URLs, and which operations require an authenticated user. Describe the intended ownership and administrative roles and how a profile is created. Do not share credentials or tokens. The browser should use Supabase Auth and send its current access token to protected backend endpoints; the C++ service must verify the token and derive the user identity from verified claims before enforcing authorization. Details are in [Supabase Auth sessions](https://supabase.com/docs/guides/auth/sessions) and [JWT verification](https://supabase.com/docs/guides/auth/jwts).
