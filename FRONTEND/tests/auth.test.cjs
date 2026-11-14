const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const test = require("node:test");
const vm = require("node:vm");

const frontend = path.resolve(__dirname, "..");

function evaluate(file, context) {
    vm.runInNewContext(fs.readFileSync(path.join(frontend, file), "utf8"), context, { filename: file });
}

test("frontend configuration exposes string project and API settings", () => {
    const context = {};
    context.window = context;
    evaluate("config.js", context);
    assert.equal(typeof context.CAMPUSSHARE_CONFIG.supabaseUrl, "string");
    assert.equal(typeof context.CAMPUSSHARE_CONFIG.supabasePublishableKey, "string");
    assert.equal(context.CAMPUSSHARE_API_BASE, context.CAMPUSSHARE_CONFIG.apiBase);
});

test("valid local frontend configuration overrides defaults without logging key values", () => {
    const warnings = [];
    const context = {
        CAMPUSSHARE_CONFIG: {
            supabaseUrl: "https://local-staging.supabase.co",
            supabasePublishableKey: "sb_publishable_local_override",
            apiBase: "http://127.0.0.1:18081"
        },
        console: { warn: (...args) => warnings.push(args) }
    };
    context.window = context;
    evaluate("config.js", context);
    assert.equal(context.CAMPUSSHARE_CONFIG.supabaseUrl, "https://local-staging.supabase.co");
    assert.equal(context.CAMPUSSHARE_CONFIG.supabasePublishableKey, "sb_publishable_local_override");
    assert.equal(context.CAMPUSSHARE_API_BASE, "http://127.0.0.1:18081");
    assert.deepEqual(warnings, []);
});

test("placeholder local key is ignored safely and never appears in diagnostics", () => {
    const warnings = [];
    const context = {
        CAMPUSSHARE_CONFIG: {
            supabaseUrl: "https://local-staging.supabase.co",
            supabasePublishableKey: "your-staging-publishable-key",
            apiBase: "http://127.0.0.1:18081"
        },
        console: { warn: (...args) => warnings.push(args) }
    };
    context.window = context;
    evaluate("config.js", context);
    assert.match(context.CAMPUSSHARE_CONFIG.supabasePublishableKey, /^sb_publishable_/);
    assert.notEqual(context.CAMPUSSHARE_API_BASE, "http://127.0.0.1:18081");
    assert.doesNotMatch(JSON.stringify(warnings), /your-staging-publishable-key/);
});

function setup({ configured = true, session = null, refreshedSession = null, refreshError = null } = {}) {
    const calls = [];
    const requests = [];
    const diagnostics = [];
    let currentSession = session;
    let currentRefreshedSession = refreshedSession;
    let authListener;
    const client = {
        auth: {
            getSession: async () => ({ data: { session: currentSession }, error: null }),
            refreshSession: async () => {
                calls.push(["refreshSession"]);
                if (refreshError) return { data: { session: null }, error: refreshError };
                if (currentRefreshedSession) currentSession = currentRefreshedSession;
                return { data: { session: currentSession }, error: null };
            },
            signUp: async (credentials) => {
                calls.push(["signUp", credentials]);
                return { data: { user: { id: "mock-user" }, session: currentSession }, error: null };
            },
            signInWithPassword: async (credentials) => {
                calls.push(["signInWithPassword", credentials]);
                return { data: { user: { id: "mock-user" }, session: currentSession }, error: null };
            },
            signOut: async () => {
                calls.push(["signOut"]);
                if (authListener) authListener("SIGNED_OUT", null);
                return { error: null };
            },
            onAuthStateChange: (callback) => {
                authListener = callback;
                calls.push(["onAuthStateChange"]);
                return { data: { subscription: { unsubscribe() {} } } };
            }
        },
        storage: {
            from: (bucket) => ({
                upload: async (path, file, options) => { calls.push(["storage.upload", bucket, path, file.type, options]); return { data: { path }, error: null }; },
                remove: async (paths) => { calls.push(["storage.remove", bucket, paths]); return { data: paths, error: null }; },
                createSignedUrls: async (paths, expires) => { calls.push(["storage.signedUrls", bucket, paths, expires]); return { data: paths.map((path) => ({ path, signedUrl: "https://signed.test/image" })), error: null }; }
            })
        }
    };
    const context = {
        CAMPUSSHARE_CONFIG: configured
            ? { supabaseUrl: "https://mock-project.supabase.co", supabasePublishableKey: "sb_publishable_test" }
            : { supabaseUrl: "", supabasePublishableKey: "" },
        supabase: { createClient: (url, key, options) => {
            calls.push(["createClient", url, key, options]);
            return client;
        } },
        CAMPUSSHARE_API_BASE: "http://127.0.0.1:18080",
        fetch: async (url, options) => {
            requests.push({ url, options });
            return { status: 200, ok: true, json: async () => [] };
        },
        calls,
        requests,
        diagnostics,
        setRefreshedSession(value) { currentRefreshedSession = value; },
        console: {
            info: (...args) => diagnostics.push(args),
            debug: (...args) => diagnostics.push(args),
            warn: (...args) => diagnostics.push(args)
        }
    };
    context.window = context;
    evaluate("api.js", context);
    evaluate("auth.js", context);
    return context;
}

