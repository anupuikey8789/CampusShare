(function (window) {
    "use strict";

    const config = window.CAMPUSSHARE_CONFIG || {};
    const url = typeof config.supabaseUrl === "string" ? config.supabaseUrl.trim() : "";
    const publishableKey = typeof config.supabasePublishableKey === "string"
        ? config.supabasePublishableKey.trim()
        : "";
    const sdk = window.supabase;
    const validUrl = /^https:\/\//i.test(url) ||
        /^http:\/\/(?:localhost|127\.0\.0\.1)(?::\d+)?$/i.test(url);
    const configured = Boolean(validUrl && publishableKey && sdk && typeof sdk.createClient === "function");
    const client = configured ? sdk.createClient(url, publishableKey, {
        auth: {
            autoRefreshToken: true,
            persistSession: true,
            detectSessionInUrl: true
        }
    }) : null;
    let refreshInFlight = null;

    function diagnostic(level, event, details) {
        const logger = window.console && window.console[level];
        if (typeof logger === "function") {
            logger.call(window.console, "[CampusShare Auth] " + event, details || {});
        }
    }

    diagnostic(configured ? "info" : "warn", "client initialization", {
        configured: configured,
        sdkAvailable: Boolean(sdk && typeof sdk.createClient === "function")
    });

    function unavailable() {
        return {
            data: null,
            error: new Error("Supabase Auth is not configured. Copy FRONTEND/config.local.example.js to FRONTEND/config.local.js and set a valid staging project URL and publishable key.")
        };
    }

    function getSession(options) {
        if (!client) return Promise.resolve(unavailable());
        if (!options || options.forceRefresh !== true) return client.auth.getSession();

        if (!refreshInFlight) {
            refreshInFlight = client.auth.refreshSession().finally(function () {
                refreshInFlight = null;
            });
        }
        return refreshInFlight;
    }

    const auth = {
        isConfigured: configured,
        getSession: function () {
            return getSession();
        },
        signUp: function (email, password, fullName) {
            return client
                ? client.auth.signUp({
                    email: email,
                    password: password,
                    options: { data: { full_name: fullName } }
                })
                : Promise.resolve(unavailable());
        },
        signIn: function (email, password) {
            return client
                ? client.auth.signInWithPassword({ email: email, password: password })
                : Promise.resolve(unavailable());
        },
        signOut: function () {
            return client ? client.auth.signOut() : Promise.resolve(unavailable());
        },
        uploadResourceImage: async function (path, file) {
            if (!client) return unavailable();
            return client.storage.from("campusshare-resource-images").upload(path, file, {
                contentType: file.type,
                cacheControl: "3600",
                upsert: false
            });
        },
        removeResourceImages: async function (paths) {
            if (!client) return unavailable();
            return client.storage.from("campusshare-resource-images").remove(paths);
        },
        createResourceImageUrls: async function (paths) {
            if (!client) return unavailable();
            return client.storage.from("campusshare-resource-images").createSignedUrls(paths, 600);
        },
        onAuthStateChange: function (callback) {
            if (!client) {
                return { data: { subscription: { unsubscribe: function () {} } } };
            }
            return client.auth.onAuthStateChange(function (event, session) {
                diagnostic("debug", "session state changed", {
                    event: typeof event === "string" ? event : "unknown",
                    accessTokenPresent: Boolean(session && session.access_token)
                });
                callback(event, session);
            });
        }
    };

    window.CampusShareAuth = Object.freeze(auth);
    if (window.CampusShareApi) {
        window.CampusShareApi.setAccessTokenProvider(async function (options) {
            if (!client) return null;
            const forceRefresh = Boolean(options && options.forceRefresh === true);
            const result = await getSession({ forceRefresh: forceRefresh });
            if (result.error) throw result.error;
            const token = result.data && result.data.session
                ? result.data.session.access_token
                : null;
            diagnostic("debug", "current session checked for an API request", {
                accessTokenPresent: Boolean(token),
                forceRefresh: forceRefresh
            });
            return token;
        });
    }
})(window);
