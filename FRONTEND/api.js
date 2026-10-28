// Frontend boundary for the known backend endpoints. Override this before this
// file loads by setting window.CAMPUSSHARE_API_BASE in the hosting page.
(function () {
    "use strict";

    const configuredBase = window.CAMPUSSHARE_API_BASE || "http://127.0.0.1:18080";
    const apiBase = configuredBase.replace(/\/+$/, "");

    async function getJson(path) {
        if (!path.startsWith("/api/")) {
            throw new Error("CampusShare API paths must start with /api/.");
        }

        const response = await fetch(apiBase + path, {
            method: "GET",
            headers: { Accept: "application/json" }
        });

        let data;
        try {
            data = await response.json();
        } catch (_error) {
            throw new Error("The CampusShare API returned invalid JSON.");
        }

        if (!response.ok) {
            const message = data && data.error && data.error.message;
            throw new Error(message || `CampusShare API request failed (${response.status}).`);
        }

        return data;
    }

    window.CampusShareApi = Object.freeze({
        health: function () {
            return getJson("/api/health");
        },
        categories: async function () {
            const records = await getJson("/api/categories");
            if (!Array.isArray(records)) {
                throw new Error("The categories endpoint did not return a JSON array.");
            }
            // Preserve records as-is: the database fields are not defined in this repository.
            return records;
        }
    });
})();