test("Supabase Auth adapter uses v2 email/password methods and restores a session", async () => {
    const context = setup({ session: { access_token: "mock-access-token" } });
    assert.equal(context.CampusShareAuth.isConfigured, true);
    assert.equal((await context.CampusShareAuth.getSession()).data.session.access_token, "mock-access-token");
    context.CampusShareAuth.onAuthStateChange(() => {});
    assert.equal(context.calls[0][3].auth.persistSession, true);
    assert.equal(context.calls[0][3].auth.autoRefreshToken, true);
    await context.CampusShareAuth.signUp("student@example.test", "mock-password", "Test Student");
    await context.CampusShareAuth.signIn("student@example.test", "mock-password");
    await context.CampusShareAuth.signOut();
    assert.deepEqual(context.calls.map((call) => call[0]), [
        "createClient", "onAuthStateChange", "signUp", "signInWithPassword", "signOut"
    ]);
    const signupPayload = context.calls.find((call) => call[0] === "signUp")[1];
    assert.equal(signupPayload.options.data.full_name, "Test Student");
});

test("resource image Storage uses the user's configured Supabase client and private bucket", async () => {
    const context = setup({ session: { access_token: "mock-access-token" } });
    const file = { type: "image/png", size: 20 };
    assert.equal((await context.CampusShareAuth.uploadResourceImage("user/17/photo.png", file)).error, null);
    assert.equal((await context.CampusShareAuth.removeResourceImages(["user/17/photo.png"])).error, null);
    assert.equal((await context.CampusShareAuth.createResourceImageUrls(["user/17/photo.png"])).data[0].signedUrl, "https://signed.test/image");
    const storageCalls = context.calls.filter((call) => call[0].startsWith("storage."));
    assert.deepEqual(storageCalls.map((call) => call[0]), ["storage.upload", "storage.remove", "storage.signedUrls"]);
    assert.ok(storageCalls.every((call) => call[1] === "campusshare-resource-images"));
    assert.equal(storageCalls[0][4].upsert, false);
    assert.doesNotMatch(JSON.stringify(storageCalls), /service_role|sb_secret|mock-access-token/);
});

test("category and resource GET calls send the current session Bearer token", async () => {
    const context = setup({ session: { access_token: "mock-access-token" } });
    await Promise.all([context.CampusShareApi.getCategories(), context.CampusShareApi.getResources()]);
    assert.deepEqual(context.requests.map((request) => request.url), [
        "http://127.0.0.1:18080/api/categories",
        "http://127.0.0.1:18080/api/resources"
    ]);
    for (const request of context.requests) {
        assert.equal(request.options.headers.Authorization, "Bearer mock-access-token");
    }
    const diagnostics = JSON.stringify(context.diagnostics);
    assert.match(diagnostics, /bearerTokenPresent/);
    assert.doesNotMatch(diagnostics, /mock-access-token|sb_publishable_test/);
});

test("a valid login session is the same session used by the category request", async () => {
    const context = setup({ session: null });
    const signedInSession = { access_token: "login-access-token" };
    const authClient = context.supabase;
    const originalCreateClient = authClient.createClient;
    // The fake sign-in call returns a persisted session through the same SDK state.
    const createdClient = originalCreateClient("https://mock-project.supabase.co", "sb_publishable_test", {});
    createdClient.auth.signInWithPassword = async () => ({
        data: { user: { id: "mock-user" }, session: signedInSession }, error: null
    });
    createdClient.auth.getSession = async () => ({ data: { session: signedInSession }, error: null });
    context.CampusShareAuth = undefined;
    // Re-evaluate with the client that returns a session after a successful sign-in.
    context.supabase.createClient = () => createdClient;
    evaluate("auth.js", context);
    await context.CampusShareAuth.signIn("student@example.test", "mock-password");
    await context.CampusShareApi.getCategories();
    assert.equal(context.requests[0].options.headers.Authorization, "Bearer login-access-token");
});

