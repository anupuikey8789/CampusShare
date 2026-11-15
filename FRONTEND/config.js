// Public browser configuration. A publishable/legacy anon key is intended for client use;
// never put a Supabase secret or service_role key here. Local values live in the
// ignored config.local.js file and are merged below.
const defaultHost = (typeof window !== "undefined" && window.location && window.location.hostname) ? window.location.hostname : "127.0.0.1";
window.CAMPUSSHARE_LOCAL_CONFIG_OVERRIDE = window.CAMPUSSHARE_CONFIG || null;
window.CAMPUSSHARE_CONFIG = {
    supabaseUrl: "https://jxndjuslvccxgayoachm.supabase.co",
    supabasePublishableKey: "sb_publishable_q1QUzaFWb3xW7bL-2bCkyQ_K5BBCa6_",
    apiBase: "https://campusshare-2kul.onrender.com"
};

(function (window) {
    "use strict";

    function isPublicKey(value) {
        if (typeof value !== "string" || !value.trim()) return false;
        const key = value.trim();
        if (key.startsWith("sb_publishable_") && key.length > "sb_publishable_".length) return true;
        const parts = key.split(".");
        if (parts.length !== 3 || typeof window.atob !== "function") return false;
        try {
            let payload = parts[1].replace(/-/g, "+").replace(/_/g, "/");
            while (payload.length % 4) payload += "=";
            return JSON.parse(window.atob(payload)).role === "anon";
        } catch (_error) {
            return false;
        }
    }

    const defaults = window.CAMPUSSHARE_CONFIG || {};
    const local = window.CAMPUSSHARE_LOCAL_CONFIG_OVERRIDE;
    if (local && isPublicKey(local.supabasePublishableKey)) {
        window.CAMPUSSHARE_CONFIG = Object.assign({}, defaults, local);
    } else {
        window.CAMPUSSHARE_CONFIG = defaults;
        if (local && local.supabasePublishableKey && window.console && window.console.warn) {
            window.console.warn("[CampusShare config] Ignoring invalid local public-key format; using configured defaults.");
        }
    }
    delete window.CAMPUSSHARE_LOCAL_CONFIG_OVERRIDE;
    window.CAMPUSSHARE_API_BASE = window.CAMPUSSHARE_CONFIG.apiBase;
})(window);
