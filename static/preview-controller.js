(() => {
    let activeAnchor = null;
    let hideTimer = null;
    let keyboardInput = false;
    const coarsePointer = () => window.matchMedia?.("(hover: none), (pointer: coarse)").matches === true;
    const target = () => document.getElementById("link-preview");

    const cancelHide = () => {
        if (hideTimer === null) return;
        window.clearTimeout(hideTimer);
        hideTimer = null;
    };

    const hide = () => {
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
        hideTimer = window.setTimeout(() => {
            const box = target();
            if (box?.matches(":hover") || box?.contains(document.activeElement)) return;
            hide();
        }, 160);
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
        cancelHide();
        if (activeAnchor === anchor && !target()?.hidden) return;
        activeAnchor = anchor;
        target()?.setAttribute("aria-busy", "true");
        anchor.dispatchEvent(new Event("preview:request"));
    };

    document.addEventListener("pointerover", (event) => {
        const element = event.target instanceof Element ? event.target : null;
        const anchor = element?.closest("a[data-previewable]");
        if (!anchor || coarsePointer() || anchor.contains(event.relatedTarget)) return;
        request(anchor);
    });

    document.addEventListener("pointerout", (event) => {
        const element = event.target instanceof Element ? event.target : null;
        const anchor = element?.closest("a[data-previewable]");
        if (anchor && anchor === activeAnchor && !anchor.contains(event.relatedTarget)) scheduleHide();
    });

    document.addEventListener("focusin", (event) => {
        const element = event.target instanceof Element ? event.target : null;
        if (element?.id === "link-preview" || element?.closest("#link-preview")) {
            cancelHide();
            return;
        }
        const anchor = element?.closest("a[data-previewable]");
        if (anchor && (!coarsePointer() || keyboardInput)) request(anchor);
    });

    document.addEventListener("focusout", (event) => {
        if (event.target === activeAnchor && !target()?.contains(event.relatedTarget)) scheduleHide();
    });

    document.addEventListener("keydown", (event) => {
        keyboardInput = true;
        if (event.key === "Escape") hide();
    });
    document.addEventListener("pointerdown", (event) => {
        keyboardInput = false;
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
    window.addEventListener("scroll", hide, { passive: true });
    window.addEventListener("resize", hide);
    window.addEventListener("blur", hide);
})();