test("a rejected expired token is refreshed once and the new token is retried", async () => {
    const context = setup({
        session: { access_token: "expired-access-token" },
        refreshedSession: { access_token: "fresh-access-token" }
    });
    const categoryRows = [{ id: 1, name: "Study Materials", created_at: "2026-11-13T00:00:00Z" }];
    context.fetch = async (url, options) => {
        context.requests.push({ url, options });
        if (options.headers.Authorization === "Bearer expired-access-token") {
            return { status: 401, ok: false, json: async () => ({ error: { code: "auth_rejected", message: "rejected" } }) };
        }
        return { status: 200, ok: true, json: async () => categoryRows };
    };
    const rows = await context.CampusShareApi.getCategories();
    assert.equal(rows.length, 1);
    assert.equal(context.requests.length, 2);
    assert.equal(context.requests[1].options.headers.Authorization, "Bearer fresh-access-token");
    assert.equal(context.calls.filter((call) => call[0] === "refreshSession").length, 1);
    const diagnostics = JSON.stringify(context.diagnostics);
    assert.doesNotMatch(diagnostics, /expired-access-token|fresh-access-token|sb_publishable_test/);
});

test("backend Auth rejection after refresh is reported safely and does not retry indefinitely", async () => {
    const context = setup({
        session: { access_token: "old-access-token" },
        refreshedSession: { access_token: "new-access-token" }
    });
    context.fetch = async (url, options) => {
        context.requests.push({ url, options });
        return { status: 401, ok: false, json: async () => ({ error: { code: "auth_rejected", message: "rejected" } }) };
    };
    await assert.rejects(context.CampusShareApi.getCategories(), /same staging project and public key/);
    assert.equal(context.requests.length, 2);
    assert.equal(context.calls.filter((call) => call[0] === "refreshSession").length, 1);
    const diagnostics = JSON.stringify(context.diagnostics);
    assert.doesNotMatch(diagnostics, /old-access-token|new-access-token|sb_publishable_test/);
});

test("an expired session that cannot refresh prompts login and does not retry the API", async () => {
    const context = setup({
        session: { access_token: "expired-access-token" },
        refreshError: new Error("mock refresh failure")
    });
    context.fetch = async (url, options) => {
        context.requests.push({ url, options });
        return { status: 401, ok: false, json: async () => ({ error: { code: "auth_rejected" } }) };
    };
    await assert.rejects(context.CampusShareApi.getCategories(), /session expired or could not be refreshed/i);
    assert.equal(context.requests.length, 1);
    const diagnostics = JSON.stringify(context.diagnostics);
    assert.doesNotMatch(diagnostics, /expired-access-token|mock refresh failure|sb_publishable_test/);
});

test("categories API accepts empty results, returns categories, and reports upstream failure", async (t) => {
    await t.test("non-empty result", async () => {
        const context = setup({ session: { access_token: "mock-access-token" } });
        const originalFetch = context.fetch;
        context.fetch = async (...args) => {
            const response = await originalFetch(...args);
            response.json = async () => [{ id: 42, name: "Books", created_at: "2026-01-01T00:00:00Z" }];
            return response;
        };
        const categories = await context.CampusShareApi.getCategories();
        assert.equal(categories.length, 1);
        assert.equal(categories[0].id, 42);
    });
    await t.test("empty result", async () => {
        const context = setup({ session: { access_token: "mock-access-token" } });
        assert.deepEqual(await context.CampusShareApi.getCategories(), []);
    });
    await t.test("upstream failure", async () => {
        const context = setup({ session: { access_token: "mock-access-token" } });
        context.fetch = async () => ({
            status: 502,
            ok: false,
            json: async () => ({ error: { code: "upstream_error", message: "Could not retrieve categories." } })
        });
        await assert.rejects(context.CampusShareApi.getCategories(), /Could not retrieve categories/);
    });
});

test("resource details uses the authenticated detail route and validates its one-row response", async (t) => {
    await t.test("valid resource", async () => {
        const context = setup({ session: { access_token: "mock-access-token" } });
        const row = { id: "resource-1", title: "Book", owner_id: "student-a" };
        const originalFetch = context.fetch;
        context.fetch = async (...args) => {
            const response = await originalFetch(...args);
            response.json = async () => [row];
            return response;
        };
        const result = await context.CampusShareApi.resource("resource-1");
        assert.equal(result.id, row.id);
        assert.equal(result.title, row.title);
        assert.equal(context.requests[0].url, "http://127.0.0.1:18080/api/resources/resource-1");
        assert.equal(context.requests[0].options.headers.Authorization, "Bearer mock-access-token");
    });
    await t.test("invalid response shape", async () => {
        const context = setup({ session: { access_token: "mock-access-token" } });
        context.fetch = async () => ({ status: 200, ok: true, json: async () => [] });
        await assert.rejects(context.CampusShareApi.resource("resource-1"), /invalid response/);
    });
});

