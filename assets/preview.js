(() => {
    const showDelayMs = 300;
    const hideDelayMs = 500;
    const cache = new Map();
    let activeAnchor = null;
    let pendingAnchor = null;
    let activeRequest = null;
    let showTimer = null;
    let hideTimer = null;
    let keyboardInput = false;

    const coarsePointer = () => window.matchMedia?.("(hover: none), (pointer: coarse)").matches === true;
    const target = () => document.getElementById("link-preview");

    const cancelShow = () => {
        if (showTimer !== null) window.clearTimeout(showTimer);
        showTimer = null;
        pendingAnchor = null;
    };

    const cancelHide = () => {
        if (hideTimer !== null) window.clearTimeout(hideTimer);
        hideTimer = null;
    };

    const cancelRequest = () => {
        activeRequest?.abort();
        activeRequest = null;
    };

    const hide = () => {
        cancelShow();
        cancelHide();
        cancelRequest();
        activeAnchor = null;
        const box = target();
        if (!box) return;
        box.hidden = true;
        box.removeAttribute("aria-busy");
        box.style.left = "";
        box.style.top = "";
        box.style.width = "";
    };

    const scheduleHide = () => {
        cancelHide();
        if (!activeAnchor) return;
        hideTimer = window.setTimeout(() => {
            hideTimer = null;
            const box = target();
            if (activeAnchor?.matches(":hover") ||
                box?.matches(":hover") ||
                activeAnchor === document.activeElement ||
                box?.contains(document.activeElement)) return;
            hide();
        }, hideDelayMs);
    };

    const position = () => {
        const box = target();
        if (!box || !activeAnchor?.isConnected) return hide();
        const anchorRect = activeAnchor.getBoundingClientRect();
        const margin = 16;
        const preferredWidth = box.classList.contains("link-preview--pdf") ? 760
            : box.classList.contains("link-preview--article") ? 560
                : 420;
        box.style.width = `${Math.min(preferredWidth, window.innerWidth - margin * 2)}px`;
        const boxRect = box.getBoundingClientRect();
        const left = Math.min(
            Math.max(margin, anchorRect.left),
            window.innerWidth - boxRect.width - margin,
        );
        const below = anchorRect.bottom + margin;
        const top = below + boxRect.height <= window.innerHeight - margin
            ? below
            : Math.max(margin, anchorRect.top - boxRect.height - margin);
        box.style.left = `${left}px`;
        box.style.top = `${top}px`;
    };

    const install = (html, anchor) => {
        if (anchor !== activeAnchor) return;
        const template = document.createElement("template");
        template.innerHTML = html.trim();
        const replacement = template.content.firstElementChild;
        if (!(replacement instanceof HTMLElement) || replacement.id !== "link-preview") {
            throw new Error("invalid preview fragment");
        }
        if (replacement.dataset.previewHref !== anchor.getAttribute("href")) {
            throw new Error("preview fragment does not match its link");
        }
        const box = target();
        if (!box) throw new Error("preview target is missing");
        box.replaceWith(replacement);
        replacement.classList.toggle("link-preview--interactive", Boolean(replacement.querySelector("a, button")));
        replacement.hidden = false;
        replacement.removeAttribute("aria-busy");
        position();
    };

    const request = async (anchor) => {
        cancelShow();
        cancelHide();
        if (activeAnchor === anchor && !target()?.hidden) return;
        cancelRequest();
        activeAnchor = anchor;

        const source = anchor.dataset.previewSrc;
        if (!source) return hide();
        const url = new URL(source, window.location.href);
        if (url.origin !== window.location.origin) return hide();

        const cached = cache.get(url.pathname);
        if (cached !== undefined) {
            try {
                install(cached, anchor);
            } catch (error) {
                console.error(error);
                hide();
            }
            return;
        }

        const controller = new AbortController();
        activeRequest = controller;
        const loadingTarget = target();
        if (loadingTarget) {
            loadingTarget.hidden = true;
            loadingTarget.setAttribute("aria-busy", "true");
        }
        try {
            const response = await fetch(url.pathname, {
                credentials: "same-origin",
                headers: { Accept: "text/html" },
                signal: controller.signal,
            });
            if (!response.ok) throw new Error(`preview request failed: ${response.status}`);
            const html = await response.text();
            cache.set(url.pathname, html);
            if (!controller.signal.aborted) install(html, anchor);
        } catch (error) {
            if (error?.name !== "AbortError" && anchor === activeAnchor) {
                console.error(error);
                hide();
            }
        } finally {
            if (activeRequest === controller) {
                activeRequest = null;
                target()?.removeAttribute("aria-busy");
            }
        }
    };

    const scheduleShow = (anchor) => {
        cancelShow();
        pendingAnchor = anchor;
        showTimer = window.setTimeout(() => {
            showTimer = null;
            const candidate = pendingAnchor;
            pendingAnchor = null;
            if (candidate !== anchor || !anchor.isConnected || coarsePointer() || !anchor.matches(":hover")) return;
            void request(anchor);
        }, showDelayMs);
    };

    document.addEventListener("pointerover", (event) => {
        const element = event.target instanceof Element ? event.target : null;
        if (element?.id === "link-preview" || element?.closest("#link-preview")) {
            cancelHide();
            return;
        }
        const anchor = element?.closest("a[data-previewable][data-preview-src]");
        if (!anchor || coarsePointer() || anchor.contains(event.relatedTarget)) return;
        if (anchor === activeAnchor) {
            cancelHide();
            return;
        }
        scheduleShow(anchor);
    });

    document.addEventListener("pointerout", (event) => {
        const element = event.target instanceof Element ? event.target : null;
        const related = event.relatedTarget instanceof Node ? event.relatedTarget : null;
        const box = element?.id === "link-preview" ? element : element?.closest("#link-preview");
        if (box) {
            if (related && (box.contains(related) || activeAnchor?.contains(related))) return;
            scheduleHide();
            return;
        }
        const anchor = element?.closest("a[data-previewable][data-preview-src]");
        if (!anchor || (related && anchor.contains(related))) return;
        if (anchor === pendingAnchor) cancelShow();
        if (anchor !== activeAnchor) return;
        if (related && target()?.contains(related)) {
            cancelHide();
            return;
        }
        scheduleHide();
    });

    document.addEventListener("focusin", (event) => {
        const element = event.target instanceof Element ? event.target : null;
        if (element?.id === "link-preview" || element?.closest("#link-preview")) {
            cancelHide();
            return;
        }
        const anchor = element?.closest("a[data-previewable][data-preview-src]");
        if (anchor && keyboardInput) void request(anchor);
    });

    document.addEventListener("focusout", (event) => {
        const element = event.target instanceof Element ? event.target : null;
        const related = event.relatedTarget instanceof Node ? event.relatedTarget : null;
        if (element?.id === "link-preview" || element?.closest("#link-preview")) {
            if (related && (target()?.contains(related) || activeAnchor?.contains(related))) return;
            scheduleHide();
            return;
        }
        if (event.target === activeAnchor && !(related && target()?.contains(related))) scheduleHide();
    });

    document.addEventListener("keydown", (event) => {
        keyboardInput = true;
        if (event.key === "Escape") hide();
    });
    document.addEventListener("pointerdown", (event) => {
        keyboardInput = false;
        cancelShow();
        const element = event.target instanceof Element ? event.target : null;
        if (element?.closest(".link-preview__close")) {
            event.preventDefault();
            hide();
        } else if (!element?.closest("#link-preview") && !element?.closest("a[data-previewable]")) {
            hide();
        }
    });

    const viewportChanged = () => {
        if (activeAnchor === document.activeElement) {
            position();
            return;
        }
        hide();
    };
    window.addEventListener("scroll", viewportChanged, { passive: true });
    window.addEventListener("resize", viewportChanged);
    window.addEventListener("blur", hide);
})();
