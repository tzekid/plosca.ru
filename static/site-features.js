(() => {
    const annotationsUrl = "/metadata/annotations.json";
    let annotationsPromise = null;
    let preview = null;
    let activeAnchor = null;

    const ready = (fn) => {
        if (document.readyState === "loading") {
            document.addEventListener("DOMContentLoaded", fn, { once: true });
        } else {
            fn();
        }
    };

    const fetchAnnotations = async () => {
        if (!annotationsPromise) {
            annotationsPromise = fetch(annotationsUrl, { credentials: "same-origin" })
                .then((response) => (response.ok ? response.json() : { annotations: [] }))
                .catch(() => ({ annotations: [] }));
        }
        return annotationsPromise;
    };

    const normalizeHref = (anchor) => {
        const raw = anchor.getAttribute("href") || "";
        try {
            const url = new URL(raw, window.location.href);
            if (url.origin === window.location.origin) {
                return `${url.pathname}${url.search}${url.hash}`;
            }
            return url.href;
        } catch {
            return raw;
        }
    };

    const annotationFor = async (anchor) => {
        const href = normalizeHref(anchor);
        const data = await fetchAnnotations();
        return (data.annotations || []).find((item) => item.href === href || item.href === anchor.getAttribute("href"));
    };

    const ensurePreview = () => {
        if (preview) return preview;
        preview = document.createElement("aside");
        preview.className = "link-preview";
        preview.hidden = true;
        preview.setAttribute("role", "status");
        document.body.appendChild(preview);
        return preview;
    };

    const hidePreview = () => {
        activeAnchor = null;
        if (preview) preview.hidden = true;
    };

    const positionPreview = (anchor) => {
        const box = ensurePreview();
        const rect = anchor.getBoundingClientRect();
        const margin = 14;
        const width = Math.min(390, window.innerWidth - margin * 2);
        box.style.maxWidth = `${width}px`;

        const previewRect = box.getBoundingClientRect();
        const left = Math.min(
            Math.max(margin, rect.left),
            window.innerWidth - previewRect.width - margin,
        );
        const below = rect.bottom + margin;
        const top = below + previewRect.height < window.innerHeight
            ? below
            : Math.max(margin, rect.top - previewRect.height - margin);

        box.style.left = `${left}px`;
        box.style.top = `${top}px`;
    };

    const showPreview = async (anchor) => {
        activeAnchor = anchor;
        const annotation = await annotationFor(anchor);
        if (!annotation || activeAnchor !== anchor) return;

        const box = ensurePreview();
        const source = escapeHtml(annotation.site_name || annotation.context_kind || annotation.kind || "link");
        const archive = annotation.archive
            ? `<a href="${escapeHtml(annotation.archive)}">archive record</a>`
            : "";
        const meta = [source, archive].filter(Boolean).join(" · ");
        box.innerHTML = `
            <strong>${escapeHtml(annotation.title || annotation.text || annotation.href)}</strong>
            <span>${escapeHtml(annotation.summary || annotation.href)}</span>
            <small>${meta}</small>
        `;
        box.hidden = false;
        positionPreview(anchor);
    };

    const escapeHtml = (value) => String(value)
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#39;");

    const initAnnotations = () => {
        const anchors = document.querySelectorAll("main a[href]:not(.heading-anchor):not(.up-btn)");
        anchors.forEach((anchor) => {
            anchor.addEventListener("pointerenter", () => showPreview(anchor));
            anchor.addEventListener("focus", () => showPreview(anchor));
            anchor.addEventListener("pointerleave", hidePreview);
            anchor.addEventListener("blur", hidePreview);
        });
        window.addEventListener("scroll", hidePreview, { passive: true });
        window.addEventListener("resize", hidePreview);
        document.addEventListener("keydown", (event) => {
            if (event.key === "Escape") hidePreview();
        });
    };

    const initTransclusions = () => {
        document.querySelectorAll("[data-transclude]").forEach(async (target) => {
            const url = target.getAttribute("data-transclude");
            if (!url) return;
            target.setAttribute("aria-busy", "true");
            try {
                const response = await fetch(url, { credentials: "same-origin" });
                if (!response.ok) throw new Error(`HTTP ${response.status}`);
                target.innerHTML = await response.text();
                target.dataset.transcluded = "true";
            } catch {
                target.dataset.transcluded = "false";
            } finally {
                target.removeAttribute("aria-busy");
            }
        });
    };

    ready(() => {
        initTransclusions();
        initAnnotations();
    });
})();