test("resource CRUD and borrowing API methods use the authenticated backend routes", async () => {
    const context = setup({ session: { access_token: "mock-access-token" } });
    await context.CampusShareApi.createResource({ title: "Book", category_id: "cat-1", resource_type: "book", availability_status: "available" });
    await context.CampusShareApi.updateResource("resource-1", { availability_status: "unavailable" });
    await context.CampusShareApi.deleteResource("resource-1");
    await context.CampusShareApi.createBorrowRequest({ resource_id: "resource-1" });
    await context.CampusShareApi.borrowRequests();
    await context.CampusShareApi.approveBorrowRequest("42", null);
    await context.CampusShareApi.rejectBorrowRequest("42");
    await context.CampusShareApi.returnBorrowedResource("42");
    assert.deepEqual(context.requests.map((request) => [request.options.method, request.url]), [
        ["POST", "http://127.0.0.1:18080/api/resources"],
        ["PATCH", "http://127.0.0.1:18080/api/resources/resource-1"],
        ["DELETE", "http://127.0.0.1:18080/api/resources/resource-1"],
        ["POST", "http://127.0.0.1:18080/api/borrow-requests"],
        ["GET", "http://127.0.0.1:18080/api/borrow-requests"],
        ["POST", "http://127.0.0.1:18080/api/borrow-requests/42/approve"],
        ["POST", "http://127.0.0.1:18080/api/borrow-requests/42/reject"],
        ["POST", "http://127.0.0.1:18080/api/borrow-requests/42/return"]
    ]);
    for (const request of context.requests) {
        assert.equal(request.options.headers.Authorization, "Bearer mock-access-token");
    }
    assert.deepEqual(JSON.parse(context.requests[5].options.body), { due_at: null });
    assert.deepEqual(JSON.parse(context.requests[6].options.body), {});
    assert.deepEqual(JSON.parse(context.requests[7].options.body), {});
    assert.deepEqual(JSON.parse(context.requests[0].options.body), {
        title: "Book", category_id: "cat-1", resource_type: "book", availability_status: "available"
    });
});

test("marketplace APIs use authenticated backend routes and preserve request payloads", async () => {
    const context = setup({ session: { access_token: "mock-access-token" } });
    await context.CampusShareApi.transferRequests();
    await context.CampusShareApi.createTransferRequest("17", "sell");
    await context.CampusShareApi.approveTransferRequest("29");
    await context.CampusShareApi.rejectTransferRequest("29");
    await context.CampusShareApi.cancelTransferRequest("29");
    await context.CampusShareApi.completeSale("29");
    await context.CampusShareApi.completeDonation("29");
    await context.CampusShareApi.updateMarketplaceResource("17", { listing_mode: "sell", sale_price: 25 });
    await context.CampusShareApi.resourceImages("17");
    await context.CampusShareApi.addResourceImages("17", [{ storage_path: "user/17/photo.jpg", sort_order: 0 }]);
    await context.CampusShareApi.reorderResourceImages("17", [8, 9]);
    await context.CampusShareApi.deleteResourceImage("image-1");
    await context.CampusShareApi.handoverDetails("17");
    await context.CampusShareApi.saveHandoverDetails("17", { pickup_location: "Library", meeting_point: "Student center" });
    await context.CampusShareApi.reportListing("17", { reason: "other", details: "Review requested" });
    await context.CampusShareApi.myListingReports();
    await context.CampusShareApi.reviewListingReport("17", "resolved", "Reviewed");
    assert.deepEqual(context.requests.map((request) => [request.options.method, request.url]), [
        ["GET", "http://127.0.0.1:18080/api/marketplace/transfer-requests"],
        ["POST", "http://127.0.0.1:18080/api/resources/17/transfer-requests"],
        ["POST", "http://127.0.0.1:18080/api/marketplace/transfer-requests/29/approve"],
        ["POST", "http://127.0.0.1:18080/api/marketplace/transfer-requests/29/reject"],
        ["POST", "http://127.0.0.1:18080/api/marketplace/transfer-requests/29/cancel"],
        ["POST", "http://127.0.0.1:18080/api/marketplace/transfer-requests/29/complete-sale"],
        ["POST", "http://127.0.0.1:18080/api/marketplace/transfer-requests/29/complete-donation"],
        ["PATCH", "http://127.0.0.1:18080/api/resources/17"],
        ["GET", "http://127.0.0.1:18080/api/resources/17/images"],
        ["POST", "http://127.0.0.1:18080/api/resources/17/images"],
        ["POST", "http://127.0.0.1:18080/api/resources/17/images/reorder"],
        ["DELETE", "http://127.0.0.1:18080/api/resource-images/image-1"],
        ["GET", "http://127.0.0.1:18080/api/resources/17/handover"],
        ["PUT", "http://127.0.0.1:18080/api/resources/17/handover"],
        ["POST", "http://127.0.0.1:18080/api/resources/17/reports"],
        ["GET", "http://127.0.0.1:18080/api/marketplace/reports"],
        ["POST", "http://127.0.0.1:18080/api/marketplace/reports/17/review"]
    ]);
    for (const request of context.requests)
        assert.equal(request.options.headers.Authorization, "Bearer mock-access-token");
    assert.deepEqual(JSON.parse(context.requests[1].options.body), { request_type: "sell" });
    assert.deepEqual(JSON.parse(context.requests[9].options.body), { images: [{ storage_path: "user/17/photo.jpg", sort_order: 0 }] });
    assert.deepEqual(JSON.parse(context.requests[10].options.body), { image_ids: [8, 9] });
    assert.deepEqual(JSON.parse(context.requests[13].options.body), { pickup_location: "Library", meeting_point: "Student center" });
    assert.deepEqual(JSON.parse(context.requests[14].options.body), { reason: "other", details: "Review requested" });
    assert.deepEqual(JSON.parse(context.requests[16].options.body), { outcome: "resolved", notes: "Reviewed" });
});

