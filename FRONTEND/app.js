(function () {
    "use strict";

    const auth = window.CampusShareAuth;
    const api = window.CampusShareApi;
    const authButton = document.getElementById("authButton");
    const authDialog = document.getElementById("authDialog");
    const authMessage = document.getElementById("authMessage");
    const authTitle = document.getElementById("authTitle");
    const authConfigNote = document.getElementById("authConfigNote");
    const loginForm = document.getElementById("loginForm");
    const registerForm = document.getElementById("registerForm");
    const resourceStatus = document.getElementById("resourceStatus");
    const searchInput = document.getElementById("searchInput");
    const categoryFilter = document.getElementById("categoryFilter");
    const resourceTypeFilter = document.getElementById("resourceTypeFilter");
    const listingModeFilter = document.getElementById("listingModeFilter");
    const availabilityFilter = document.getElementById("availabilityFilter");
    const priceMinFilter = document.getElementById("priceMinFilter");
    const priceMaxFilter = document.getElementById("priceMaxFilter");
    const conditionFilter = document.getElementById("conditionFilter");
    const sortSelect = document.getElementById("sortSelect");
    const openFilterBtn = document.getElementById("openFilterBtn");
    const closeFilterBtn = document.getElementById("closeFilterBtn");
    const filterDrawer = document.getElementById("filterDrawer");
    const filterDrawerBackdrop = document.getElementById("filterDrawerBackdrop");
    const filterBadge = document.getElementById("filterBadge");
    const drawerApplyBtn = document.getElementById("drawerApplyBtn");
    const drawerResetBtn = document.getElementById("drawerResetBtn");
    const searchClearBtn = document.getElementById("searchClearBtn");
    const activeFilterChips = document.getElementById("activeFilterChips");
    const drawerCategoryList = document.getElementById("drawerCategoryList");
    const drawerConditionList = document.getElementById("drawerConditionList");
    const drawerPriceSection = document.getElementById("drawerPriceSection");
    const drawerPriceMin = document.getElementById("drawerPriceMin");
    const drawerPriceMax = document.getElementById("drawerPriceMax");
    const priceSliderMin = document.getElementById("priceSliderMin");
    const priceSliderMax = document.getElementById("priceSliderMax");
    const priceSliderRange = document.getElementById("priceSliderRange");
    const drawerQuickPrices = document.getElementById("drawerQuickPrices");
    const drawerSortList = document.getElementById("drawerSortList");
    const drawerAvailabilityList = document.getElementById("drawerAvailabilityList");
    const sliderMaxLabel = document.getElementById("sliderMaxLabel");

    let stagingCategory = "all";
    let stagingCondition = "all";
    let stagingMinPrice = "";
    let stagingMaxPrice = "";
    let stagingAvailability = "all";
    let stagingSort = "newest";
    const resourceGrid = document.getElementById("resourceGrid");
    const resourceCount = document.getElementById("resourceCount");
    const noResults = document.getElementById("noResults");
    const resourceForm = document.getElementById("resourceForm");
    const resourceFormHeading = document.getElementById("resourceFormHeading");
    const resourceFormStatus = document.getElementById("resourceFormStatus");
    const resourceSaveButton = document.getElementById("resourceSaveButton");
    const showAddForm = document.getElementById("showAddForm");
    const borrowRequestsSection = document.getElementById("borrowRequestsSection");
    const borrowCreationNote = document.getElementById("borrowCreationNote");
    const borrowStatus = document.getElementById("borrowStatus");
    const myBorrowRequests = document.getElementById("myBorrowRequests");
    const ownerBorrowRequests = document.getElementById("ownerBorrowRequests");
    const myBorrowEmpty = document.getElementById("myBorrowEmpty");
    const ownerBorrowEmpty = document.getElementById("ownerBorrowEmpty");
    const resourceDetailsDialog = document.getElementById("resourceDetailsDialog");
    const resourceDetailsTitle = document.getElementById("resourceDetailsTitle");
    const resourceDetailsDescription = document.getElementById("resourceDetailsDescription");
    const resourceDetailsActions = document.getElementById("resourceDetailsActions");
    const resourceDetailsFeatureNote = document.getElementById("resourceDetailsFeatureNote");
    const dashboard = document.getElementById("dashboard");
    const dashboardStudentName = document.getElementById("dashboardStudentName");
    const welcomeSummary = document.getElementById("welcomeSummary");
    const welcomeAvailableSummary = document.getElementById("welcomeAvailableSummary");
    const welcomeRequestSummary = document.getElementById("welcomeRequestSummary");
    const myActivityList = document.getElementById("myActivityList");
    const myActivityEmpty = document.getElementById("myActivityEmpty");
    const sidebarProfile = document.getElementById("sidebarProfile");
    const sidebarAvatar = document.getElementById("sidebarAvatar");
    const sidebarStudentName = document.getElementById("sidebarStudentName");
    const sidebarStudentEmail = document.getElementById("sidebarStudentEmail");
    const topbarStudentName = document.getElementById("topbarStudentName");
    const topbarStudentEmail = document.getElementById("topbarStudentEmail");
    const topbarAvatar = document.getElementById("topbarAvatar");
    const topbarPageTitle = document.getElementById("topbarPageTitle");
    const appSidebar = document.getElementById("appSidebar");
    const sidebarBackdrop = document.getElementById("sidebarBackdrop");
    const mobileNavToggle = document.getElementById("mobileNavToggle");
    const homeView = document.getElementById("home");
    const dashboardNav = document.getElementById("dashboardNav");
    const homeNav = document.getElementById("homeNav");
    const myResourcesNav = document.getElementById("myResourcesNav");
    const browseNav = document.getElementById("browseNav");
    const sellNav = document.getElementById("sellNav");
    const donateNav = document.getElementById("donateNav");
    const requestsNav = document.getElementById("requestsNav");
    const aboutNav = document.getElementById("aboutNav");
    const aboutView = document.getElementById("about");
    const browsePage = document.getElementById("browsePage");
    const myResourcesPage = document.getElementById("myResourcesPage");
    const sellPage = document.getElementById("sellPage");
    const donatePage = document.getElementById("donatePage");
    const resourcesSection = document.getElementById("resources");
    const browseResourcesMount = document.getElementById("browseResourcesMount");
    const myResourcesMount = document.getElementById("myResourcesMount");
    const myBorrowTab = document.getElementById("myBorrowTab");
    const mySellTab = document.getElementById("mySellTab");
    const myDonateTab = document.getElementById("myDonateTab");
    let myResourcesActiveSubTab = "borrow";
    const sellResourcesMount = document.getElementById("sellResourcesMount");
    const donateResourcesMount = document.getElementById("donateResourcesMount");
    const sellMarketplaceNote = document.getElementById("sellMarketplaceNote");
    const donateMarketplaceNote = document.getElementById("donateMarketplaceNote");
    const resourcesPageHeading = document.getElementById("resourcesPageHeading");
    const resourcesPageDescription = document.getElementById("resourcesPageDescription");
    const statGrid = document.querySelector(".stat-grid");
    const recentResources = document.getElementById("recentResources");
    const recentResourcesEmpty = document.getElementById("recentResourcesEmpty");
    const emptyTitle = document.getElementById("emptyTitle");
    const emptyMessage = document.getElementById("emptyMessage");
    const emptyAddResource = document.getElementById("emptyAddResource");
    const resourceViewTitle = document.getElementById("resourceViewTitle");
    const borrowStatusFeatureNote = document.getElementById("borrowStatusFeatureNote");
    const marketplaceFields = document.getElementById("marketplaceFields");
    const marketplaceTransferSection = document.getElementById("marketplaceTransferSection");
    const myTransferRequests = document.getElementById("myTransferRequests");
    const ownerTransferRequests = document.getElementById("ownerTransferRequests");
    const myTransferEmpty = document.getElementById("myTransferEmpty");
    const ownerTransferEmpty = document.getElementById("ownerTransferEmpty");
    const myListingReports = document.getElementById("myListingReports");
    const myReportsEmpty = document.getElementById("myReportsEmpty");
    const listingReportDialog = document.getElementById("listingReportDialog");
    const listingReportForm = document.getElementById("listingReportForm");
    const listingReportStatus = document.getElementById("listingReportStatus");
    const resourceImagesInput = document.getElementById("resourceImages");
    const imagePreviewList = document.getElementById("imagePreviewList");
    const existingImageList = document.getElementById("existingImageList");
    const imageUploadAvailabilityNote = document.getElementById("imageUploadAvailabilityNote");
    const ui = window.CampusShareUiModel;

    let currentSession = null;
    let categories = [];
    let categoryLoadState = "idle";
    let resources = [];
    let borrowingRequests = [];
    let resourcesLoaded = false;
    let requestsLoaded = false;
    let borrowRequestRpcEnabled = false;
    let borrowStatusRpcEnabled = false;
    let marketplaceEnabled = false;
    let marketplaceDataLoaded = false;
    let resourceImagesEnabled = false;
    let transferRequests = [];
    let listingReports = [];
    let reportResourceId = null;
    let selectedImageFiles = [];
    let existingImageCount = 0;
    let existingPrimaryImage = false;
    let resourceFormGeneration = 0;
    let resourceFormImageLoad = Promise.resolve(true);
    const imageStripGenerations = new WeakMap();
    let myResourcesOnly = false;
    let requestGeneration = 0;
    let resourceDetailsGeneration = 0;
    let authFormBusy = false;
    let resourceFormBusy = false;
    let currentRoute = "home";
    let sessionResolved = false;
    const borrowBusy = new Set();
    const borrowStatusBusy = new Set();

    function setAuthMessage(message, kind) {
        authMessage.textContent = message || "";
        authMessage.classList.toggle("is-error", kind === "error");
        authMessage.classList.toggle("is-success", kind === "success");
    }

    function setStatus(message, kind) {
        resourceStatus.textContent = message || "";
        resourceStatus.classList.toggle("is-error", kind === "error");
        resourceStatus.classList.toggle("is-success", kind === "success");
    }

    function setResourceFormStatus(message, kind) {
        resourceFormStatus.textContent = message || "";
        resourceFormStatus.hidden = !message;
        resourceFormStatus.classList.toggle("is-error", kind === "error");
        resourceFormStatus.classList.toggle("is-success", kind === "success");
        if (!message) delete resourceFormStatus.dataset.categoryNotice;
    }

    function setBorrowStatus(message, kind) {
        borrowStatus.textContent = message || "";
        borrowStatus.classList.toggle("is-error", kind === "error");
        borrowStatus.classList.toggle("is-success", kind === "success");
    }

    function errorMessage(error) {
        return error && error.message ? error.message : "Something went wrong. Please try again.";
    }

    function registrationErrorMessage(error) {
        const code = error && typeof error.code === "string" ? error.code : "";
        const message = error && typeof error.message === "string" ? error.message : "";
        const status = error && Number(error.status);
        if (status === 429 || code === "over_email_send_rate_limit" || /email rate limit exceeded|too many requests/i.test(message)) {
            return "Registration email limit reached. Please wait before trying again; repeated attempts will not send the email sooner. If you already created an account, switch to 'Log in' to sign in directly with your password. College and personal email addresses are supported.";
        }
        return errorMessage(error);
    }

    const routeViews = [
        { route: "home", element: homeView },
        { route: "dashboard", element: dashboard },
        { route: "browse", element: browsePage },
        { route: "sell", element: sellPage },
        { route: "donate", element: donatePage },
        { route: "my-resources", element: myResourcesPage },
        { route: "borrowing", element: borrowRequestsSection },
        { route: "about", element: aboutView }
    ];
    const routeLinks = [
        { route: "home", element: homeNav },
        { route: "dashboard", element: dashboardNav },
        { route: "browse", element: browseNav },
        { route: "sell", element: sellNav },
        { route: "donate", element: donateNav },
        { route: "my-resources", element: myResourcesNav },
        { route: "borrowing", element: requestsNav },
        { route: "about", element: aboutNav }
    ];
    const validRoutes = new Set(routeLinks.map(function (item) { return item.route; }));
    const routeAliases = { resources: "browse", borrowRequestsSection: "borrowing", "sell-marketplace": "sell", "donate-marketplace": "donate", messages: "borrowing" };
    routeLinks.forEach(function (item) {
        item.element.addEventListener("click", function (event) {
            event.preventDefault();
            setSidebarOpen(false);
            if (item.route === "my-resources") {
                showMyResources();
            } else if (item.route === "browse") {
                showBrowseResources();
            } else {
                navigateTo(item.route);
            }
        });
    });

    function requestedRoute() {
        const route = String(window.location.hash || "#home").replace(/^#/, "");
        return validRoutes.has(route) ? route : routeAliases[route] || "home";
    }

    function navigateTo(route) {
        if (!validRoutes.has(route)) return;
        const nextHash = "#" + route;
        if (window.location.hash !== nextHash) window.location.hash = nextHash;
        renderRoute();
    }

    function renderRoute() {
        let route = requestedRoute();
        const protectedRoute = route === "dashboard" || route === "my-resources" || route === "borrowing";
        if (protectedRoute && !sessionResolved) return;
        if (protectedRoute && !currentSession) {
            route = "home";
            if (window.location.hash !== "#home") window.location.hash = "#home";
            setStatus("Log in to open that CampusShare page.", "error");
        } else if (window.location.hash !== "#" + route) {
            window.location.hash = "#" + route;
        }

        setSidebarOpen(false);
        currentRoute = route;
        myResourcesOnly = route === "my-resources";
        const resourcePageMount = myResourcesOnly ? myResourcesMount
            : route === "sell" ? sellResourcesMount
                : route === "donate" ? donateResourcesMount : browseResourcesMount;
        if (resourcesSection.parentElement !== resourcePageMount) {
            resourcePageMount.appendChild(resourcesSection);
        }
        routeViews.forEach(function (view) {
            view.element.hidden = view.route !== route;
        });
        routeLinks.forEach(function (link) {
            link.element.setAttribute("aria-current", link.route === route ? "page" : "false");
        });
        const pageTitles = {
            home: "Home",
            dashboard: "Dashboard",
            browse: "Browse Resources",
            sell: "Sell Resources",
            donate: "Donate Resources",
            "my-resources": "My Resources",
            borrowing: "Borrowing",
            about: "About"
        };
        topbarPageTitle.textContent = pageTitles[route];
        if (typeof window.scrollTo === "function") window.scrollTo(0, 0);

        const showingMyResources = route === "my-resources";
        resourcesPageHeading.textContent = showingMyResources ? "My Resources"
            : route === "sell" ? "Fixed-price listings"
                : route === "donate" ? "Free donations" : "Explore Resources";
        resourcesPageDescription.textContent = showingMyResources
            ? "Manage the resources you have shared with your campus."
            : route === "sell" ? "Browse items listed for a fixed price in INR."
                : route === "donate" ? "Browse resources offered for free permanent transfer."
                    : "Find and share useful materials with fellow students.";
        sellMarketplaceNote.hidden = marketplaceEnabled;
        donateMarketplaceNote.hidden = marketplaceEnabled;
        updateMarketplaceFilterVisibility();
        showAddForm.hidden = !canAddFromCurrentRoute();
        emptyAddResource.hidden = !myResourcesOnly || !canAddFromCurrentRoute();
        resourceViewTitle.textContent = resourceViewHeading();
        if (resourcesLoaded) renderResources();
    }

    function setMyResourcesSubTab(subTab) {
        myResourcesActiveSubTab = subTab;
        if (myBorrowTab) {
            myBorrowTab.classList.toggle("is-active", subTab === "borrow");
            myBorrowTab.setAttribute("aria-selected", subTab === "borrow" ? "true" : "false");
        }
        if (mySellTab) {
            mySellTab.classList.toggle("is-active", subTab === "sell");
            mySellTab.setAttribute("aria-selected", subTab === "sell" ? "true" : "false");
        }
        if (myDonateTab) {
            myDonateTab.classList.toggle("is-active", subTab === "donate");
            myDonateTab.setAttribute("aria-selected", subTab === "donate" ? "true" : "false");
        }
        resourceViewTitle.textContent = resourceViewHeading();
        if (resourcesLoaded) renderResources();
    }

    function resourceViewHeading() {
        if (currentRoute === "my-resources") return "My resources";
        if (currentRoute === "sell") return "Sell listings";
        if (currentRoute === "donate") return "Donation listings";
        return "Browse resources";
    }

    function updateMarketplaceFilterVisibility() {
        const showMarketplaceFilters = marketplaceEnabled && (currentRoute === "sell" || currentRoute === "browse");
        listingModeFilter.hidden = !marketplaceEnabled || currentRoute !== "browse";
        priceMinFilter.hidden = !showMarketplaceFilters;
        priceMaxFilter.hidden = !showMarketplaceFilters;
        conditionFilter.hidden = !showMarketplaceFilters;
    }

    function canAddFromCurrentRoute() {
        return Boolean(currentSession && !((currentRoute === "sell" || currentRoute === "donate") && !marketplaceEnabled));
    }

    function setSidebarOpen(isOpen) {
        appSidebar.classList.toggle("is-open", isOpen);
        appSidebar.setAttribute("aria-hidden", String(!isOpen));
        appSidebar.inert = !isOpen;
        sidebarBackdrop.hidden = !isOpen;
        mobileNavToggle.setAttribute("aria-expanded", String(isOpen));
        mobileNavToggle.setAttribute("aria-label", isOpen ? "Close navigation" : "Open navigation");
    }

    function renderStudentProfile() {
        const user = currentSession && currentSession.user;
        const signedIn = Boolean(user);
        const name = signedIn ? getStudentDisplayName() : "Student";
        const email = signedIn && typeof user.email === "string" ? user.email : "";
        const initials = name.split(/\s+/).filter(Boolean).slice(0, 2).map(function (part) {
            return part.charAt(0).toUpperCase();
        }).join("") || "S";
        sidebarProfile.hidden = !signedIn;
        sidebarStudentName.textContent = name;
        sidebarStudentEmail.textContent = email;
        sidebarAvatar.textContent = initials;
        topbarStudentName.textContent = name;
        topbarStudentName.hidden = !signedIn;
        topbarStudentEmail.textContent = email;
        topbarStudentEmail.hidden = !signedIn || !email;
        topbarAvatar.textContent = initials;
        topbarAvatar.hidden = !signedIn;
    }

    function setAuthMode(mode) {
        const registering = mode === "register";
        const sourceForm = registering ? loginForm : registerForm;
        const targetForm = registering ? registerForm : loginForm;
        if (sourceForm && targetForm) {
            if (sourceForm.elements.email && targetForm.elements.email && sourceForm.elements.email.value) {
                targetForm.elements.email.value = sourceForm.elements.email.value;
            }
            if (sourceForm.elements.password && targetForm.elements.password && sourceForm.elements.password.value) {
                targetForm.elements.password.value = sourceForm.elements.password.value;
            }
        }
        loginForm.hidden = registering;
        registerForm.hidden = !registering;
        document.getElementById("showLogin").setAttribute("aria-selected", String(!registering));
        document.getElementById("showRegister").setAttribute("aria-selected", String(registering));
        authTitle.textContent = registering ? "Create your account" : "Log in to your account";
        setAuthMessage("");
    }

    function setButtonBusy(button, isBusy, busyLabel) {
        if (!button) return;
        if (!button.dataset.idleText) button.dataset.idleText = button.textContent;
        button.disabled = isBusy;
        button.textContent = isBusy ? busyLabel : button.dataset.idleText;
    }

    function setFormBusy(form, isBusy, busyLabel) {
        setButtonBusy(form.querySelector('button[type="submit"]'), isBusy, busyLabel);
    }

    function renderCategories() {
        const selectedFilter = categoryFilter.value;
        categoryFilter.replaceChildren(new Option("All Categories", "all"));
        const selectedFormCategory = document.getElementById("resourceCategory").value;
        const resourceCategory = document.getElementById("resourceCategory");
        const placeholders = {
            idle: "Sign in to load categories",
            loading: "Loading categories…",
            error: "Categories could not be loaded",
            loaded: categories.length ? "Choose a category" : "No categories available"
        };
        const placeholder = new Option(placeholders[categoryLoadState], "");
        placeholder.disabled = categoryLoadState !== "loaded" || categories.length === 0;
        resourceCategory.replaceChildren(placeholder);

        categories.forEach(function (category) {
            if (!category || category.id == null || typeof category.name !== "string") return;
            categoryFilter.add(new Option(category.name, String(category.id)));
            resourceCategory.add(new Option(category.name, String(category.id)));
        });

        if (Array.from(categoryFilter.options).some(function (option) {
            return option.value === selectedFilter;
        })) categoryFilter.value = selectedFilter;
        if (Array.from(resourceCategory.options).some(function (option) {
            return option.value === selectedFormCategory;
        })) resourceCategory.value = selectedFormCategory;
        if (!resourceForm.hidden) updateCategoryFormState();
        renderDrawerCategories();
    }

    function renderDrawerCategories() {
        if (!drawerCategoryList) return;
        drawerCategoryList.replaceChildren();
        const allBtn = document.createElement("button");
        allBtn.type = "button";
        allBtn.className = `filter-pill ${stagingCategory === "all" ? "is-active" : ""}`;
        allBtn.dataset.category = "all";
        allBtn.textContent = "All Categories";
        allBtn.addEventListener("click", function () {
            stagingCategory = "all";
            syncDrawerCategoryPills();
        });
        drawerCategoryList.appendChild(allBtn);

        categories.forEach(function (category) {
            if (!category || category.id == null || typeof category.name !== "string") return;
            const btn = document.createElement("button");
            btn.type = "button";
            btn.className = `filter-pill ${stagingCategory === String(category.id) ? "is-active" : ""}`;
            btn.dataset.category = String(category.id);
            btn.textContent = category.name;
            btn.addEventListener("click", function () {
                stagingCategory = String(category.id);
                syncDrawerCategoryPills();
            });
            drawerCategoryList.appendChild(btn);
        });
    }

    function syncDrawerCategoryPills() {
        if (!drawerCategoryList) return;
        Array.from(drawerCategoryList.children).forEach(function (btn) {
            btn.classList.toggle("is-active", btn.dataset.category === stagingCategory);
        });
    }

    function syncDrawerConditionPills() {
        if (!drawerConditionList) return;
        Array.from(drawerConditionList.children).forEach(function (btn) {
            btn.classList.toggle("is-active", btn.dataset.condition === stagingCondition);
        });
    }

    function syncDrawerSortPills() {
        if (!drawerSortList) return;
        Array.from(drawerSortList.children).forEach(function (btn) {
            btn.classList.toggle("is-active", btn.dataset.sort === stagingSort);
        });
    }

    function syncDrawerAvailabilityPills() {
        if (!drawerAvailabilityList) return;
        Array.from(drawerAvailabilityList.children).forEach(function (btn) {
            btn.classList.toggle("is-active", btn.dataset.avail === stagingAvailability);
        });
    }

    function getDynamicMaxPrice() {
        let maxFound = 5000;
        (resources || []).forEach(function (r) {
            const p = Number(r.sale_price) || 0;
            if (p > maxFound) maxFound = p;
        });
        return Math.ceil(maxFound / 1000) * 1000;
    }

    function syncDrawerPriceVisibility() {
        if (!drawerPriceSection) return;
        const mode = currentRoute === "sell" ? "sell"
            : currentRoute === "donate" ? "donate"
            : myResourcesOnly ? myResourcesActiveSubTab : "browse";
        if (mode === "donate" || mode === "borrow") {
            drawerPriceSection.hidden = true;
        } else {
            drawerPriceSection.hidden = false;
        }
    }

    function updateQuickPricePills() {
        if (!drawerQuickPrices) return;
        Array.from(drawerQuickPrices.children).forEach(function (btn) {
            const min = btn.dataset.min ?? "";
            const max = btn.dataset.max ?? "";
            const match = min === stagingMinPrice && max === stagingMaxPrice;
            btn.classList.toggle("is-active", match);
        });
    }

    function updateSliderTrackHighlight() {
        if (!priceSliderRange || !priceSliderRange.style || !priceSliderMin || !priceSliderMax) return;
        const maxLimit = Number(priceSliderMax.max) || 10000;
        const minVal = Number(priceSliderMin.value) || 0;
        const maxVal = Number(priceSliderMax.value) || maxLimit;
        const pctMin = Math.min(100, Math.max(0, (minVal / maxLimit) * 100));
        const pctMax = Math.min(100, Math.max(0, (maxVal / maxLimit) * 100));
        priceSliderRange.style.left = `${pctMin}%`;
        priceSliderRange.style.width = `${Math.max(0, pctMax - pctMin)}%`;
    }

    function syncDrawerPriceSlider() {
        if (!priceSliderMin || !priceSliderMax) return;
        const maxLimit = getDynamicMaxPrice();
        priceSliderMin.max = String(maxLimit);
        priceSliderMax.max = String(maxLimit);
        if (sliderMaxLabel) {
            sliderMaxLabel.textContent = `₹${maxLimit.toLocaleString("en-IN")}+`;
        }
        const minVal = stagingMinPrice === "" ? 0 : Math.max(0, Number(stagingMinPrice) || 0);
        const maxVal = stagingMaxPrice === "" ? maxLimit : Math.min(maxLimit, Number(stagingMaxPrice) || maxLimit);
        priceSliderMin.value = String(minVal);
        priceSliderMax.value = String(maxVal);
        updateSliderTrackHighlight();
    }

    function syncDrawerWithState() {
        syncDrawerCategoryPills();
        syncDrawerConditionPills();
        syncDrawerSortPills();
        syncDrawerAvailabilityPills();
        if (drawerPriceMin) drawerPriceMin.value = stagingMinPrice;
        if (drawerPriceMax) drawerPriceMax.value = stagingMaxPrice;
        updateQuickPricePills();
        syncDrawerPriceSlider();
        syncDrawerPriceVisibility();
    }

    function openFilterDrawer() {
        stagingCategory = categoryFilter ? categoryFilter.value || "all" : "all";
        stagingCondition = conditionFilter ? conditionFilter.value || "all" : "all";
        stagingMinPrice = priceMinFilter ? priceMinFilter.value || "" : "";
        stagingMaxPrice = priceMaxFilter ? priceMaxFilter.value || "" : "";
        stagingAvailability = availabilityFilter ? availabilityFilter.value || "all" : "all";
        stagingSort = sortSelect ? sortSelect.value || "newest" : "newest";

        renderDrawerCategories();
        syncDrawerWithState();

        if (filterDrawer && filterDrawerBackdrop) {
            filterDrawer.hidden = false;
            filterDrawerBackdrop.hidden = false;
            if (typeof window !== "undefined" && typeof window.requestAnimationFrame === "function") {
                window.requestAnimationFrame(function () {
                    filterDrawer.classList.add("is-open");
                });
            } else {
                filterDrawer.classList.add("is-open");
            }
        }
    }

    function closeFilterDrawer() {
        if (!filterDrawer) return;
        filterDrawer.classList.remove("is-open");
        const timer = typeof window !== "undefined" && typeof window.setTimeout === "function"
            ? window.setTimeout : (typeof setTimeout === "function" ? setTimeout : function (fn) { fn(); });
        timer(function () {
            if (!filterDrawer.classList.contains("is-open")) {
                filterDrawer.hidden = true;
                if (filterDrawerBackdrop) filterDrawerBackdrop.hidden = true;
            }
        }, 280);
    }

    function applyDrawerFilters() {
        if (stagingMinPrice !== "" && stagingMaxPrice !== "") {
            const minNum = Number(stagingMinPrice);
            const maxNum = Number(stagingMaxPrice);
            if (minNum > maxNum) {
                const temp = stagingMinPrice;
                stagingMinPrice = stagingMaxPrice;
                stagingMaxPrice = temp;
            }
        }
        if (categoryFilter) categoryFilter.value = stagingCategory;
        if (conditionFilter) conditionFilter.value = stagingCondition;
        if (priceMinFilter) priceMinFilter.value = stagingMinPrice;
        if (priceMaxFilter) priceMaxFilter.value = stagingMaxPrice;
        if (availabilityFilter) availabilityFilter.value = stagingAvailability;
        if (sortSelect) sortSelect.value = stagingSort;

        closeFilterDrawer();
        renderResources();
    }

    function resetDrawerFilters() {
        stagingCategory = "all";
        stagingCondition = "all";
        stagingMinPrice = "";
        stagingMaxPrice = "";
        stagingAvailability = "all";
        stagingSort = "newest";
        syncDrawerWithState();
    }

    function sortLabel(value) {
        return ({
            "newest": "Newest First",
            "oldest": "Oldest First",
            "price-low": "Price: Low to High",
            "price-high": "Price: High to Low",
            "title": "A to Z",
            "title-desc": "Z to A"
        })[value] || value;
    }

    function updateActiveFilterUI(rowCount, totalCount) {
        let activeCount = 0;
        const query = searchInput ? searchInput.value.trim() : "";
        if (query) activeCount++;
        if (categoryFilter && categoryFilter.value && categoryFilter.value !== "all") activeCount++;
        if (conditionFilter && conditionFilter.value && conditionFilter.value !== "all") activeCount++;
        if ((priceMinFilter && priceMinFilter.value !== "") || (priceMaxFilter && priceMaxFilter.value !== "")) activeCount++;
        if (availabilityFilter && availabilityFilter.value && availabilityFilter.value !== "all") activeCount++;
        if (sortSelect && sortSelect.value && sortSelect.value !== "newest") activeCount++;

        if (filterBadge) {
            filterBadge.textContent = String(activeCount);
            filterBadge.hidden = activeCount === 0;
        }
        if (searchClearBtn) {
            searchClearBtn.hidden = !query;
        }

        const clearBtn = document.getElementById("clearFilters");
        if (clearBtn) {
            clearBtn.hidden = activeCount === 0;
        }

        if (activeFilterChips) {
            activeFilterChips.replaceChildren();

            function makeChip(labelText, onRemove) {
                const chip = document.createElement("span");
                chip.className = "filter-chip";
                const labelSpan = document.createElement("span");
                labelSpan.textContent = labelText;
                chip.appendChild(labelSpan);
                const removeBtn = document.createElement("button");
                removeBtn.type = "button";
                removeBtn.className = "filter-chip-remove";
                removeBtn.textContent = "✕";
                removeBtn.setAttribute("aria-label", `Remove ${labelText} filter`);
                removeBtn.addEventListener("click", onRemove);
                chip.appendChild(removeBtn);
                activeFilterChips.appendChild(chip);
            }

            if (query) {
                makeChip(`Search: "${query}"`, function () {
                    if (searchInput) searchInput.value = "";
                    if (searchClearBtn) searchClearBtn.hidden = true;
                    renderResources();
                });
            }

            if (categoryFilter && categoryFilter.value && categoryFilter.value !== "all") {
                const catObj = categories.find(function (c) { return String(c.id) === categoryFilter.value; });
                const catName = catObj ? catObj.name : categoryFilter.value;
                makeChip(`Category: ${catName}`, function () {
                    categoryFilter.value = "all";
                    stagingCategory = "all";
                    renderResources();
                });
            }

            if (conditionFilter && conditionFilter.value && conditionFilter.value !== "all") {
                makeChip(`Condition: ${itemConditionLabel(conditionFilter.value)}`, function () {
                    conditionFilter.value = "all";
                    stagingCondition = "all";
                    renderResources();
                });
            }

            const minP = priceMinFilter ? priceMinFilter.value : "";
            const maxP = priceMaxFilter ? priceMaxFilter.value : "";
            if (minP !== "" || maxP !== "") {
                const priceText = minP !== "" && maxP !== "" ? `Price: ₹${minP}–₹${maxP}`
                    : minP !== "" ? `Price: Above ₹${minP}` : `Price: Under ₹${maxP}`;
                makeChip(priceText, function () {
                    if (priceMinFilter) priceMinFilter.value = "";
                    if (priceMaxFilter) priceMaxFilter.value = "";
                    stagingMinPrice = "";
                    stagingMaxPrice = "";
                    renderResources();
                });
            }

            if (availabilityFilter && availabilityFilter.value && availabilityFilter.value !== "all") {
                makeChip(`Availability: ${availabilityFilter.value === "available" ? "Available Only" : availabilityFilter.value}`, function () {
                    availabilityFilter.value = "all";
                    stagingAvailability = "all";
                    renderResources();
                });
            }

            if (sortSelect && sortSelect.value && sortSelect.value !== "newest") {
                makeChip(`Sort: ${sortLabel(sortSelect.value)}`, function () {
                    sortSelect.value = "newest";
                    stagingSort = "newest";
                    syncDrawerSortPills();
                    renderResources();
                });
            }
        }
    }

    function renderResourceTypeFilter() {
        const selected = resourceTypeFilter.value || "all";
        const types = Array.from(new Set(resources.map(function (resource) {
            return typeof resource.resource_type === "string" ? resource.resource_type.trim() : "";
        }).filter(Boolean))).sort(function (left, right) { return left.localeCompare(right); });
        resourceTypeFilter.replaceChildren(new Option("Any resource type", "all"));
        types.forEach(function (type) { resourceTypeFilter.add(new Option(type, type)); });
        resourceTypeFilter.value = types.includes(selected) ? selected : "all";
    }

    function categoryAvailabilityMessage() {
        if (categoryLoadState === "loading") return "Categories are loading. Choose one after the list finishes loading.";
        if (categoryLoadState === "error") {
            return "Categories could not be loaded. Check the signed-in session and backend, then use Refresh to try again.";
        }
        if (categoryLoadState === "loaded" && categories.length === 0) {
            return "No categories are available in staging yet. Ask the project owner to review and run the approved category seed SQL.";
        }
        return "";
    }

    function updateCategoryFormState() {
        const message = categoryAvailabilityMessage();
        if (message) {
            setResourceFormStatus(message, "error");
            resourceFormStatus.dataset.categoryNotice = "true";
        } else if (resourceFormStatus.dataset.categoryNotice === "true") {
            setResourceFormStatus("");
        }
    }

    function categoryName(resource) {
        const category = categories.find(function (item) {
            return item && String(item.id) === String(resource.category_id);
        });
        return category ? category.name : "Resource";
    }

    function hasActiveOwnRequest(resourceId) {
        if (!currentSession || !currentSession.user) return false;
        return borrowingRequests.some(function (request) {
            return String(request.resource_id) === String(resourceId) &&
                String(request.borrower_id) === String(currentSession.user.id) &&
                (request.status === "pending" || request.status === "approved");
        });
    }

    function hasActiveTransferRequest(resourceId) {
        if (!currentSession || !currentSession.user) return false;
        return transferRequests.some(function (request) {
            return String(request.resource_id) === String(resourceId) &&
                String(request.requester_id) === String(currentSession.user.id) &&
                (request.status === "pending" || request.status === "approved");
        });
    }

    function resourcePriceSummary(resource) {
        if (!marketplaceEnabled) return "";
        const formatInr = function (value) {
            return new Intl.NumberFormat("en-IN", { style: "currency", currency: "INR", maximumFractionDigits: 2 }).format(value);
        };
        if (resource.listing_state === "sold") return `Sold · ${formatInr(Number(resource.sale_price))}`;
        if (resource.listing_state === "donated") return "Donated · no longer available";
        if (resource.listing_state === "reserved") return "Reserved · request approved";
        if (resource.listing_mode === "sell") {
            const original = Number(resource.sale_original_price);
            const price = Number(resource.sale_price);
            const discount = Number.isFinite(original) && original > 0 && Number.isFinite(price)
                ? Math.max(0, Math.round((original - price) / original * 100)) : 0;
            return `For sale · ${formatInr(price)}${discount > 0 ? ` · ${discount}% below original (${formatInr(original - price)} savings)` : ""}`;
        }
        if (resource.listing_mode === "donate") return "Free donation";
        const amount = Number(resource.borrow_price_amount);
        if (!resource.borrow_price_kind || resource.borrow_price_kind === "free" || !(amount > 0)) return "Free to borrow";
        const unit = resource.borrow_price_kind === "per_day" ? "per day" : resource.borrow_price_kind === "per_week" ? "per week" : "one-time";
        return `Borrow · ${formatInr(amount)} ${unit}`;
    }

    function itemConditionLabel(value) {
        return ({ new: "New / unused", like_new: "Like new", good: "Good", fair: "Fair" })[value] || "Not specified";
    }

    function renderDashboard() {
        if (!currentSession || !currentSession.user) return;
        const stats = ui.dashboardStats(resources, borrowingRequests, currentSession.user.id);
        const displayName = getStudentDisplayName();
        dashboardStudentName.textContent = displayName;
        document.getElementById("statMyResources").textContent = resourcesLoaded ? String(stats.myResources) : "—";
        document.getElementById("statAvailableResources").textContent = resourcesLoaded ? String(stats.availableResources) : "—";
        document.getElementById("statPendingRequests").textContent = requestsLoaded ? String(stats.pendingRequests) : "—";
        document.getElementById("statApprovedRequests").textContent = requestsLoaded ? String(stats.approvedRequests) : "—";
        const marketplaceSummary = document.getElementById("marketplaceDashboardSummary");
        marketplaceSummary.hidden = !marketplaceEnabled;
        if (marketplaceEnabled) {
            const marketStats = ui.dashboardMarketplaceStats(resources, borrowingRequests, transferRequests, currentSession.user.id);
            const fields = {
                statActiveBorrowListings: marketStats.activeBorrowListings,
                statActiveSellListings: marketStats.activeSellListings,
                statActiveDonateListings: marketStats.activeDonateListings,
                statIncomingRequests: marketStats.incomingRequests,
                statOutgoingRequests: marketStats.outgoingRequests,
                statCompletedBorrowReturns: marketStats.completedBorrowReturns,
                statCompletedSales: marketStats.completedSales,
                statCompletedDonations: marketStats.completedDonations
            };
            Object.entries(fields).forEach(function (entry) {
                document.getElementById(entry[0]).textContent = resourcesLoaded && requestsLoaded && marketplaceDataLoaded ? String(entry[1]) : "—";
            });
        }
        welcomeSummary.textContent = resourcesLoaded && requestsLoaded
            ? `You have ${stats.myResources} ${stats.myResources === 1 ? "resource" : "resources"} listed and ${borrowingRequests.length} borrowing ${borrowingRequests.length === 1 ? "request" : "requests"} visible to your account.`
            : "Your resources and borrowing activity are loading.";
        welcomeAvailableSummary.textContent = resourcesLoaded
            ? `${stats.availableResources} of your resources marked available`
            : "Available resources are loading…";
        welcomeRequestSummary.textContent = requestsLoaded
            ? `${borrowingRequests.length} request records visible`
            : "Borrowing requests are loading…";

        recentResources.replaceChildren();
        const newestResources = ui.filterResources(resources, { sort: "newest" }).slice(0, 4);
        newestResources.forEach(function (resource) {
            const row = document.createElement("div");
            row.className = "recent-resource";
            const copy = document.createElement("div");
            copy.className = "recent-resource-copy";
            const title = document.createElement("strong");
            title.textContent = resource.title || "Untitled resource";
            const meta = document.createElement("small");
            meta.textContent = `${categoryName(resource)} · ${resource.availability_status || "Unknown"}`;
            copy.append(title, meta);
            const details = makeActionButton("Details", "secondary-btn", function () {
                openResourceDetails(resource);
            });
            row.append(copy, details);
            recentResources.appendChild(row);
        });
        recentResourcesEmpty.hidden = resourcesLoaded && newestResources.length !== 0;
        if (!resourcesLoaded) {
            recentResourcesEmpty.textContent = "Resources are loading or could not be loaded.";
            recentResourcesEmpty.hidden = false;
        } else {
            recentResourcesEmpty.textContent = "No resources have been shared yet.";
        }

        renderMyActivity();
        statGrid.setAttribute("aria-busy", resourcesLoaded && requestsLoaded ? "false" : "true");
    }

    function getStudentDisplayName() {
        const user = currentSession && currentSession.user;
        const metadataName = user && user.user_metadata && typeof user.user_metadata.full_name === "string"
            ? user.user_metadata.full_name.trim()
            : "";
        return metadataName || "Student";
    }

    function renderMyActivity() {
        myActivityList.replaceChildren();
        if (!requestsLoaded) {
            myActivityEmpty.textContent = "Borrowing activity is loading or could not be loaded.";
            myActivityEmpty.hidden = false;
            return;
        }

        const userId = String(currentSession.user.id);
        const ownedIds = new Set(resources
            .filter(function (resource) { return String(resource.owner_id) === userId; })
            .map(function (resource) { return String(resource.id); }));
        const activity = borrowingRequests.map(function (request) {
            const isBorrower = String(request.borrower_id) === userId;
            const isOwnerRequest = ownedIds.has(String(request.resource_id)) && !isBorrower;
            if (!isBorrower && !isOwnerRequest) return null;
            const resource = resources.find(function (item) {
                return String(item.id) === String(request.resource_id);
            });
            return {
                request: request,
                title: resource && resource.title ? resource.title : "Resource request",
                label: isBorrower ? "You requested" : "Request for your resource",
                date: Date.parse(request.requested_at || "") || 0
            };
        }).filter(Boolean).sort(function (left, right) {
            return right.date - left.date;
        }).slice(0, 4);

        if (activity.length === 0) {
            myActivityEmpty.textContent = "No borrowing activity is available yet.";
            myActivityEmpty.hidden = false;
            return;
        }
        myActivityEmpty.hidden = true;
        activity.forEach(function (item) {
            const row = document.createElement("div");
            row.className = "activity-row";
            const details = document.createElement("div");
            details.className = "activity-copy";
            const label = document.createElement("strong");
            label.textContent = `${item.label} · ${item.title}`;
            const date = document.createElement("small");
            date.textContent = item.request.requested_at ? formatDate(item.request.requested_at) : "Date not provided";
            details.append(label, date);
            const status = document.createElement("span");
            status.className = `request-status status-${String(item.request.status || "unknown").toLowerCase()}`;
            status.textContent = item.request.status || "Unknown";
            row.append(details, status);
            myActivityList.appendChild(row);
        });
    }

    function filteredResources() {
        let mode = listingModeFilter.value;
        if (currentRoute === "sell") {
            mode = "sell";
        } else if (currentRoute === "donate") {
            mode = "donate";
        } else if (myResourcesOnly) {
            mode = myResourcesActiveSubTab;
        }

        return ui.filterResources(resources, {
            query: searchInput.value,
            categoryId: categoryFilter.value,
            resourceType: resourceTypeFilter.value,
            listingMode: mode,
            availability: availabilityFilter.value,
            minPrice: priceMinFilter.value,
            maxPrice: priceMaxFilter.value,
            condition: conditionFilter.value,
            ownerId: myResourcesOnly && currentSession && currentSession.user
                ? currentSession.user.id
                : null,
            sort: sortSelect.value
        });
    }

    async function openResourceDetails(resource) {
        const generation = ++resourceDetailsGeneration;
        resourceDetailsTitle.textContent = "Loading resource…";
        resourceDetailsDescription.textContent = "Loading the latest resource details.";
        document.getElementById("resourceDetailsList").replaceChildren();
        const detailsImages = document.getElementById("resourceDetailsImages");
        detailsImages.replaceChildren();
        detailsImages.hidden = true;
        resourceDetailsActions.replaceChildren();
        resourceDetailsFeatureNote.hidden = true;
        resourceDetailsDialog.showModal();
        try {
            const latestResource = await api.resource(resource.id);
            if (generation !== resourceDetailsGeneration || !resourceDetailsDialog.open) return;
            renderResourceDetails(latestResource);
        } catch (error) {
            if (generation !== resourceDetailsGeneration || !resourceDetailsDialog.open) return;
            resourceDetailsTitle.textContent = resource.title || "Resource details";
            resourceDetailsDescription.textContent = "Could not load the latest resource details. " + errorMessage(error);
            document.getElementById("resourceDetailsList").replaceChildren();
            resourceDetailsActions.replaceChildren();
        }
    }

    function renderResourceDetails(resource) {
        document.getElementById("resourceDetailsTitle").textContent = resource.title || "Untitled resource";
        document.getElementById("resourceDetailsDescription").textContent = resource.description || "No description provided.";
        const paymentApplies = marketplaceEnabled &&
            (resource.listing_mode === "sell" ||
             (resource.listing_mode === "borrow" && resource.borrow_price_kind && resource.borrow_price_kind !== "free"));
        document.getElementById("resourcePaymentDisclaimer").hidden = !paymentApplies;
        loadImageStrip(document.getElementById("resourceDetailsImages"), resource.id);
        loadPrivateHandover(resource);
        document.getElementById("borrowDueDateWrap").hidden = !(marketplaceEnabled && (resource.listing_mode || "borrow") === "borrow");
        document.getElementById("borrowDueDate").value = "";
        const details = document.getElementById("resourceDetailsList");
        details.replaceChildren();
        [
            ["Category", categoryName(resource)],
            ["Type", resource.resource_type || "Not specified"],
            ["Availability", resource.availability_status || "Not specified"],
            ...(marketplaceEnabled ? [
                ["Listing", resource.listing_mode || "borrow"],
                ["Listing status", resource.listing_state || "active"],
                ["Price", resourcePriceSummary(resource)],
                ...(resource.item_condition ? [["Condition", itemConditionLabel(resource.item_condition)]] : []),
                ...(resource.purchase_year ? [["Purchase year", String(resource.purchase_year)]] : [])
            ] : []),
            ["Owner", ui.isOwnResource(resource, currentSession && currentSession.user && currentSession.user.id)
                ? "You"
                : "Owner profile details are not provided by this API"],
            ["Added", formatDate(resource.created_at)]
        ].forEach(function (entry) {
            const term = document.createElement("dt");
            term.textContent = entry[0];
            const value = document.createElement("dd");
            value.textContent = entry[1];
            details.append(term, value);
        });
        resourceDetailsActions.replaceChildren();
        resourceDetailsFeatureNote.hidden = true;
        const isOwner = ui.isOwnResource(resource, currentSession && currentSession.user && currentSession.user.id);
        if (isOwner) {
            resourceDetailsActions.appendChild(makeActionButton("Edit listing", "secondary-btn", function () {
                resourceDetailsDialog.close();
                openResourceForm(resource);
            }));
            resourceDetailsActions.appendChild(makeActionButton("Delete listing", "danger-btn", function (event) {
                resourceDetailsDialog.close();
                deleteResource(resource, event.currentTarget);
            }));
        } else if (resource.availability_status === "available") {
            if (marketplaceEnabled && (resource.listing_mode === "sell" || resource.listing_mode === "donate") && resource.listing_state === "active") {
                if (!hasActiveTransferRequest(resource.id)) {
                    resourceDetailsActions.appendChild(makeActionButton(
                        resource.listing_mode === "sell" ? "Request to buy" : "Request donation",
                        "borrow-btn", function (event) { submitTransferRequest(resource, event.currentTarget); }
                    ));
                } else {
                    resourceDetailsFeatureNote.textContent = "You already have an active request for this listing.";
                    resourceDetailsFeatureNote.hidden = false;
                }
            } else if (ui.canRequestBorrow(resource, {
                userId: currentSession && currentSession.user && currentSession.user.id,
                borrowingEnabled: borrowRequestRpcEnabled,
                hasActiveRequest: hasActiveOwnRequest(resource.id)
            })) {
                resourceDetailsActions.appendChild(makeActionButton("Request to borrow", "borrow-btn", function (event) {
                    resourceDetailsDialog.close();
                    submitBorrowRequest(resource, event.currentTarget);
                }));
            } else if (!borrowRequestRpcEnabled) {
                resourceDetailsFeatureNote.textContent = "Borrow requests are disabled until the secure staging RPC is verified.";
                resourceDetailsFeatureNote.hidden = false;
            } else if (hasActiveOwnRequest(resource.id)) {
                resourceDetailsFeatureNote.textContent = "You already have a pending or approved request for this resource.";
                resourceDetailsFeatureNote.hidden = false;
            }
        }
        if (!isOwner && marketplaceEnabled) {
            resourceDetailsActions.appendChild(makeActionButton("Report listing", "secondary-btn", function () {
                reportResourceId = resource.id;
                listingReportForm.reset();
                listingReportStatus.textContent = "";
                listingReportDialog.showModal();
            }));
        }
    }

    function makeActionButton(label, className, onClick) {
        const button = document.createElement("button");
        button.type = "button";
        button.className = className;
        button.textContent = label;
        button.addEventListener("click", onClick);
        return button;
    }

    function renderResources() {
        const rows = filteredResources();
        const userId = currentSession && currentSession.user ? String(currentSession.user.id) : "";
        resourceGrid.replaceChildren();
        resourceViewTitle.textContent = resourceViewHeading();
        resourceCount.textContent = myResourcesOnly
            ? `${rows.length} of ${resources.length} loaded resources are yours`
            : `${rows.length} shown · ${resources.length} loaded`;
        updateActiveFilterUI(rows.length, resources.length);

        rows.forEach(function (resource) {
            const card = document.createElement("article");
            card.className = "resource-card";
            const imageStrip = document.createElement("div");
            imageStrip.className = "resource-card-images";
            imageStrip.hidden = true;
            card.appendChild(imageStrip);
            loadImageStrip(imageStrip, resource.id);

            const icon = document.createElement("div");
            icon.className = "resource-icon";
            icon.textContent = "📚";
            const heading = document.createElement("h3");
            heading.textContent = resource.title || "Untitled resource";
            const description = document.createElement("p");
            description.textContent = resource.description || "No description provided.";
            const badges = document.createElement("div");
            badges.className = "resource-badges";
            const category = document.createElement("span");
            category.textContent = categoryName(resource);
            const availability = document.createElement("span");
            availability.className = `availability-badge ${resource.availability_status === "available" ? "is-available" : resource.availability_status === "unavailable" ? "is-unavailable" : ""}`;
            availability.textContent = resource.availability_status || "Unknown";
            badges.append(category, availability);
            if (marketplaceEnabled) {
                const listing = document.createElement("span");
                listing.className = "listing-mode-badge";
                listing.textContent = resource.listing_mode === "sell" ? "For sale" : resource.listing_mode === "donate" ? "Donation" : "Borrow / lend";
                badges.appendChild(listing);
                if (resource.listing_state === "sold" || resource.listing_state === "donated" || resource.listing_state === "reserved") {
                    const stateBadge = document.createElement("span");
                    stateBadge.className = "request-status";
                    stateBadge.textContent = resource.listing_state === "sold" ? "Sold" : resource.listing_state === "donated" ? "Donated" : "Reserved";
                    badges.appendChild(stateBadge);
                }
            }
            card.append(icon, heading, description, badges);
            const type = document.createElement("small");
            type.className = "resource-type";
            type.textContent = resource.resource_type || "Resource type not specified";
            card.appendChild(type);
            if (marketplaceEnabled) {
                const price = document.createElement("p");
                price.className = "resource-price";
                price.textContent = resourcePriceSummary(resource);
                card.appendChild(price);
                if (resource.listing_mode === "sell" ||
                    (resource.listing_mode === "borrow" && resource.borrow_price_kind && resource.borrow_price_kind !== "free")) {
                    const paymentNote = document.createElement("small");
                    paymentNote.className = "payment-note";
                    paymentNote.textContent = "Students arrange payment directly; CampusShare does not process or verify it.";
                    card.appendChild(paymentNote);
                }
                if (resource.listing_mode === "sell" && resource.item_condition) {
                    const condition = document.createElement("small");
                    condition.textContent = `${itemConditionLabel(resource.item_condition)}${resource.purchase_year ? ` · Purchased ${resource.purchase_year}` : ""}`;
                    card.appendChild(condition);
                }
            }

            const actions = document.createElement("div");
            actions.className = "resource-actions";
            actions.appendChild(makeActionButton("Details", "secondary-btn", function () {
                return openResourceDetails(resource);
            }));

            const isOwner = ui.isOwnResource(resource, userId);
            if (isOwner) {
                actions.appendChild(makeActionButton("Edit", "secondary-btn", function () {
                    openResourceForm(resource);
                }));
                actions.appendChild(makeActionButton("Delete", "danger-btn", function (event) {
                    deleteResource(resource, event.currentTarget);
                }));
            } else if (marketplaceEnabled && !isOwner && resource.availability_status === "available" && resource.listing_state === "active" &&
                (resource.listing_mode === "sell" || resource.listing_mode === "donate") && !hasActiveTransferRequest(resource.id)) {
                actions.appendChild(makeActionButton(resource.listing_mode === "sell" ? "Request to buy" : "Request donation", "borrow-btn", function (event) {
                    submitTransferRequest(resource, event.currentTarget);
                }));
            } else if (ui.canRequestBorrow(resource, {
                userId: userId,
                borrowingEnabled: borrowRequestRpcEnabled,
                hasActiveRequest: hasActiveOwnRequest(resource.id)
            })) {
                actions.appendChild(makeActionButton("Request to borrow", "borrow-btn", function (event) {
                    submitBorrowRequest(resource, event.currentTarget);
                }));
            } else if (!isOwner && (hasActiveOwnRequest(resource.id) || hasActiveTransferRequest(resource.id))) {
                const pending = document.createElement("small");
                pending.className = "pending-note";
                pending.textContent = "You already have an active request";
                actions.appendChild(pending);
            }
            card.appendChild(actions);
            resourceGrid.appendChild(card);
        });

        const showEmpty = Boolean(currentSession) && resourcesLoaded && rows.length === 0;
        noResults.hidden = !showEmpty;
        if (showEmpty && resources.length === 0) {
            emptyTitle.textContent = myResourcesOnly ? "Your shelf is ready" : "No resources yet";
            emptyMessage.textContent = myResourcesOnly
                ? "Add your first resource and make it available to your campus."
                : "There are no resources in the records returned by the backend yet.";
            emptyAddResource.hidden = !canAddFromCurrentRoute();
        } else if (showEmpty) {
            emptyTitle.textContent = "No matching resources";
            emptyMessage.textContent = myResourcesOnly
                ? "Your loaded listings do not match these filters. Clear filters or browse the library."
                : "Try another search or filter, or clear them to see the loaded list.";
            emptyAddResource.hidden = !myResourcesOnly || !canAddFromCurrentRoute();
        }
        borrowStatusFeatureNote.hidden = borrowStatusRpcEnabled;
    }

    function formatDate(value) {
        if (!value) return "Not set";
        const date = new Date(value);
        return Number.isNaN(date.getTime()) ? String(value) : date.toLocaleString();
    }

    async function signedResourceImages(resourceId) {
        if (!resourceImagesEnabled || !auth || typeof auth.createResourceImageUrls !== "function") return [];
        const records = await api.resourceImages(resourceId);
        if (!records.length) return [];
        const result = await auth.createResourceImageUrls(records.map(function (record) { return record.storage_path; }));
        if (result.error) throw result.error;
        const urls = result.data || [];
        return records.map(function (record) {
            const match = urls.find(function (item) { return item.path === record.storage_path; });
            return match && typeof match.signedUrl === "string" ? { record: record, url: match.signedUrl } : null;
        }).filter(Boolean);
    }

    function appendImageStrip(container, images) {
        container.replaceChildren();
        images.slice().sort(function (a, b) {
            return Number(a.record.sort_order) - Number(b.record.sort_order);
        }).forEach(function (image, index) {
            const img = document.createElement("img");
            img.src = image.url;
            img.alt = image.record.alt_text || "Photo of this resource";
            img.loading = "lazy";
            if (index === 0) {
                img.className = "primary-resource-image";
                img.setAttribute("data-primary-image", "true");
            }
            container.appendChild(img);
        });
        container.hidden = images.length === 0;
    }

    async function loadImageStrip(container, resourceId) {
        if (!resourceImagesEnabled || !container) return;
        const generation = (imageStripGenerations.get(container) || 0) + 1;
        imageStripGenerations.set(container, generation);
        try {
            const images = await signedResourceImages(resourceId);
            if (imageStripGenerations.get(container) === generation) appendImageStrip(container, images);
        } catch (_error) {
            if (imageStripGenerations.get(container) === generation) {
                container.replaceChildren();
                container.hidden = true;
            }
        }
    }

    async function renderExistingImages(resource, generation) {
        existingImageList.replaceChildren();
        existingImageCount = 0;
        existingPrimaryImage = false;
        if (!resource || !resourceImagesEnabled) return;
        let images;
        try { images = await signedResourceImages(resource.id); }
        catch (error) {
            if (generation === resourceFormGeneration) setResourceFormStatus("Saved photos could not be loaded. Refresh the listing before changing its images.", "error");
            return false;
        }
        if (generation !== resourceFormGeneration || resourceForm.dataset.resourceId !== String(resource.id)) return false;
        images = images.slice().sort(function (a, b) {
            return Number(a.record.sort_order) - Number(b.record.sort_order);
        });
        existingImageCount = images.length;
        existingPrimaryImage = images.some(function (image) { return Number(image.record.sort_order) === 0; });
        images.forEach(function (image, imageIndex) {
            const wrapper = document.createElement("div");
            wrapper.className = "image-preview-item saved-image-preview";
            wrapper.dataset.imageId = String(image.record.id);
            const img = document.createElement("img");
            img.src = image.url;
            img.alt = image.record.alt_text || "Saved resource image";
            if (Number(image.record.sort_order) === 0) {
                const badge = document.createElement("span");
                badge.className = "primary-image-badge";
                badge.textContent = "Primary";
                wrapper.appendChild(badge);
            }
            const remove = makeActionButton("Remove photo", "danger-btn", async function (event) {
                const button = event.currentTarget;
                setButtonBusy(button, true, "Removing…");
                try {
                    await api.deleteResourceImage(image.record.id);
                    existingImageCount = Math.max(0, existingImageCount - 1);
                    if (Number(image.record.sort_order) === 0) existingPrimaryImage = false;
                    setResourceFormStatus("Photo removed.", "success");
                    await renderExistingImages(resource, generation);
                    await loadLibrary();
                } catch (error) {
                    setResourceFormStatus(errorMessage(error), "error");
                } finally { if (button.isConnected) setButtonBusy(button, false); }
            });
            const orderControls = document.createElement("div");
            orderControls.className = "resource-actions saved-image-order-controls";
            if (images.length > 1 && imageIndex > 0) {
                orderControls.appendChild(makeActionButton("Move earlier", "secondary-btn", function () {
                    persistSavedImageMove(resource, generation, imageIndex, imageIndex - 1);
                }));
            }
            if (images.length > 1 && imageIndex < images.length - 1) {
                orderControls.appendChild(makeActionButton("Move later", "secondary-btn", function () {
                    persistSavedImageMove(resource, generation, imageIndex, imageIndex + 1);
                }));
            }
            wrapper.append(img, orderControls, remove);
            existingImageList.appendChild(wrapper);
        });
        return true;
    }

    async function persistSavedImageMove(resource, generation, fromIndex, toIndex) {
        const ordered = Array.from(existingImageList.children);
        if (fromIndex < 0 || toIndex < 0 || fromIndex >= ordered.length || toIndex >= ordered.length) return;
        const [moved] = ordered.splice(fromIndex, 1);
        ordered.splice(toIndex, 0, moved);
        try {
            await api.reorderResourceImages(resource.id, ordered.map(function (item) { return item.dataset.imageId; }));
            setResourceFormStatus("Saved photo order updated.", "success");
            await renderExistingImages(resource, generation);
            await loadLibrary();
        } catch (error) {
            setResourceFormStatus(errorMessage(error), "error");
            await renderExistingImages(resource, generation);
        }
    }

    function renderSelectedImages() {
        imagePreviewList.replaceChildren();
        selectedImageFiles.forEach(function (file, index) {
            const wrapper = document.createElement("div");
            wrapper.className = "image-preview-item";
            const img = document.createElement("img");
            if (window.URL && typeof window.URL.createObjectURL === "function") {
                const url = window.URL.createObjectURL(file);
                img.src = url;
                img.addEventListener("load", function () { window.URL.revokeObjectURL(url); }, { once: true });
            }
            img.alt = file.name;
            if (index === 0 && !existingPrimaryImage) {
                const badge = document.createElement("span");
                badge.className = "primary-image-badge";
                badge.textContent = "Primary image";
                wrapper.appendChild(badge);
            }
            const remove = makeActionButton("Remove", "secondary-btn", function () {
                selectedImageFiles.splice(index, 1);
                if (selectedImageFiles.length && index === 0 && !existingPrimaryImage) {
                    setResourceFormStatus("The first selected photo is the primary image.", "info");
                }
                renderSelectedImages();
            });
            const controls = [remove];
            if (index > 0 && !existingPrimaryImage) {
                controls.push(makeActionButton("Make primary", "secondary-btn", function () {
                    selectedImageFiles.unshift(selectedImageFiles.splice(index, 1)[0]);
                    setResourceFormStatus("Primary image selected. The first photo is shown as the listing cover.", "success");
                    renderSelectedImages();
                }));
            }
            if (index > 1) {
                controls.push(makeActionButton("Move earlier", "secondary-btn", function () {
                    const previous = selectedImageFiles[index - 1];
                    selectedImageFiles[index - 1] = selectedImageFiles[index];
                    selectedImageFiles[index] = previous;
                    renderSelectedImages();
                }));
            }
            if (index < selectedImageFiles.length - 1) {
                controls.push(makeActionButton("Move later", "secondary-btn", function () {
                    const next = selectedImageFiles[index + 1];
                    selectedImageFiles[index + 1] = selectedImageFiles[index];
                    selectedImageFiles[index] = next;
                    renderSelectedImages();
                }));
            }
            wrapper.append(img, ...controls);
            imagePreviewList.appendChild(wrapper);
        });
        if (existingPrimaryImage && selectedImageFiles.length) {
            setResourceFormStatus("The saved primary photo stays first. Remove it before choosing a newly uploaded photo as the primary image.", "info");
        }
    }

    function validateSelectedImages(files) {
        if (existingImageCount + files.length + selectedImageFiles.length > 10) return "Choose no more than 10 images per resource.";
        const allowed = new Set(["image/jpeg", "image/png", "image/webp"]);
        for (const file of files) {
            if (!allowed.has(file.type)) return "Images must be JPEG, PNG, or WebP files.";
            if (file.size <= 0 || file.size > 5 * 1024 * 1024) return "Each image must be between 1 byte and 5 MiB.";
        }
        return "";
    }

    async function uploadSelectedImages(resourceId) {
        if (!selectedImageFiles.length) return;
        if (!resourceImagesEnabled) throw new Error("Resource image uploads are disabled by backend configuration.");
        const userId = currentSession && currentSession.user && currentSession.user.id;
        if (!userId) throw new Error("Sign in before uploading resource images.");
        const savedImages = await api.resourceImages(resourceId);
        if (savedImages.length + selectedImageFiles.length > 10)
            throw new Error("A resource can have no more than 10 photos. Remove an existing photo before adding another.");
        const usedOrders = new Set(savedImages.map(function (image) { return Number(image.sort_order); }));
        const availableOrders = Array.from({ length: 10 }, function (_value, index) { return index; })
            .filter(function (index) { return !usedOrders.has(index); });
        if (availableOrders.length < selectedImageFiles.length)
            throw new Error("No photo order slots remain. Remove a photo before adding another.");
        const uploaded = [];
        const attemptedPaths = [];
        try {
            for (const [index, file] of selectedImageFiles.entries()) {
                const extension = file.type === "image/jpeg" ? "jpg" : file.type === "image/png" ? "png" : "webp";
                const randomPart = window.crypto && typeof window.crypto.randomUUID === "function"
                    ? window.crypto.randomUUID() : `${Date.now()}-${Math.random().toString(36).slice(2)}`;
                const path = `${userId}/${resourceId}/${randomPart}.${extension}`;
                attemptedPaths.push(path);
                const result = await auth.uploadResourceImage(path, file);
                if (result.error) throw result.error;
                uploaded.push({ storage_path: path, alt_text: file.name.slice(0, 200), sort_order: availableOrders[index] });
            }
            await api.addResourceImages(resourceId, uploaded);
            selectedImageFiles = [];
            renderSelectedImages();
        } catch (error) {
            if (attemptedPaths.length) {
                const cleanup = await auth.removeResourceImages(attemptedPaths);
                if (cleanup.error) throw new Error("Image upload failed and automatic cleanup was denied. Remove the uploaded file from this listing before retrying.");
            }
            throw error;
        }
    }

    async function saveHandover(resourceId) {
        if (!marketplaceEnabled) return;
        const location = document.getElementById("pickupLocation").value.trim();
        const meetingPoint = document.getElementById("meetingPoint").value.trim();
        const phone = document.getElementById("contactPhone") ? document.getElementById("contactPhone").value.trim() : "";
        if (!location || !meetingPoint) throw new Error("Enter both a campus pickup location and a separate meeting point.");
        const rawInstructions = document.getElementById("handoverInstructions").value.trim();
        let combinedInstructions = rawInstructions;
        if (phone) {
            combinedInstructions = `Phone: ${phone}${rawInstructions ? "\nNotes: " + rawInstructions : ""}`;
        }
        await api.saveHandoverDetails(resourceId, {
            pickup_location: location,
            meeting_point: meetingPoint,
            preferred_pickup_time: document.getElementById("preferredPickupTime").value.trim() || null,
            instructions: combinedInstructions || null
        });
    }

    async function loadPrivateHandover(resource) {
        const panel = document.getElementById("handoverDetailsPanel");
        const detailsText = document.getElementById("handoverDetailsText");
        const generation = resourceDetailsGeneration;
        panel.hidden = true;
        if (!marketplaceEnabled) return;
        try {
            const details = await api.handoverDetails(resource.id);
            if (generation !== resourceDetailsGeneration || !resourceDetailsDialog.open) return;
            if (!details) return;

            let phone = "";
            let notes = details.instructions || "";
            const phoneMatch = notes.match(/^Phone:\s*([^\n\r]+)/i);
            if (phoneMatch) {
                phone = phoneMatch[1].trim();
                notes = notes.replace(/^Phone:\s*[^\n\r]+(\r?\nNotes:\s*|\r?\n)?/i, "").trim();
            }

            const cleanPhone = phone.replace(/[^\d+]/g, "");
            const whatsappNumber = cleanPhone.replace(/^\+/, "");
            const whatsappLink = whatsappNumber ? `https://wa.me/${whatsappNumber}` : null;

            if (detailsText) {
                detailsText.replaceChildren();
                if (phone) {
                    const phoneCard = document.createElement("div");
                    phoneCard.className = "handover-phone-card";

                    const label = document.createElement("div");
                    label.className = "phone-label";
                    label.textContent = "📞 Owner Contact Phone (Approved Request)";
                    phoneCard.appendChild(label);

                    const phoneRow = document.createElement("div");
                    phoneRow.className = "phone-number";

                    const phoneLink = document.createElement("a");
                    phoneLink.className = "phone-link";
                    phoneLink.href = `tel:${cleanPhone}`;
                    phoneLink.textContent = phone;
                    phoneRow.appendChild(phoneLink);

                    if (whatsappLink) {
                        const waBtn = document.createElement("a");
                        waBtn.className = "whatsapp-btn";
                        waBtn.href = whatsappLink;
                        waBtn.target = "_blank";
                        waBtn.rel = "noopener noreferrer";
                        waBtn.textContent = "💬 Chat on WhatsApp";
                        phoneRow.appendChild(waBtn);
                    }

                    phoneCard.appendChild(phoneRow);
                    detailsText.appendChild(phoneCard);
                }

                const rows = [
                    details.pickup_location && ["📍 Campus Pickup Location", details.pickup_location],
                    details.meeting_point && ["🤝 Meeting Point", details.meeting_point],
                    details.preferred_pickup_time && ["⏰ Preferred Time", details.preferred_pickup_time],
                    notes && ["📝 Notes", notes]
                ].filter(Boolean);

                rows.forEach(function (row) {
                    const rowElem = document.createElement("div");
                    rowElem.className = "handover-contact-row";
                    const strong = document.createElement("strong");
                    strong.textContent = `${row[0]}: `;
                    rowElem.appendChild(strong);
                    rowElem.appendChild(document.createTextNode(row[1]));
                    detailsText.appendChild(rowElem);
                });
            }

            const hasAny = Boolean(phone || details.pickup_location || details.meeting_point || details.preferred_pickup_time || notes);
            panel.hidden = !hasAny;
        } catch (_error) {
            // RLS intentionally hides handover data from unrelated users.
        }
    }

    function appendRequestImageGallery(card, resource) {
        if (!resourceImagesEnabled || !resource) return;
        const gallery = document.createElement("div");
        gallery.className = "resource-card-images request-card-images";
        gallery.hidden = true;
        card.appendChild(gallery);
        loadImageStrip(gallery, resource.id);
    }

    function makeRequestCard(request, isOwnerView) {
        const resource = resources.find(function (item) {
            return String(item.id) === String(request.resource_id);
        });
        const card = document.createElement("article");
        card.className = "borrow-request-card";
        const title = document.createElement("h4");
        title.textContent = resource ? resource.title : "Resource no longer visible";
        const status = document.createElement("span");
        const allowedStatuses = ["pending", "approved", "rejected", "returned"];
        const statusValue = allowedStatuses.includes(request.status) ? request.status : "unknown";
        status.className = `request-status status-${statusValue}`;
        status.textContent = statusValue === "unknown" ? "Unknown" : statusValue;
        const requested = document.createElement("p");
        requested.textContent = `Requested: ${formatDate(request.requested_at)}`;
        const due = document.createElement("p");
        due.textContent = `Due: ${formatDate(request.due_at)}`;
        card.append(title, status, requested, due);
        appendRequestImageGallery(card, resource);
        if (request.returned_at) {
            const returned = document.createElement("p");
            returned.textContent = `Returned: ${formatDate(request.returned_at)}`;
            card.appendChild(returned);
        }
        const ownerActions = ui.ownerRequestActions(request, {
            isOwner: isOwnerView,
            statusActionsEnabled: borrowStatusRpcEnabled
        });
        if (ownerActions.length > 0) {
            const actions = document.createElement("div");
            actions.className = "resource-actions";
            if (ownerActions.includes("approve")) {
                const dueLabel = document.createElement("label");
                dueLabel.textContent = "Approved due date (optional)";
                const dueInput = document.createElement("input");
                dueInput.type = "date";
                dueInput.className = "borrow-due-date";
                dueInput.value = request.due_at ? String(request.due_at).slice(0, 10) : "";
                actions.append(dueLabel, dueInput);
            }
            ownerActions.forEach(function (action) {
                const label = action === "approve" ? "Approve" : action === "reject" ? "Reject" : "Confirm return";
                const buttonClass = action === "reject" ? "danger-btn" : "borrow-btn";
                actions.appendChild(makeActionButton(label, buttonClass, function (event) {
                    updateBorrowRequestStatus(request, action, event.currentTarget);
                }));
            });
            card.appendChild(actions);
        } else if (isOwnerView) {
            const note = document.createElement("small");
            note.className = "pending-note";
            note.textContent = borrowStatusRpcEnabled
                ? (request.status === "returned" ? "✓ Returned & loan completed" : request.status === "rejected" ? "✕ Request rejected" : "This request has no owner action in its current status.")
                : "Submitted by another student. Owner actions appear when the secure staging workflow is enabled.";
            card.appendChild(note);
        }
        if (resource && (request.status === "approved" || request.status === "return_requested")) {
            card.appendChild(makeActionButton("View Contact & Handover", "secondary-btn", function () {
                openResourceDetails(resource);
            }));
        }
        return card;
    }

    async function updateBorrowRequestStatus(request, action, button) {
        const requestId = String(request.id);
        if (borrowStatusBusy.has(requestId)) return;
        borrowStatusBusy.add(requestId);
        setButtonBusy(button, true, action === "approve" ? "Approving…" : action === "reject" ? "Rejecting…" : "Confirming…");
        setBorrowStatus("");
        try {
            if (action === "approve") {
                const dueInput = button.closest(".borrow-request-card")?.querySelector(".borrow-due-date");
                const dueAt = dueInput && dueInput.value
                    ? `${dueInput.value}T23:59:59Z`
                    : null;
                if (dueAt && request.requested_at && dueAt < request.requested_at)
                    throw new Error("The due date cannot be earlier than the request date.");
                await api.approveBorrowRequest(requestId, dueAt);
            } else if (action === "reject") {
                await api.rejectBorrowRequest(requestId);
            } else {
                await api.returnBorrowedResource(requestId);
            }
            const refreshed = await loadLibrary();
            const msg = refreshed
                ? (action === "approve" ? "Borrowing request approved." : action === "reject" ? "Borrowing request rejected." : "Resource marked as returned.")
                : "Request updated, but the latest data could not be loaded.";
            setStatus(msg, refreshed ? "success" : "error");
            setBorrowStatus(msg, refreshed ? "success" : "error");
        } catch (error) {
            const err = errorMessage(error);
            setStatus(err, "error");
            setBorrowStatus(err, "error");
        } finally {
            borrowStatusBusy.delete(requestId);
            if (button.isConnected) setButtonBusy(button, false);
        }
    }

    function renderBorrowRequests() {
        myBorrowRequests.replaceChildren();
        ownerBorrowRequests.replaceChildren();
        const userId = currentSession && currentSession.user ? String(currentSession.user.id) : "";
        const myRequests = borrowingRequests.filter(function (request) {
            return String(request.borrower_id) === userId;
        });
        const myResourceIds = new Set(resources
            .filter(function (resource) { return String(resource.owner_id) === userId; })
            .map(function (resource) { return String(resource.id); }));
        const ownerRequests = borrowingRequests.filter(function (request) {
            return myResourceIds.has(String(request.resource_id)) &&
                String(request.borrower_id) !== userId;
        });

        myRequests.forEach(function (request) { myBorrowRequests.appendChild(makeRequestCard(request, false)); });
        ownerRequests.forEach(function (request) { ownerBorrowRequests.appendChild(makeRequestCard(request, true)); });
        myBorrowEmpty.hidden = !requestsLoaded || myRequests.length !== 0;
        ownerBorrowEmpty.hidden = !requestsLoaded || ownerRequests.length !== 0;
        renderDashboard();
    }

    async function loadBorrowRequests(generation) {
        try {
            const requests = await api.borrowRequests();
            if (generation !== requestGeneration) return false;
            borrowingRequests = requests;
            requestsLoaded = true;
            renderResources();
            renderBorrowRequests();
            setBorrowStatus("");
            return true;
        } catch (error) {
            if (generation !== requestGeneration) return false;
            borrowingRequests = [];
            requestsLoaded = false;
            renderBorrowRequests();
            renderDashboard();
            statGrid.setAttribute("aria-busy", "false");
            setBorrowStatus(errorMessage(error), "error");
            return false;
        }
    }

    function makeTransferCard(request, ownerView) {
        const resource = resources.find(function (item) { return String(item.id) === String(request.resource_id); });
        const card = document.createElement("article");
        card.className = "borrow-request-card";
        const title = document.createElement("h4");
        title.textContent = resource ? resource.title : `Resource ${request.resource_id}`;
        const status = document.createElement("span");
        const statusValue = ["pending", "approved", "rejected", "completed", "cancelled"].includes(request.status) ? request.status : "unknown";
        status.className = `request-status status-${statusValue}`;
        status.textContent = `${request.request_type === "sell" ? "Sale" : "Donation"} · ${statusValue}`;
        const date = document.createElement("p");
        date.textContent = `Requested: ${formatDate(request.requested_at)}`;
        card.append(title, status, date);
        appendRequestImageGallery(card, resource);
        if (ownerView && request.status === "pending") {
            const actions = document.createElement("div");
            actions.className = "resource-actions";
            actions.appendChild(makeActionButton("Approve", "borrow-btn", function (event) { updateTransferRequest(request, "approve", event.currentTarget); }));
            actions.appendChild(makeActionButton("Reject", "danger-btn", function (event) { updateTransferRequest(request, "reject", event.currentTarget); }));
            card.appendChild(actions);
        } else if (ownerView && (request.request_type === "sell" || request.request_type === "donate") && request.status === "approved") {
            const action = request.request_type === "sell" ? "complete-sale" : "complete-donation";
            card.appendChild(makeActionButton(request.request_type === "sell" ? "Confirm sale completed" : "Confirm donation handover", "borrow-btn", function (event) {
                updateTransferRequest(request, action, event.currentTarget);
            }));
        } else if (!ownerView && request.status === "pending") {
            card.appendChild(makeActionButton("Cancel request", "danger-btn", function (event) {
                updateTransferRequest(request, "cancel", event.currentTarget);
            }));
        } else if (resource && (request.status === "approved" || request.status === "completed")) {
            card.appendChild(makeActionButton("View Contact & Handover", "secondary-btn", function () { openResourceDetails(resource); }));
        }
        return card;
    }

    function renderMarketplaceData() {
        marketplaceTransferSection.hidden = !marketplaceEnabled;
        myTransferRequests.replaceChildren();
        ownerTransferRequests.replaceChildren();
        myListingReports.replaceChildren();
        if (!marketplaceEnabled || !currentSession) return;
        const userId = String(currentSession.user.id);
        const sent = transferRequests.filter(function (request) { return String(request.requester_id) === userId; });
        const received = transferRequests.filter(function (request) { return String(request.owner_id) === userId; });
        sent.forEach(function (request) { myTransferRequests.appendChild(makeTransferCard(request, false)); });
        received.forEach(function (request) { ownerTransferRequests.appendChild(makeTransferCard(request, true)); });
        myTransferEmpty.hidden = sent.length > 0;
        ownerTransferEmpty.hidden = received.length > 0;
        listingReports.forEach(function (report) {
            const item = document.createElement("article");
            item.className = "borrow-request-card";
            const heading = document.createElement("h4");
            heading.textContent = report.reason.replaceAll("_", " ");
            const status = document.createElement("span");
            status.className = `request-status status-${report.status || "pending"}`;
            status.textContent = report.status || "pending";
            const details = document.createElement("p");
            details.textContent = report.details || "No additional details.";
            item.append(heading, status, details);
            const appMetadata = currentSession && currentSession.user && currentSession.user.app_metadata;
            if (appMetadata && appMetadata.campusshare_role === "moderator" && report.status === "pending") {
                const notes = document.createElement("textarea");
                notes.maxLength = 1000;
                notes.placeholder = "Optional moderation notes";
                notes.setAttribute("aria-label", "Moderation notes");
                const actions = document.createElement("div");
                actions.className = "resource-actions";
                ["resolved", "dismissed"].forEach(function (outcome) {
                    actions.appendChild(makeActionButton(outcome === "resolved" ? "Resolve report" : "Dismiss report", outcome === "dismissed" ? "danger-btn" : "borrow-btn", function (event) {
                        reviewListingReport(report, outcome, notes.value, event.currentTarget);
                    }));
                });
                item.append(notes, actions);
            }
            myListingReports.appendChild(item);
        });
        myReportsEmpty.hidden = listingReports.length > 0;
    }

    async function reviewListingReport(report, outcome, notes, button) {
        setButtonBusy(button, true, "Saving…");
        try {
            await api.reviewListingReport(report.id, outcome, notes);
            await loadLibrary();
            setBorrowStatus("Report review saved.", "success");
        } catch (error) {
            setBorrowStatus(errorMessage(error), "error");
        } finally { if (button.isConnected) setButtonBusy(button, false); }
    }

    async function loadMarketplaceData(generation) {
        if (!marketplaceEnabled || !currentSession) {
            transferRequests = [];
            listingReports = [];
            marketplaceDataLoaded = !marketplaceEnabled;
            renderMarketplaceData();
            renderDashboard();
            return true;
        }
        const results = await Promise.allSettled([api.transferRequests(), api.myListingReports()]);
        if (generation !== requestGeneration) return false;
        transferRequests = results[0].status === "fulfilled" ? results[0].value : [];
        listingReports = results[1].status === "fulfilled" ? results[1].value : [];
        marketplaceDataLoaded = results.every(function (result) { return result.status === "fulfilled"; });
        renderMarketplaceData();
        renderDashboard();
        const failed = results.find(function (result) { return result.status === "rejected"; });
        if (failed) setBorrowStatus("Some marketplace records could not be loaded: " + errorMessage(failed.reason), "error");
        return !failed;
    }

    async function updateTransferRequest(request, action, button) {
        setButtonBusy(button, true, action === "approve" ? "Approving…" : action === "reject" ? "Rejecting…" : "Saving…");
        try {
            if (action === "approve") await api.approveTransferRequest(request.id);
            else if (action === "reject") await api.rejectTransferRequest(request.id);
            else if (action === "complete-sale") await api.completeSale(request.id);
            else if (action === "complete-donation") await api.completeDonation(request.id);
            else if (action === "cancel") await api.cancelTransferRequest(request.id);
            await loadLibrary();
            const msg = action === "approve" ? "Transfer request approved." : action === "reject" ? "Transfer request rejected." : action === "cancel" ? "Transfer request cancelled." : "Transfer completed.";
            setBorrowStatus(msg, "success");
            setStatus(msg, "success");
        } catch (error) {
            const err = errorMessage(error);
            setBorrowStatus(err, "error");
            setStatus(err, "error");
        } finally { if (button.isConnected) setButtonBusy(button, false); }
    }

    async function submitTransferRequest(resource, button) {
        if (!marketplaceEnabled || !currentSession || !currentSession.user) return;
        if (ui.isOwnResource(resource, currentSession.user.id)) {
            setStatus("You cannot request your own resource.", "error");
            return;
        }
        if (resourceDetailsDialog.open) {
            resourceDetailsDialog.close();
        }
        setButtonBusy(button, true, "Sending…");
        setStatus("");
        try {
            await api.createTransferRequest(resource.id, (resource.listing_mode || "sell").toLowerCase());
            const refreshed = await loadLibrary();
            const message = resource.listing_mode === "sell"
                ? "Purchase request submitted as pending. Arrange any payment directly; CampusShare does not process it."
                : "Donation request submitted as pending.";
            setStatus(message, "success");
            setBorrowStatus(message, "success");
        } catch (error) {
            const err = errorMessage(error);
            setStatus(err, "error");
            setBorrowStatus(err, "error");
        } finally {
            if (button.isConnected) setButtonBusy(button, false);
        }
    }



    function clearLibrary() {
        categories = [];
        categoryLoadState = "idle";
        resources = [];
        resourceTypeFilter.replaceChildren(new Option("Any resource type", "all"));
        resourceTypeFilter.value = "all";
        listingModeFilter.value = "all";
        borrowingRequests = [];
        transferRequests = [];
        listingReports = [];
        marketplaceDataLoaded = false;
        resourcesLoaded = false;
        requestsLoaded = false;
        renderCategories();
        renderResources();
        resourceGrid.setAttribute("aria-busy", "false");
        renderBorrowRequests();
        renderMarketplaceData();
        renderDashboard();
        noResults.hidden = true;
    }

    async function loadLibrary() {
        const generation = ++requestGeneration;
        if (!currentSession || !currentSession.access_token) return;
        setStatus("Loading resources and categories…");
        setBorrowStatus("Loading borrowing requests…");
        resourceCount.textContent = "Loading resources…";
        resourceGrid.setAttribute("aria-busy", "true");
        categoryLoadState = "loading";
        renderCategories();
        resourcesLoaded = false;
        requestsLoaded = false;
        statGrid.setAttribute("aria-busy", "true");
        renderDashboard();
        try {
            const results = await Promise.allSettled([
                api.getCategories(),
                api.getResources(),
                api.health().catch(function (error) { return { healthError: error }; })
            ]);
            if (generation !== requestGeneration) return;

            const categoriesResult = results[0];
            if (categoriesResult.status === "fulfilled" && Array.isArray(categoriesResult.value)) {
                categories = categoriesResult.value;
                categoryLoadState = "loaded";
            } else {
                categories = [];
                categoryLoadState = "error";
            }

            const resourcesResult = results[1];
            resourcesLoaded = resourcesResult.status === "fulfilled" && Array.isArray(resourcesResult.value);
            resources = resourcesLoaded ? resourcesResult.value : [];
            renderResourceTypeFilter();

            const healthResult = results[2];
            const health = healthResult.status === "fulfilled" ? healthResult.value : null;
            const features = health && health.features;
            borrowRequestRpcEnabled = Boolean(
                features && features.borrow_request_rpc_enabled === true
            );
            borrowStatusRpcEnabled = Boolean(
                features && features.borrow_status_rpc_enabled === true
            );
            marketplaceEnabled = Boolean(features && features.marketplace_enabled === true);
            updateMarketplaceFilterVisibility();
            sellMarketplaceNote.hidden = marketplaceEnabled;
            donateMarketplaceNote.hidden = marketplaceEnabled;
            resourceImagesEnabled = Boolean(features && features.resource_images_enabled === true);
            marketplaceFields.hidden = !marketplaceEnabled;
            imageUploadAvailabilityNote.hidden = resourceImagesEnabled;
            imageUploadAvailabilityNote.textContent = resourceImagesEnabled
                ? ""
                : "You can select, preview, remove, and choose a primary photo here. Saving or managing saved photos is unavailable until SUPABASE_RESOURCE_IMAGES_ENABLED is enabled after staging setup.";
            marketplaceTransferSection.hidden = !marketplaceEnabled;
            borrowCreationNote.hidden = borrowRequestRpcEnabled;
            renderCategories();
            renderResources();
            resourceGrid.setAttribute("aria-busy", "false");
            renderDashboard();

            const loadErrors = [];
            if (categoryLoadState === "error") {
                const reason = categoriesResult.status === "rejected"
                    ? errorMessage(categoriesResult.reason)
                    : "The categories endpoint returned an invalid response.";
                loadErrors.push("Categories could not be loaded. " + reason);
            }
            if (!resourcesLoaded) {
                const reason = resourcesResult.status === "rejected"
                    ? errorMessage(resourcesResult.reason)
                    : "The resources endpoint returned an invalid response.";
                resourceCount.textContent = "Resources could not be loaded.";
                loadErrors.push("Resources could not be loaded. " + reason);
            }
            if (health && health.healthError) {
                loadErrors.push(errorMessage(health.healthError));
            }
            setStatus(loadErrors.join(" "), loadErrors.length ? "error" : "");
            const requestsLoaded = await loadBorrowRequests(generation);
            const marketplaceLoaded = await loadMarketplaceData(generation);
            return resourcesLoaded && requestsLoaded && marketplaceLoaded;
        } catch (error) {
            if (generation !== requestGeneration) return false;
            borrowRequestRpcEnabled = false;
            borrowStatusRpcEnabled = false;
            marketplaceEnabled = false;
            resourceImagesEnabled = false;
            updateMarketplaceFilterVisibility();
            marketplaceFields.hidden = true;
            marketplaceTransferSection.hidden = true;
            borrowCreationNote.hidden = false;
            if (resourcesLoaded) clearLibrary();
            categories = [];
            categoryLoadState = "error";
            renderCategories();
            if (!resourcesLoaded) resourceCount.textContent = "Resources could not be loaded.";
            resourceGrid.setAttribute("aria-busy", "false");
            setStatus(errorMessage(error), "error");
            statGrid.setAttribute("aria-busy", "false");
            return false;
        }
    }

    function applySession(session, sessionIsResolved) {
        sessionResolved = sessionIsResolved !== false || sessionResolved;
        const wasSignedIn = Boolean(currentSession && currentSession.access_token);
        const previousUserId = currentSession && currentSession.user ? String(currentSession.user.id) : "";
        currentSession = session && session.access_token && session.user ? session : null;
        const signedIn = Boolean(currentSession);
        renderStudentProfile();
        const nextUserId = signedIn ? String(currentSession.user.id) : "";
        authButton.textContent = signedIn ? "Log out" : "Log in";
        authButton.setAttribute("aria-label", signedIn ? "Log out of CampusShare" : "Log in to CampusShare");
        authConfigNote.hidden = auth.isConfigured;
        showAddForm.hidden = !canAddFromCurrentRoute();
        borrowRequestsSection.hidden = !signedIn;
        dashboard.hidden = !signedIn;
        dashboardNav.hidden = !signedIn;
        myResourcesNav.hidden = !signedIn;
        requestsNav.hidden = !signedIn;

        if (signedIn && previousUserId && previousUserId !== nextUserId) {
            myResourcesOnly = false;
            clearLibrary();
        }

        if (!signedIn) {
            requestGeneration++;
            myResourcesOnly = false;
            borrowRequestRpcEnabled = false;
            borrowStatusRpcEnabled = false;
            marketplaceEnabled = false;
            resourceImagesEnabled = false;
            updateMarketplaceFilterVisibility();
            imageUploadAvailabilityNote.hidden = false;
            imageUploadAvailabilityNote.textContent = "Image features are unavailable because backend feature status could not be loaded.";
            transferRequests = [];
            listingReports = [];
            borrowCreationNote.hidden = true;
            clearLibrary();
            resourceCount.textContent = "Log in to view campus resources.";
            setBorrowStatus("");
            if (wasSignedIn) setStatus("You are logged out.", "success");
            else setStatus("");
            renderRoute();
            return;
        }
        renderRoute();
        loadLibrary();
    }

    function openResourceForm(resource) {
        if (!currentSession) return;
        const formGeneration = ++resourceFormGeneration;
        existingImageCount = 0;
        existingPrimaryImage = false;
        resourceFormImageLoad = Promise.resolve(true);
        resourceForm.reset();
        selectedImageFiles = [];
        imagePreviewList.replaceChildren();
        existingImageList.replaceChildren();
        setResourceFormStatus("");
        if (resource) {
            resourceForm.dataset.resourceId = String(resource.id);
            resourceFormHeading.textContent = "Edit Resource";
            resourceSaveButton.textContent = "Save Changes";
            document.getElementById("resourceTitle").value = resource.title || "";
            document.getElementById("resourceDescription").value = resource.description || "";
            document.getElementById("resourceCategory").value = String(resource.category_id || "");
            document.getElementById("resourceType").value = resource.resource_type || "";
            document.getElementById("resourceAvailability").value = resource.availability_status || "available";
            if (resourceImagesEnabled) {
                resourceFormImageLoad = renderExistingImages(resource, formGeneration);
            }
            if (marketplaceEnabled) {
                document.getElementById("listingMode").value = resource.listing_mode || "borrow";
                document.getElementById("borrowPriceKind").value = resource.borrow_price_kind || "free";
                document.getElementById("borrowPriceAmount").value = resource.borrow_price_amount || "";
                document.getElementById("saleOriginalPrice").value = resource.sale_original_price || "";
                document.getElementById("salePrice").value = resource.sale_price || "";
                document.getElementById("itemCondition").value = resource.item_condition || "new";
                document.getElementById("purchaseYear").value = resource.purchase_year || "";
                api.handoverDetails(resource.id).then(function (details) {
                    if (!details || resourceForm.hidden || resourceForm.dataset.resourceId !== String(resource.id)) return;
                    document.getElementById("pickupLocation").value = details.pickup_location || "";
                    document.getElementById("meetingPoint").value = details.meeting_point || "";
                    document.getElementById("preferredPickupTime").value = details.preferred_pickup_time || "";
                    let instructions = details.instructions || "";
                    let phone = "";
                    const phoneMatch = instructions.match(/^Phone:\s*([^\n\r]+)/i);
                    if (phoneMatch) {
                        phone = phoneMatch[1].trim();
                        instructions = instructions.replace(/^Phone:\s*[^\n\r]+(\r?\nNotes:\s*|\r?\n)?/i, "").trim();
                    }
                    const phoneInput = document.getElementById("contactPhone");
                    if (phoneInput) phoneInput.value = phone;
                    document.getElementById("handoverInstructions").value = instructions;
                }).catch(function () {});
            }
        } else {
            delete resourceForm.dataset.resourceId;
            resourceFormHeading.textContent = "Add a Resource";
            resourceSaveButton.textContent = "Add Resource";
            document.getElementById("resourceAvailability").value = "available";
            document.getElementById("listingMode").value = "borrow";
            document.getElementById("borrowPriceKind").value = "free";
            document.getElementById("borrowPriceAmount").value = "";
            document.getElementById("saleOriginalPrice").value = "";
            document.getElementById("salePrice").value = "";
            document.getElementById("itemCondition").value = "new";
            document.getElementById("purchaseYear").value = "";
            const phoneInput = document.getElementById("contactPhone");
            if (phoneInput) phoneInput.value = "";
            document.getElementById("pickupLocation").value = "";
            document.getElementById("meetingPoint").value = "";
            document.getElementById("preferredPickupTime").value = "";
            document.getElementById("handoverInstructions").value = "";
            if (currentRoute === "sell" || currentRoute === "donate") {
                document.getElementById("listingMode").value = currentRoute;
            }
        }
        marketplaceFields.hidden = !marketplaceEnabled;
        updateMarketplaceFilterVisibility();
        updateMarketplaceFormVisibility();
        resourceForm.hidden = false;
        updateCategoryFormState();
        resourceForm.scrollIntoView({ behavior: "smooth", block: "center" });
    }

    function updateMarketplaceFormVisibility() {
        const mode = document.getElementById("listingMode").value;
        const priceKind = document.getElementById("borrowPriceKind").value;
        document.getElementById("borrowPriceFields").hidden = mode !== "borrow";
        document.getElementById("borrowPriceAmount").required = mode === "borrow" && priceKind !== "free";
        document.getElementById("borrowPriceAmount").disabled = mode !== "borrow" || priceKind === "free";
        document.getElementById("saleFields").hidden = mode !== "sell";
        ["saleOriginalPrice", "salePrice", "itemCondition"].forEach(function (id) {
            document.getElementById(id).required = mode === "sell";
            document.getElementById(id).disabled = mode !== "sell";
        });
        document.getElementById("purchaseYear").disabled = !marketplaceEnabled || mode !== "sell";
        document.getElementById("purchaseYear").required = mode === "sell";
        document.getElementById("purchaseYear").max = String(new Date().getFullYear());
    }

    async function submitResourceForm(event) {
        event.preventDefault();
        if (resourceFormBusy || !currentSession) return;
        if (!resourceForm.reportValidity()) {
            setResourceFormStatus("Complete each required field before submitting.", "error");
            return;
        }
        const resourceId = resourceForm.dataset.resourceId;
        const payload = {
            title: document.getElementById("resourceTitle").value.trim(),
            description: document.getElementById("resourceDescription").value.trim(),
            category_id: document.getElementById("resourceCategory").value,
            resource_type: document.getElementById("resourceType").value.trim(),
            availability_status: document.getElementById("resourceAvailability").value
        };
        if (marketplaceEnabled) {
            const mode = document.getElementById("listingMode").value;
            const priceKind = document.getElementById("borrowPriceKind").value;
            payload.listing_mode = mode;
            payload.borrow_price_kind = mode === "borrow" ? priceKind : "free";
            if (mode === "borrow" && priceKind !== "free") payload.borrow_price_amount = Number(document.getElementById("borrowPriceAmount").value);
            else payload.borrow_price_amount = null;
            if (mode === "sell") {
                payload.sale_original_price = Number(document.getElementById("saleOriginalPrice").value);
                payload.sale_price = Number(document.getElementById("salePrice").value);
                payload.item_condition = document.getElementById("itemCondition").value;
                payload.purchase_year = Number(document.getElementById("purchaseYear").value);
            } else {
                payload.sale_original_price = null;
                payload.sale_price = null;
                payload.item_condition = null;
            }
            if (mode !== "sell") payload.purchase_year = null;
        }
        const validCategory = categories.some(function (category) {
            return category && String(category.id) === String(payload.category_id).trim();
        });
        if (!validCategory) {
            setResourceFormStatus(categoryAvailabilityMessage() || "Choose a category from the available list.", "error");
            return;
        }
        const validationMessage = ui.validateResourcePayload(payload);
        if (validationMessage) {
            setResourceFormStatus(validationMessage, "error");
            return;
        }
        if (selectedImageFiles.length && !resourceImagesEnabled) {
            setResourceFormStatus("Your photos are selected, but image uploads are not enabled by the backend yet. They were not uploaded; remove them or try again after the staging image integration is enabled.", "error");
            return;
        }
        const fileError = validateSelectedImages([]);
        if (fileError) { setResourceFormStatus(fileError, "error"); return; }
        if (resourceImagesEnabled && !(await resourceFormImageLoad)) {
            setResourceFormStatus("Saved photos could not be loaded. Refresh the listing before changing its images.", "error");
            return;
        }
        if (marketplaceEnabled) {
            if (payload.listing_mode === "borrow" && payload.borrow_price_kind !== "free" &&
                (!Number.isFinite(payload.borrow_price_amount) || payload.borrow_price_amount <= 0)) {
                setResourceFormStatus("Enter a positive borrow charge or choose Free.", "error");
                return;
            }
            if (payload.listing_mode === "sell" && payload.sale_price > payload.sale_original_price) {
                setResourceFormStatus("The selling price cannot exceed the original purchase price.", "error");
                return;
            }
            const purchaseYear = payload.purchase_year;
            if (payload.listing_mode === "sell" && (!Number.isInteger(purchaseYear) || purchaseYear < 1900 || purchaseYear > new Date().getFullYear())) {
                setResourceFormStatus("Enter a valid purchase year that is not in the future.", "error");
                return;
            }
            const contactPhone = document.getElementById("contactPhone") ? document.getElementById("contactPhone").value.trim() : "";
            if (!contactPhone) {
                setResourceFormStatus("Enter your contact phone number so approved requesters can coordinate handover.", "error");
                return;
            }
            if (!document.getElementById("pickupLocation").value.trim() || !document.getElementById("meetingPoint").value.trim()) {
                setResourceFormStatus("Enter both a campus pickup location and a separate meeting point.", "error");
                return;
            }
        }
        resourceFormBusy = true;
        setFormBusy(resourceForm, true, resourceId ? "Saving…" : "Adding…");
        setResourceFormStatus("");
        setStatus("");
        try {
            let savedId = resourceId;
            if (resourceId) {
                const original = resources.find(function (item) { return String(item.id) === String(resourceId); });
                const changes = { ...payload };
                if (original && marketplaceEnabled) {
                    ["listing_mode", "borrow_price_kind", "borrow_price_amount", "sale_original_price", "sale_price", "item_condition", "purchase_year"].forEach(function (field) {
                        if (String(original[field] ?? "") === String(changes[field] ?? "")) delete changes[field];
                    });
                }
                await api.updateResource(resourceId, changes);
            } else {
                const created = await api.createResource(payload);
                const row = Array.isArray(created) ? created[0] : created;
                if (!row || !row.id) throw new Error("The resource was created but the API did not return its ID.");
                savedId = row.id;
                resourceForm.dataset.resourceId = String(savedId);
                resourceFormHeading.textContent = "Edit Resource";
                resourceSaveButton.textContent = "Save Changes";
            }
            if (resourceImagesEnabled && savedId) {
                await uploadSelectedImages(savedId);
            }
            if (marketplaceEnabled && savedId) {
                await saveHandover(savedId);
            }
            resourceForm.reset();
            selectedImageFiles = [];
            existingImageCount = 0;
            existingPrimaryImage = false;
            resourceFormImageLoad = Promise.resolve(true);
            renderSelectedImages();
            delete resourceForm.dataset.resourceId;
            resourceForm.hidden = true;
            const refreshed = await loadLibrary();
            setStatus(
                refreshed
                    ? (resourceId ? "Resource updated." : "Resource added.")
                    : "Resource saved, but some updated data could not be refreshed.",
                refreshed ? "success" : "error"
            );
        } catch (error) {
            setResourceFormStatus(errorMessage(error), "error");
            setStatus(errorMessage(error), "error");
        } finally {
            resourceFormBusy = false;
            setFormBusy(resourceForm, false);
            resourceSaveButton.textContent = resourceForm.dataset.resourceId ? "Save Changes" : "Add Resource";
        }
    }

    async function deleteResource(resource, button) {
        if (!currentSession || !currentSession.user) return;
        if (String(resource.owner_id) !== String(currentSession.user.id)) {
            setStatus("Only the owner can delete this resource.", "error");
            return;
        }
        if (!window.confirm(`Delete “${resource.title}”? This cannot be undone.`)) return;
        if (button) setButtonBusy(button, true, "Deleting…");
        setStatus("Deleting resource…");
        try {
            if (resourceImagesEnabled) {
                try {
                    const imageRows = await api.resourceImages(resource.id);
                    if (imageRows.length) {
                        for (const row of imageRows) await api.deleteResourceImage(row.id);
                    }
                } catch (_) {}
            }
            await api.deleteResource(resource.id);
            // Immediately remove resource locally so UI updates instantly
            resources = resources.filter(function (r) { return String(r.id) !== String(resource.id); });
            renderResources();
            renderDashboard();

            const refreshed = await loadLibrary();
            setStatus(
                refreshed ? "Resource deleted." : "Resource deleted, but some updated data could not be refreshed.",
                refreshed ? "success" : "error"
            );
        } catch (error) {
            setStatus(errorMessage(error), "error");
        } finally {
            if (button && button.isConnected) setButtonBusy(button, false);
        }
    }

    async function submitBorrowRequest(resource, button) {
        if (!currentSession || !currentSession.user) return;
        if (String(resource.owner_id) === String(currentSession.user.id)) {
            setStatus("You cannot request your own resource.", "error");
            return;
        }
        if (resource.availability_status !== "available") {
            setStatus("This resource is not currently available to borrow.", "error");
            return;
        }
        if (hasActiveOwnRequest(resource.id)) {
            setStatus("You already have a pending or approved request for this resource.", "error");
            return;
        }
        const resourceId = String(resource.id);
        if (borrowBusy.has(resourceId)) return;
        borrowBusy.add(resourceId);
        setButtonBusy(button, true, "Sending…");
        setStatus("");
        try {
            const dueInput = document.getElementById("borrowDueDate");
            const dueAt = marketplaceEnabled && dueInput && dueInput.value
                ? `${dueInput.value}T23:59:59Z`
                : null;
            await api.createBorrowRequest({ resource_id: resourceId, due_at: dueAt });
            const refreshed = await loadLibrary();
            setStatus(
                refreshed
                    ? "Borrowing request submitted with pending status."
                    : "Request submitted, but some updated data could not be refreshed.",
                refreshed ? "success" : "error"
            );
        } catch (error) {
            setStatus(errorMessage(error), "error");
        } finally {
            borrowBusy.delete(resourceId);
            button.disabled = false;
            button.textContent = "Request to borrow";
        }
    }

    function showMyResources() {
        if (!currentSession) return;
        searchInput.value = "";
        categoryFilter.value = "all";
        resourceTypeFilter.value = "all";
        listingModeFilter.value = "all";
        availabilityFilter.value = "all";
        priceMinFilter.value = "";
        priceMaxFilter.value = "";
        conditionFilter.value = "all";
        sortSelect.value = "newest";
        navigateTo("my-resources");
    }

    function showBrowseResources() {
        navigateTo("browse");
    }

    function clearResourceFilters() {
        searchInput.value = "";
        if (searchClearBtn) searchClearBtn.hidden = true;
        categoryFilter.value = "all";
        resourceTypeFilter.value = "all";
        listingModeFilter.value = "all";
        availabilityFilter.value = "all";
        priceMinFilter.value = "";
        priceMaxFilter.value = "";
        conditionFilter.value = "all";
        sortSelect.value = "newest";
        myResourcesOnly = currentRoute === "my-resources";
        resetDrawerFilters();
        renderResources();
    }

    auth.onAuthStateChange(function (_event, session) {
        // Supabase recommends keeping this callback synchronous.
        window.setTimeout(function () { applySession(session, true); }, 0);
    });

    window.addEventListener("hashchange", renderRoute);
    window.addEventListener("popstate", renderRoute);

    auth.getSession().then(function (result) {
        if (result.error) {
            applySession(null, true);
            setStatus(errorMessage(result.error), "error");
            return;
        }
        applySession(result.data && result.data.session, true);
    }).catch(function (error) {
        applySession(null, true);
        setStatus(errorMessage(error), "error");
    });

    authButton.addEventListener("click", async function () {
        if (!currentSession) {
            setAuthMessage("");
            authDialog.showModal();
            return;
        }
        authButton.disabled = true;
        authButton.textContent = "Logging out…";
        try {
            const result = await auth.signOut();
            if (result.error) throw result.error;
            applySession(null);
        } catch (error) {
            authButton.textContent = "Log out";
            setStatus(errorMessage(error), "error");
        } finally {
            authButton.disabled = false;
        }
    });

    document.getElementById("closeAuthDialog").addEventListener("click", function () { authDialog.close(); });
    document.getElementById("showLogin").addEventListener("click", function () { setAuthMode("login"); });
    document.getElementById("showRegister").addEventListener("click", function () { setAuthMode("register"); });
    authDialog.addEventListener("click", function (event) { if (event.target === authDialog) authDialog.close(); });

    async function submitAuth(event, mode) {
        event.preventDefault();
        if (authFormBusy) return;
        if (!auth.isConfigured) {
            setAuthMessage("Set the Supabase project URL and publishable key in FRONTEND/config.js.", "error");
            return;
        }
        const form = event.currentTarget;
        authFormBusy = true;
        setFormBusy(form, true, mode === "register" ? "Creating account…" : "Logging in…");
        setAuthMessage("");
        try {
            const email = form.elements.email.value.trim();
            const password = form.elements.password.value;
            const fullName = mode === "register" ? form.elements.full_name.value.trim() : "";
            if (mode === "register" && !fullName) {
                throw new Error("Enter your full name to create your profile.");
            }
            let result;
            if (mode === "register") {
                result = await auth.signUp(email, password, fullName);
                if (result && result.error) {
                    const errStatus = Number(result.error.status);
                    const errCode = result.error.code || "";
                    const errMsg = result.error.message || "";
                    const isRateLimitOrExisting = errStatus === 429 ||
                        errCode === "over_email_send_rate_limit" ||
                        errCode === "user_already_exists" ||
                        /email rate limit exceeded|already registered|user already exists/i.test(errMsg);

                    if (isRateLimitOrExisting && typeof auth.signIn === "function") {
                        const fallbackLogin = await auth.signIn(email, password);
                        if (fallbackLogin && !fallbackLogin.error && fallbackLogin.data && fallbackLogin.data.session) {
                            result = fallbackLogin;
                            mode = "login";
                        }
                    }
                }
            } else {
                result = await auth.signIn(email, password);
            }
            if (result.error) throw result.error;

            if (mode === "register" && result.data && result.data.user && !result.data.session) {
                setAuthMessage("Account created. Check your email to confirm it, then log in.", "success");
                form.reset();
            } else if (mode === "register" && result.data && result.data.session) {
                setAuthMessage("Your account is ready.", "success");
                form.reset();
                authDialog.close();
            } else if (mode === "register") {
                setAuthMessage("If your account was created, check your email for confirmation or next steps.", "success");
                form.reset();
            } else {
                if (!result.data || !result.data.session) throw new Error("Login did not return an active session. Please try again.");
                setAuthMessage("You are logged in.", "success");
                form.reset();
                authDialog.close();
            }
        } catch (error) {
            setAuthMessage(mode === "register" ? registrationErrorMessage(error) : errorMessage(error), "error");
        } finally {
            authFormBusy = false;
            setFormBusy(form, false);
        }
    }

    loginForm.addEventListener("submit", function (event) { submitAuth(event, "login"); });
    registerForm.addEventListener("submit", function (event) { submitAuth(event, "register"); });
    resourceForm.addEventListener("submit", submitResourceForm);
    showAddForm.addEventListener("click", function () { openResourceForm(null); });
    document.getElementById("cancelAddForm").addEventListener("click", function () {
        resourceFormGeneration++;
        existingImageCount = 0;
        existingPrimaryImage = false;
        resourceFormImageLoad = Promise.resolve(true);
        resourceForm.reset();
        delete resourceForm.dataset.resourceId;
        selectedImageFiles = [];
        renderSelectedImages();
        existingImageList.replaceChildren();
        resourceForm.hidden = true;
        setResourceFormStatus("");
    });
    document.getElementById("listingMode").addEventListener("change", updateMarketplaceFormVisibility);
    document.getElementById("borrowPriceKind").addEventListener("change", updateMarketplaceFormVisibility);
    resourceImagesInput.addEventListener("change", function (event) {
        const files = Array.from(event.target.files || []);
        const validation = validateSelectedImages(files);
        if (validation) setResourceFormStatus(validation, "error");
        else {
            selectedImageFiles.push(...files);
            setResourceFormStatus("");
            renderSelectedImages();
        }
        resourceImagesInput.value = "";
    });
    document.getElementById("cancelListingReport").addEventListener("click", function () {
        listingReportDialog.close();
        reportResourceId = null;
    });
    listingReportForm.addEventListener("submit", async function (event) {
        event.preventDefault();
        if (!marketplaceEnabled || !reportResourceId || !currentSession) return;
        const submit = listingReportForm.querySelector("button[type='submit']");
        setButtonBusy(submit, true, "Submitting…");
        listingReportStatus.textContent = "";
        try {
            await api.reportListing(reportResourceId, {
                reason: document.getElementById("listingReportReason").value,
                details: document.getElementById("listingReportDetails").value.trim()
            });
            await loadMarketplaceData(requestGeneration);
            listingReportStatus.textContent = "Report submitted for human review. A report alone does not suspend an account.";
            listingReportDialog.close();
            setBorrowStatus("Listing report submitted.", "success");
        } catch (error) {
            listingReportStatus.textContent = errorMessage(error);
        } finally { setButtonBusy(submit, false); }
    });
    document.getElementById("refreshLibrary").addEventListener("click", loadLibrary);
    document.getElementById("clearFilters").addEventListener("click", clearResourceFilters);
    document.getElementById("emptyAddResource").addEventListener("click", function () {
        openResourceForm(null);
    });
    document.getElementById("dashboardMyResources").addEventListener("click", showMyResources);
    document.getElementById("quickBrowse").addEventListener("click", function () {
        showBrowseResources();
    });
    document.getElementById("quickMyRequests").addEventListener("click", function () {
        navigateTo("borrowing");
    });
    document.getElementById("quickReceivedRequests").addEventListener("click", function () {
        navigateTo("borrowing");
    });
    document.getElementById("quickSell").addEventListener("click", function () { navigateTo("sell"); });
    document.getElementById("quickDonate").addEventListener("click", function () { navigateTo("donate"); });
    document.getElementById("dashboardViewAllResources").addEventListener("click", showBrowseResources);
    document.getElementById("dashboardViewBorrowing").addEventListener("click", function () {
        navigateTo("borrowing");
    });
    document.getElementById("dashboardAddResource").addEventListener("click", function () {
        navigateTo("browse");
        openResourceForm(null);
    });
    mobileNavToggle.addEventListener("click", function () {
        setSidebarOpen(mobileNavToggle.getAttribute("aria-expanded") !== "true");
    });
    sidebarBackdrop.addEventListener("click", function () { setSidebarOpen(false); });
    document.addEventListener("keydown", function (event) {
        if (event.key === "Escape") {
            setSidebarOpen(false);
            closeFilterDrawer();
        }
    });
    document.getElementById("closeResourceDetails").addEventListener("click", function () { resourceDetailsDialog.close(); });
    resourceDetailsDialog.addEventListener("click", function (event) {
        if (event.target === resourceDetailsDialog) resourceDetailsDialog.close();
    });
    if (myBorrowTab) myBorrowTab.addEventListener("click", function () { setMyResourcesSubTab("borrow"); });
    if (mySellTab) mySellTab.addEventListener("click", function () { setMyResourcesSubTab("sell"); });
    if (myDonateTab) myDonateTab.addEventListener("click", function () { setMyResourcesSubTab("donate"); });

    searchInput.addEventListener("input", function () {
        if (searchClearBtn) searchClearBtn.hidden = !searchInput.value.trim();
        renderResources();
    });
    if (searchClearBtn) {
        searchClearBtn.addEventListener("click", function () {
            searchInput.value = "";
            searchClearBtn.hidden = true;
            renderResources();
            if (typeof searchInput.focus === "function") searchInput.focus();
        });
    }

    categoryFilter.addEventListener("change", renderResources);
    resourceTypeFilter.addEventListener("change", renderResources);
    listingModeFilter.addEventListener("change", renderResources);
    availabilityFilter.addEventListener("change", renderResources);
    priceMinFilter.addEventListener("input", renderResources);
    priceMaxFilter.addEventListener("input", renderResources);
    conditionFilter.addEventListener("change", renderResources);
    sortSelect.addEventListener("change", function () {
        stagingSort = sortSelect.value;
        syncDrawerSortPills();
        renderResources();
    });

    if (openFilterBtn) openFilterBtn.addEventListener("click", openFilterDrawer);
    if (closeFilterBtn) closeFilterBtn.addEventListener("click", closeFilterDrawer);
    if (filterDrawerBackdrop) filterDrawerBackdrop.addEventListener("click", closeFilterDrawer);
    if (drawerApplyBtn) drawerApplyBtn.addEventListener("click", applyDrawerFilters);
    if (drawerResetBtn) drawerResetBtn.addEventListener("click", resetDrawerFilters);

    if (drawerConditionList) {
        drawerConditionList.addEventListener("click", function (event) {
            const btn = event.target.closest("button.filter-pill");
            if (!btn) return;
            stagingCondition = btn.dataset.condition || "all";
            syncDrawerConditionPills();
        });
    }

    if (drawerSortList) {
        drawerSortList.addEventListener("click", function (event) {
            const btn = event.target.closest("button.filter-pill");
            if (!btn) return;
            stagingSort = btn.dataset.sort || "newest";
            syncDrawerSortPills();
        });
    }

    if (drawerAvailabilityList) {
        drawerAvailabilityList.addEventListener("click", function (event) {
            const btn = event.target.closest("button.filter-pill");
            if (!btn) return;
            stagingAvailability = btn.dataset.avail || "all";
            syncDrawerAvailabilityPills();
        });
    }

    if (drawerQuickPrices) {
        drawerQuickPrices.addEventListener("click", function (event) {
            const btn = event.target.closest("button.filter-pill");
            if (!btn) return;
            stagingMinPrice = btn.dataset.min ?? "";
            stagingMaxPrice = btn.dataset.max ?? "";
            if (drawerPriceMin) drawerPriceMin.value = stagingMinPrice;
            if (drawerPriceMax) drawerPriceMax.value = stagingMaxPrice;
            updateQuickPricePills();
            syncDrawerPriceSlider();
        });
    }

    if (drawerPriceMin) {
        drawerPriceMin.addEventListener("input", function () {
            stagingMinPrice = drawerPriceMin.value.trim();
            updateQuickPricePills();
            syncDrawerPriceSlider();
        });
    }
    if (drawerPriceMax) {
        drawerPriceMax.addEventListener("input", function () {
            stagingMaxPrice = drawerPriceMax.value.trim();
            updateQuickPricePills();
            syncDrawerPriceSlider();
        });
    }

    if (priceSliderMin && priceSliderMax) {
        priceSliderMin.addEventListener("input", function () {
            let minVal = Number(priceSliderMin.value);
            const maxVal = Number(priceSliderMax.value);
            if (minVal > maxVal) {
                minVal = maxVal;
                priceSliderMin.value = String(minVal);
            }
            stagingMinPrice = minVal > 0 ? String(minVal) : "";
            if (drawerPriceMin) drawerPriceMin.value = stagingMinPrice;
            updateQuickPricePills();
            updateSliderTrackHighlight();
        });
        priceSliderMax.addEventListener("input", function () {
            const minVal = Number(priceSliderMin.value);
            let maxVal = Number(priceSliderMax.value);
            if (maxVal < minVal) {
                maxVal = minVal;
                priceSliderMax.value = String(maxVal);
            }
            const limit = Number(priceSliderMax.max) || 10000;
            stagingMaxPrice = maxVal < limit ? String(maxVal) : "";
            if (drawerPriceMax) drawerPriceMax.value = stagingMaxPrice;
            updateQuickPricePills();
            updateSliderTrackHighlight();
        });
    }

    setAuthMode("login");
    applySession(null, false);
})();
