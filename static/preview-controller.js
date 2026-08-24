(() => {
    const showDelayMs = 300;
    const hideDelayMs = 500;
    let activeAnchor = null;
    let pendingAnchor = null;
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
        if (hideTimer === null) return;
        window.clearTimeout(hideTimer);
        hideTimer = null;
    };

    const hide = () => {
        cancelShow();
        cancelHide();
        const previousAnchor = activeAnchor;
        activeAnchor = null;
        previousAnchor?.dispatchEvent(new Event("htmx:abort"));
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

    const request = (anchor) => {
        cancelShow();
        cancelHide();
        if (activeAnchor === anchor && !target()?.hidden) return;
        if (activeAnchor && activeAnchor !== anchor) {
            activeAnchor.dispatchEvent(new Event("htmx:abort"));
        }
        activeAnchor = anchor;
        target()?.setAttribute("aria-busy", "true");
        anchor.dispatchEvent(new Event("preview:request"));
    };

    const scheduleShow = (anchor) => {
        cancelShow();
        pendingAnchor = anchor;
        showTimer = window.setTimeout(() => {
            showTimer = null;
            const candidate = pendingAnchor;
            pendingAnchor = null;
            if (candidate !== anchor || !anchor.isConnected || coarsePointer() || !anchor.matches(":hover")) return;
            request(anchor);
        }, showDelayMs);
    };

    document.addEventListener("pointerover", (event) => {
        const element = event.target instanceof Element ? event.target : null;
        if (element?.id === "link-preview" || element?.closest("#link-preview")) {
            cancelHide();
            return;
        }
        const anchor = element?.closest("a[data-previewable]");
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
        const anchor = element?.closest("a[data-previewable]");
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
        const anchor = element?.closest("a[data-previewable]");
        if (anchor && keyboardInput) request(anchor);
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

    document.addEventListener("htmx:after:swap", () => {
        const box = target();
        if (!box || !activeAnchor || box.dataset.previewHref !== activeAnchor.getAttribute("href")) {
            if (box) box.hidden = true;
            return;
        }
        box.classList.toggle("link-preview--interactive", Boolean(box.querySelector("a, button")));
        box.hidden = false;
        box.removeAttribute("aria-busy");
        position();
    });
    document.addEventListener("htmx:response:error", (event) => {
        if (event.target === activeAnchor) hide();
    });
    document.addEventListener("htmx:error", (event) => {
        const error = event.detail?.error;
        if (error?.name === "AbortError" || /aborted/i.test(error?.message || "")) return;
        if (event.target === activeAnchor) hide();
    });
    document.addEventListener("htmx:finally:request", () => target()?.removeAttribute("aria-busy"));
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
