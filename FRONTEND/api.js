// Frontend boundary for the CampusShare backend. auth.js supplies the existing
// Supabase session's access token; this helper stores no token of its own.
(function () {
    "use strict";

    const configuredBase = window.CAMPUSSHARE_API_BASE || "http://127.0.0.1:18080";
    const apiBase = configuredBase.replace(/\/+$/, "");
    const requestTimeoutMs = Number.isFinite(window.CAMPUSSHARE_API_TIMEOUT_MS)
        ? Math.max(1, Math.min(window.CAMPUSSHARE_API_TIMEOUT_MS, 60000)) : 15000;
    let accessTokenProvider = null;

    function diagnostic(level, event, details) {
        const logger = window.console && window.console[level];
        if (typeof logger === "function") {
            logger.call(window.console, "[CampusShare API] " + event, details || {});
        }
    }

    async function requestJson(path, options, authenticated) {
        if (!path.startsWith("/api/")) {
            throw new Error("CampusShare API paths must start with /api/.");
        }

        const headers = { Accept: "application/json" };
        let token;
        if (authenticated) {
            if (typeof accessTokenProvider !== "function") {
                throw new Error("CampusShare authentication is not connected.");
            }
            token = await accessTokenProvider();
            if (typeof token !== "string" || token.length === 0) {
                if (path === "/api/categories") {
                    diagnostic("warn", "category request has no current access token", { path: path });
                }
                throw new Error("Sign in before using this CampusShare feature.");
            }
            headers.Authorization = `Bearer ${token}`;
            if (path === "/api/categories") {
                diagnostic("debug", "category request prepared", { path: path, bearerTokenPresent: true });
            }
        }
        if (options && options.body !== undefined) {
            headers["Content-Type"] = "application/json";
        }

        const send = async function () {
            const controller = typeof window.AbortController === "function" ? new window.AbortController() : null;
            let timedOut = false;
            const timer = controller ? window.setTimeout(function () {
                timedOut = true;
                controller.abort();
            }, requestTimeoutMs) : null;
            try {
                return await fetch(apiBase + path, {
                    ...options,
                    signal: controller ? controller.signal : (options && options.signal),
                    headers: { ...(options && options.headers ? options.headers : {}), ...headers }
                });
            } catch (error) {
                if (timedOut) {
                    const timeoutError = new Error("CampusShare API request timed out. Retry in a moment.");
                    timeoutError.code = "request_timeout";
                    throw timeoutError;
                }
                throw error;
            } finally {
                if (timer !== null) window.clearTimeout(timer);
            }
        };
        let response;
        try {
            response = await send();
        } catch (error) {
            if (error && error.code === "request_timeout") throw error;
            diagnostic("warn", "backend network or CORS request failed", {
                method: options && options.method ? options.method : "GET",
                path: path
            });
            throw new Error("CampusShare backend could not be reached. Check that it is running and allows this page's origin through CORS.");
        }
        async function readJson(currentResponse) {
            if (currentResponse.status === 204) return null;
            try {
                return await currentResponse.json();
            } catch (_error) {
                throw new Error("The CampusShare API returned invalid JSON.");
            }
        }

        let data = await readJson(response);
        const errorCode = data && data.error && data.error.code;
        if (authenticated && response.status === 401 && errorCode === "auth_rejected") {
            let refreshFailed = false;
            diagnostic("info", "backend rejected the current session; attempting one session refresh", {
                path: path,
                status: response.status,
                code: errorCode
            });
            try {
                const refreshedToken = await accessTokenProvider({ forceRefresh: true });
                if (typeof refreshedToken === "string" && refreshedToken.length > 0) {
                    headers.Authorization = `Bearer ${refreshedToken}`;
                    try {
                        response = await send();
                    } catch (retryError) {
                        if (retryError && retryError.code === "request_timeout") throw retryError;
                        diagnostic("warn", "backend retry after session refresh failed", { path: path });
                        throw new Error("CampusShare backend could not be reached after refreshing your session. Check that it is running and allows this page's origin through CORS.");
                    }
                    data = await readJson(response);
                } else {
                    refreshFailed = true;
                }
            } catch (_refreshError) {
                refreshFailed = true;
                diagnostic("warn", "session refresh failed", { path: path });
            }
            if (refreshFailed) {
                throw new Error("Your sign-in session expired or could not be refreshed. Please log in again.");
            }
        }

        if (!response.ok) {
            const message = data && data.error && data.error.message;
            diagnostic("warn", "backend returned an error response", {
                path: path,
                status: response.status,
                code: data && data.error && data.error.code ? data.error.code : "unknown"
            });
            if (response.status === 401 && authenticated) {
                if (data && data.error && data.error.code === "auth_rejected") {
                    throw new Error("The backend could not verify your refreshed session. Check that the backend is using the same staging project and public key as the frontend, then sign in again.");
                }
                throw new Error("Your sign-in session could not be authenticated. Please log in again.");
            }
            throw new Error(message || `CampusShare API request failed (${response.status}).`);
        }
        return data;
    }

    function get(path, authenticated) {
        return requestJson(path, { method: "GET" }, authenticated);
    }

    function post(path, body) {
        return requestJson(path, { method: "POST", body: JSON.stringify(body) }, true);
    }

    function patch(path, body) {
        return requestJson(path, { method: "PATCH", body: JSON.stringify(body) }, true);
    }

    function isRecord(value) {
        return value !== null && typeof value === "object" && !Array.isArray(value);
    }

    function isId(value) {
        return (typeof value === "string" && value.length > 0) ||
            (typeof value === "number" && Number.isFinite(value));
    }

    async function getCategories() {
        const records = await get("/api/categories", true);
        if (!Array.isArray(records) || !records.every(function (record) {
            return isRecord(record) && isId(record.id);
        })) {
            throw new Error("The categories endpoint returned an invalid response.");
        }
        return records;
    }

    async function getResources() {
        const records = await get("/api/resources", true);
        if (!Array.isArray(records) || !records.every(function (record) {
            return isRecord(record) && isId(record.id);
        })) {
            throw new Error("The resources endpoint returned an invalid response.");
        }
        return records;
    }

    window.CampusShareApi = Object.freeze({
        // Call with the existing Supabase client's session accessor, for example:
        // CampusShareApi.setAccessTokenProvider(async () => (await supabase.auth.getSession()).data.session?.access_token)
        setAccessTokenProvider: function (provider) {
            if (typeof provider !== "function") {
                throw new TypeError("An access token provider function is required.");
            }
            accessTokenProvider = provider;
        },
        health: async function () {
            const health = await get("/api/health", false);
            const featureNames = ["borrow_request_rpc_enabled", "borrow_status_rpc_enabled",
                "atomic_resource_update_rpc_enabled", "marketplace_enabled", "resource_images_enabled"];
            if (!isRecord(health) || health.status !== "ok" || health.api_version !== "1.0.0" ||
                typeof health.build_id !== "string" || !health.build_id || !isRecord(health.features) ||
                !featureNames.every(function (name) { return typeof health.features[name] === "boolean"; })) {
                diagnostic("error", "backend health contract is incompatible", {
                    apiVersionPresent: Boolean(health && typeof health.api_version === "string"),
                    featureFlagsPresent: Boolean(health && isRecord(health.features))
                });
                throw new Error("The running backend is outdated or incompatible. Rebuild and restart the latest CampusShare backend.");
            }
            return health;
        },
        getCategories: getCategories,
        getResources: getResources,
        categories: getCategories,
        resources: getResources,
        resource: async function (id) {
            const records = await get("/api/resources/" + encodeURIComponent(id), true);
            if (!Array.isArray(records) || records.length !== 1 ||
                !isRecord(records[0]) || !isId(records[0].id)) {
                throw new Error("The resource details endpoint returned an invalid response.");
            }
            return records[0];
        },
        createResource: function (resource) {
            return post("/api/resources", resource);
        },
        updateResource: function (id, changes) {
            return patch("/api/resources/" + encodeURIComponent(id), changes);
        },
        deleteResource: function (id) {
            return requestJson("/api/resources/" + encodeURIComponent(id), { method: "DELETE" }, true);
        },
        transferRequests: async function () {
            const rows = await get("/api/marketplace/transfer-requests", true);
            if (!Array.isArray(rows) || !rows.every(isRecord))
                throw new Error("The transfer-request endpoint returned an invalid response.");
            return rows;
        },
        createTransferRequest: function (resourceId, requestType) {
            return post("/api/resources/" + encodeURIComponent(resourceId) + "/transfer-requests", {
                request_type: requestType
            });
        },
        approveTransferRequest: function (requestId) {
            return post("/api/marketplace/transfer-requests/" + encodeURIComponent(requestId) + "/approve", {});
        },
        rejectTransferRequest: function (requestId) {
            return post("/api/marketplace/transfer-requests/" + encodeURIComponent(requestId) + "/reject", {});
        },
        cancelTransferRequest: function (requestId) {
            return post("/api/marketplace/transfer-requests/" + encodeURIComponent(requestId) + "/cancel", {});
        },
        completeSale: function (requestId) {
            return post("/api/marketplace/transfer-requests/" + encodeURIComponent(requestId) + "/complete-sale", {});
        },
        completeDonation: function (requestId) {
            return post("/api/marketplace/transfer-requests/" + encodeURIComponent(requestId) + "/complete-donation", {});
        },
        updateMarketplaceResource: function (id, changes) {
            return patch("/api/resources/" + encodeURIComponent(id), changes);
        },
        resourceImages: async function (resourceId) {
            const rows = await get("/api/resources/" + encodeURIComponent(resourceId) + "/images", true);
            if (!Array.isArray(rows) || !rows.every(isRecord))
                throw new Error("The resource image endpoint returned an invalid response.");
            return rows;
        },
        addResourceImages: function (resourceId, images) {
            return post("/api/resources/" + encodeURIComponent(resourceId) + "/images", { images: images });
        },
        reorderResourceImages: function (resourceId, imageIds) {
            return post("/api/resources/" + encodeURIComponent(resourceId) + "/images/reorder", { image_ids: imageIds });
        },
        deleteResourceImage: function (imageId) {
            return requestJson("/api/resource-images/" + encodeURIComponent(imageId), { method: "DELETE" }, true);
        },
        handoverDetails: async function (resourceId) {
            const rows = await get("/api/resources/" + encodeURIComponent(resourceId) + "/handover", true);
            if (!Array.isArray(rows) || !rows.every(isRecord))
                throw new Error("The handover endpoint returned an invalid response.");
            return rows[0] || null;
        },
        saveHandoverDetails: function (resourceId, details) {
            return requestJson("/api/resources/" + encodeURIComponent(resourceId) + "/handover", {
                method: "PUT", body: JSON.stringify(details)
            }, true);
        },
        reportListing: function (resourceId, report) {
            return post("/api/resources/" + encodeURIComponent(resourceId) + "/reports", report);
        },
        myListingReports: async function () {
            const rows = await get("/api/marketplace/reports", true);
            if (!Array.isArray(rows) || !rows.every(isRecord))
                throw new Error("The listing reports endpoint returned an invalid response.");
            return rows;
        },
        reviewListingReport: function (reportId, outcome, notes) {
            return post("/api/marketplace/reports/" + encodeURIComponent(reportId) + "/review", {
                outcome: outcome, notes: notes || null
            });
        },
        borrowRequests: async function () {
            const records = await get("/api/borrow-requests", true);
            if (!Array.isArray(records) || !records.every(function (record) {
                return isRecord(record);
            })) {
                throw new Error("The borrowing requests endpoint returned an invalid response.");
            }
            return records;
        },
        createBorrowRequest: function (request) {
            return post("/api/borrow-requests", request);
        },
        approveBorrowRequest: function (requestId, dueAt) {
            return post("/api/borrow-requests/" + encodeURIComponent(requestId) + "/approve", {
                due_at: dueAt == null ? null : dueAt
            });
        },
        rejectBorrowRequest: function (requestId) {
            return post("/api/borrow-requests/" + encodeURIComponent(requestId) + "/reject", {});
        },
        returnBorrowedResource: function (requestId) {
            return post("/api/borrow-requests/" + encodeURIComponent(requestId) + "/return", {});
        },
        conversations: function () {
            return get("/api/conversations", true);
        },
        conversationMessages: function (conversationId) {
            return get("/api/conversations/" + encodeURIComponent(conversationId) + "/messages", true);
        },
        sendMessage: function (conversationId, content, idempotencyKey) {
            if (!conversationId || typeof conversationId !== "string" || !conversationId.trim()) {
                return Promise.reject(new Error("A valid conversation ID is required."));
            }
            if (!content || typeof content !== "string" || !content.trim()) {
                return Promise.reject(new Error("Message content cannot be empty."));
            }
            return post("/api/conversations/" + encodeURIComponent(conversationId) + "/messages", {
                content: content.trim(),
                client_idempotency_key: idempotencyKey || ("cs_" + Date.now() + "_" + Math.random().toString(36).slice(2, 10))
            });
        },
        conversationMeetings: function (conversationId) {
            return get("/api/conversations/" + encodeURIComponent(conversationId) + "/meetings", true);
        },
        proposeMeeting: function (conversationId, proposal) {
            if (!conversationId || typeof conversationId !== "string" || !conversationId.trim()) {
                return Promise.reject(new Error("A valid conversation ID is required."));
            }
            if (!proposal || typeof proposal !== "object") {
                return Promise.reject(new Error("A meeting proposal object is required."));
            }
            const type = proposal.meeting_type || "handover";
            if (type !== "handover" && type !== "return") {
                return Promise.reject(new Error("meeting_type must be handover or return."));
            }
            if (!proposal.meeting_date || typeof proposal.meeting_date !== "string" || !proposal.meeting_date.trim()) {
                return Promise.reject(new Error("meeting_date is required."));
            }
            if (!proposal.meeting_time || typeof proposal.meeting_time !== "string" || !proposal.meeting_time.trim()) {
                return Promise.reject(new Error("meeting_time is required."));
            }
            if (!proposal.location || typeof proposal.location !== "string" || !proposal.location.trim()) {
                return Promise.reject(new Error("location is required."));
            }
            return post("/api/conversations/" + encodeURIComponent(conversationId) + "/meetings", {
                meeting_type: type,
                meeting_date: proposal.meeting_date.trim(),
                meeting_time: proposal.meeting_time.trim(),
                location: proposal.location.trim(),
                notes: proposal.notes ? proposal.notes.trim() : null
            });
        },
        respondToMeeting: function (proposalId, action) {
            if (!proposalId) {
                return Promise.reject(new Error("A valid proposal ID is required."));
            }
            if (action !== "accept" && action !== "decline" && action !== "cancel") {
                return Promise.reject(new Error("action must be accept, decline, or cancel."));
            }
            return post("/api/meetings/" + encodeURIComponent(proposalId) + "/respond", {
                action: action
            });
        },
        notifications: function () {
            return get("/api/notifications", true);
        },
        markNotificationsRead: function (options) {
            return post("/api/notifications/mark-read", {
                ids: (options && options.ids) || null,
                mark_all: Boolean(options && options.mark_all)
            });
        },
        requestReturn: function (conversationId) {
            return post("/api/conversations/" + encodeURIComponent(conversationId) + "/return-request", {});
        }
    });
})();
