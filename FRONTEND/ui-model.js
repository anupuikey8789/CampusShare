(function (window) {
    "use strict";

    function isOwnResource(resource, userId) {
        return Boolean(userId && resource && resource.owner_id != null &&
            String(resource.owner_id) === String(userId));
    }

    function filterResources(resources, options) {
        const settings = options || {};
        const query = String(settings.query || "").trim().toLocaleLowerCase();
        const minPrice = settings.minPrice === "" || settings.minPrice == null ? null : Number(settings.minPrice);
        const maxPrice = settings.maxPrice === "" || settings.maxPrice == null ? null : Number(settings.maxPrice);
        const condition = String(settings.condition || "all");
        return (Array.isArray(resources) ? resources : []).filter(function (resource) {
            if (!resource || typeof resource !== "object") return false;
            if (resource.listing_state === "withdrawn" || resource.listing_state === "sold" || resource.listing_state === "donated") return false;
            if (resource.title && (resource.title.startsWith("Lifecycle Test") || resource.title.startsWith("Direct RPC Test"))) return false;
            const resourceType = String(resource.resource_type || "").trim().toLocaleLowerCase();
            const listingMode = String(resource.listing_mode || "borrow");
            const text = `${resource.title || ""} ${resource.description || ""} ${resource.resource_type || ""}`.toLocaleLowerCase();
            if (query && !text.includes(query)) return false;
            if (settings.categoryId && settings.categoryId !== "all" &&
                String(resource.category_id) !== String(settings.categoryId)) return false;
            if (settings.availability && settings.availability !== "all" &&
                resource.availability_status !== settings.availability) return false;
            if (settings.resourceType && settings.resourceType !== "all" &&
                resourceType !== String(settings.resourceType).trim().toLocaleLowerCase()) return false;
            if (settings.listingMode && settings.listingMode !== "all" && listingMode !== settings.listingMode) return false;
            if (settings.ownerId && !isOwnResource(resource, settings.ownerId)) return false;
            if (condition !== "all" && resource.item_condition !== condition) return false;
            if (Number.isFinite(minPrice) || Number.isFinite(maxPrice)) {
                const price = listingMode === "sell" ? Number(resource.sale_price)
                    : listingMode === "borrow" && resource.borrow_price_kind !== "free"
                        ? Number(resource.borrow_price_amount) : 0;
                if (!Number.isFinite(price)) return false;
                if (Number.isFinite(minPrice) && price < minPrice) return false;
                if (Number.isFinite(maxPrice) && price > maxPrice) return false;
            }
            return true;
        }).sort(function (left, right) {
            if (settings.sort === "title") {
                return String(left.title || "").localeCompare(String(right.title || ""), undefined, { sensitivity: "base" });
            }
            if (settings.sort === "title-desc") {
                return String(right.title || "").localeCompare(String(left.title || ""), undefined, { sensitivity: "base" });
            }
            if (settings.sort === "oldest") {
                return (Date.parse(left.created_at || "") || 0) - (Date.parse(right.created_at || "") || 0);
            }
            if (settings.sort === "price-low" || settings.sort === "price-high") {
                function priceOf(resource) {
                    const mode = resource.listing_mode || "borrow";
                    if (mode === "sell") return Number(resource.sale_price) || 0;
                    if (mode === "borrow" && resource.borrow_price_kind !== "free") return Number(resource.borrow_price_amount) || 0;
                    return 0;
                }
                const difference = priceOf(left) - priceOf(right);
                if (difference) return settings.sort === "price-low" ? difference : -difference;
                return (Date.parse(right.created_at || "") || 0) - (Date.parse(left.created_at || "") || 0);
            }
            return (Date.parse(right.created_at || "") || 0) -
                (Date.parse(left.created_at || "") || 0);
        });
    }

    function dashboardStats(resources, requests, userId) {
        const owned = (Array.isArray(resources) ? resources : []).filter(function (resource) {
            return isOwnResource(resource, userId);
        });
        const visibleRequests = Array.isArray(requests) ? requests : [];
        return {
            myResources: owned.length,
            availableResources: owned.filter(function (resource) {
                return resource.availability_status === "available";
            }).length,
            pendingRequests: visibleRequests.filter(function (request) {
                return request && request.status === "pending";
            }).length,
            approvedRequests: visibleRequests.filter(function (request) {
                return request && request.status === "approved";
            }).length,
            recentResources: owned.sort(function (left, right) {
                return (Date.parse(right.created_at || "") || 0) -
                    (Date.parse(left.created_at || "") || 0);
            }).slice(0, 4)
        };
    }

    function dashboardMarketplaceStats(resources, borrowRequests, transferRequests, userId) {
        const rows = Array.isArray(resources) ? resources : [];
        const borrows = Array.isArray(borrowRequests) ? borrowRequests : [];
        const transfers = Array.isArray(transferRequests) ? transferRequests : [];
        const owned = rows.filter(function (resource) { return isOwnResource(resource, userId); });
        const byId = new Map(rows.map(function (resource) { return [String(resource.id), resource]; }));
        const incomingBorrow = borrows.filter(function (request) {
            const resource = request && byId.get(String(request.resource_id));
            return resource && isOwnResource(resource, userId);
        });
        const outgoingBorrow = borrows.filter(function (request) { return request && String(request.borrower_id) === String(userId); });
        const incomingTransfer = transfers.filter(function (request) { return request && String(request.owner_id) === String(userId); });
        const outgoingTransfer = transfers.filter(function (request) { return request && String(request.requester_id) === String(userId); });
        return {
            activeBorrowListings: owned.filter(function (resource) { return resource.listing_mode === "borrow" && resource.listing_state === "active"; }).length,
            activeSellListings: owned.filter(function (resource) { return resource.listing_mode === "sell" && resource.listing_state === "active"; }).length,
            activeDonateListings: owned.filter(function (resource) { return resource.listing_mode === "donate" && resource.listing_state === "active"; }).length,
            incomingRequests: incomingBorrow.filter(function (request) { return ["pending", "approved"].includes(request.status); }).length +
                incomingTransfer.filter(function (request) { return ["pending", "approved"].includes(request.status); }).length,
            outgoingRequests: outgoingBorrow.filter(function (request) { return ["pending", "approved"].includes(request.status); }).length +
                outgoingTransfer.filter(function (request) { return ["pending", "approved"].includes(request.status); }).length,
            completedBorrowReturns: borrows.filter(function (request) { return request && request.status === "returned" &&
                (String(request.borrower_id) === String(userId) || isOwnResource(byId.get(String(request.resource_id)), userId)); }).length,
            completedSales: transfers.filter(function (request) { return request && request.request_type === "sell" && request.status === "completed" &&
                (String(request.owner_id) === String(userId) || String(request.requester_id) === String(userId)); }).length,
            completedDonations: transfers.filter(function (request) { return request && request.request_type === "donate" && request.status === "completed" &&
                (String(request.owner_id) === String(userId) || String(request.requester_id) === String(userId)); }).length
        };
    }

    function canRequestBorrow(resource, options) {
        const settings = options || {};
        return Boolean(settings.userId && settings.borrowingEnabled && resource &&
            (!resource.listing_mode || resource.listing_mode === "borrow") &&
            resource.availability_status === "available" &&
            !isOwnResource(resource, settings.userId) && !settings.hasActiveRequest);
    }

    function ownerRequestActions(request, options) {
        const settings = options || {};
        if (!settings.isOwner || !settings.statusActionsEnabled || !request || request.id == null) return [];
        if (request.status === "pending") return ["approve", "reject"];
        if (request.status === "approved" || request.status === "return_requested") return ["return"];
        return [];
    }

    function conversationRole(conversation, userId) {
        if (!conversation || !userId) return null;
        if (String(conversation.borrower_id) === String(userId)) return "borrower";
        if (String(conversation.owner_id) === String(userId)) return "owner";
        return null;
    }

    function conversationPartnerName(conversation, userId) {
        if (!conversation || !userId) return "Student";
        return String(conversation.borrower_id) === String(userId)
            ? (conversation.owner_name || "Owner")
            : (conversation.borrower_name || "Borrower");
    }

    function activeMeetingProposal(proposals) {
        return (Array.isArray(proposals) ? proposals : []).find(function (p) {
            return p && p.status === "pending";
        }) || null;
    }

    function confirmedMeeting(proposals) {
        return (Array.isArray(proposals) ? proposals : []).find(function (p) {
            return p && p.status === "accepted";
        }) || null;
    }

    function formatMeetingTimeIST(timeStr) {
        if (!timeStr || typeof timeStr !== "string" || !timeStr.includes(":")) return timeStr || "";
        const parts = timeStr.split(":");
        const hours = parseInt(parts[0], 10);
        const minutes = parts[1];
        if (isNaN(hours)) return timeStr;
        const ampm = hours >= 12 ? "PM" : "AM";
        const standardHour = hours % 12 || 12;
        return `${standardHour}:${minutes} ${ampm} IST`;
    }

    function validateResourcePayload(payload) {
        if (!payload || typeof payload !== "object") return "Enter the resource details before saving.";
        if (typeof payload.title !== "string" || !payload.title.trim()) return "Enter a resource title.";
        if (typeof payload.description !== "string" || !payload.description.trim()) return "Enter a description.";
        if (payload.category_id == null || String(payload.category_id).trim() === "") return "Choose a category.";
        if (typeof payload.resource_type !== "string" || !payload.resource_type.trim()) return "Enter a resource type.";
        if (!["available", "unavailable"].includes(payload.availability_status)) return "Choose a valid availability status.";
        return "";
    }

    window.CampusShareUiModel = Object.freeze({
        isOwnResource: isOwnResource,
        filterResources: filterResources,
        dashboardStats: dashboardStats,
        dashboardMarketplaceStats: dashboardMarketplaceStats,
        canRequestBorrow: canRequestBorrow,
        ownerRequestActions: ownerRequestActions,
        conversationRole: conversationRole,
        conversationPartnerName: conversationPartnerName,
        activeMeetingProposal: activeMeetingProposal,
        confirmedMeeting: confirmedMeeting,
        formatMeetingTimeIST: formatMeetingTimeIST,
        validateResourcePayload: validateResourcePayload
    });
})(window);