test("missing config and missing session prevent authenticated API requests", async (t) => {
    await t.test("missing config", async () => {
        const context = setup({ configured: false });
        assert.equal(context.CampusShareAuth.isConfigured, false);
        await assert.rejects(context.CampusShareApi.getCategories(), /Sign in before using/);
        assert.equal(context.requests.length, 0);
    });
    await t.test("missing session", async () => {
        const context = setup();
        await assert.rejects(context.CampusShareApi.getResources(), /Sign in before using/);
        assert.equal(context.requests.length, 0);
    });
});

test("missing Supabase configuration notice is outside the login dialog", () => {
    const html = fs.readFileSync(path.join(frontend, "index.html"), "utf8");
    const noticeAt = html.indexOf('id="authConfigNote"');
    const dialogAt = html.indexOf('<dialog id="authDialog"');
    assert.notEqual(noticeAt, -1);
    assert.ok(noticeAt < dialogAt, "configuration guidance should be visible on the main page");
    assert.match(html.slice(noticeAt, noticeAt + 300), /Supabase Auth is not configured/);
    assert.match(html.slice(noticeAt, noticeAt + 300), /FRONTEND\/config\.local\.js/);
});

test("health API returns backend RPC feature flags without authentication", async () => {
    const context = setup();
    context.fetch = async (url, options) => {
        context.requests.push({ url, options });
        return {
            status: 200,
            ok: true,
            json: async () => ({
                status: "ok",
                features: { borrow_request_rpc_enabled: false, atomic_resource_update_rpc_enabled: false }
            })
        };
    };
    const health = await context.CampusShareApi.health();
    assert.equal(health.features.borrow_request_rpc_enabled, false);
    assert.equal(context.requests[0].url, "http://127.0.0.1:18080/api/health");
    assert.equal(context.requests[0].options.headers.Authorization, undefined);
});

test("API helper reports malformed JSON and HTTP errors", async (t) => {
    await t.test("malformed JSON", async () => {
        const context = setup({ session: { access_token: "mock-access-token" } });
        context.fetch = async () => ({ ok: true, status: 200, json: async () => { throw new Error("bad json"); } });
        await assert.rejects(context.CampusShareApi.getCategories(), /invalid JSON/);
    });
    await t.test("HTTP error", async () => {
        const context = setup({ session: { access_token: "mock-access-token" } });
        context.fetch = async () => ({ ok: false, status: 401, json: async () => ({ error: { message: "Unauthorized" } }) });
        await assert.rejects(context.CampusShareApi.getResources(), /Please log in again/);
    });
    await t.test("malformed record shapes", async () => {
        const context = setup({ session: { access_token: "mock-access-token" } });
        context.fetch = async () => ({ ok: true, status: 200, json: async () => [null] });
        await assert.rejects(context.CampusShareApi.getCategories(), /invalid response/);
        await assert.rejects(context.CampusShareApi.getResources(), /invalid response/);
        await assert.rejects(context.CampusShareApi.borrowRequests(), /invalid response/);
    });
});
