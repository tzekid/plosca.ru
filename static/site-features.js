(() => {
    const annotationsUrl = "/metadata/annotations.json";
    let annotationsPromise = null;
    let preview = null;
    let activeAnchor = null;
    let activeInteractive = false;
    let previewPointerInside = false;
    let hideTimer = null;

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
        preview.addEventListener("pointerenter", () => {
            if (!activeInteractive) return;
            previewPointerInside = true;
            cancelHide();
        });
        preview.addEventListener("pointerleave", () => {
            previewPointerInside = false;
            if (activeInteractive) scheduleHide();
        });
        preview.addEventListener("focusin", () => {
            if (activeInteractive) cancelHide();
        });
        preview.addEventListener("focusout", (event) => {
            if (activeInteractive && !preview.contains(event.relatedTarget)) scheduleHide();
        });
        document.body.appendChild(preview);
        return preview;
    };

    const cancelHide = () => {
        if (!hideTimer) return;
        window.clearTimeout(hideTimer);
        hideTimer = null;
    };

    const scheduleHide = () => {
        cancelHide();
        hideTimer = window.setTimeout(() => {
            if (previewPointerInside) return;
            hidePreview();
        }, 160);
    };

    const hidePreview = () => {
        cancelHide();
        activeAnchor = null;
        activeInteractive = false;
        previewPointerInside = false;
        if (preview) preview.hidden = true;
    };

    const positionPreview = (anchor) => {
        const box = ensurePreview();
        const rect = anchor.getBoundingClientRect();
        const margin = 16;
        const width = Math.min(activeInteractive ? 560 : 420, window.innerWidth - margin * 2);
        box.style.width = `${width}px`;

        const previewRect = box.getBoundingClientRect();
        const left = Math.min(
            Math.max(margin, rect.left - (activeInteractive ? 28 : 0)),
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
        cancelHide();
        activeAnchor = anchor;
        const annotation = await annotationFor(anchor);
        if (activeAnchor !== anchor) return;
        if (!annotation) {
            hidePreview();
            return;
        }

        const box = ensurePreview();
        const hasPreviewImage = Boolean(annotation.preview_image);
        const isPdfPreview = annotation.context_kind === "pdf" || annotation.kind === "pdf";
        const interactive = annotation.context_kind === "wikipedia" || annotation.kind === "internal" || isPdfPreview;
        activeInteractive = interactive;
        box.classList.toggle("link-preview--interactive", interactive);
        box.classList.toggle("link-preview--article", annotation.kind === "internal");
        box.classList.toggle("link-preview--wikipedia", annotation.context_kind === "wikipedia");
        box.classList.toggle("link-preview--pdf", isPdfPreview);
        const source = escapeHtml(isPdfPreview ? "PDF" : annotation.site_name || annotation.context_kind || annotation.kind || "link");
        const date = annotation.date ? escapeHtml(formatDate(annotation.date)) : "";
        const fileSize = Number.isFinite(Number(annotation.file_size)) ? escapeHtml(formatBytes(Number(annotation.file_size))) : "";
        const archive = annotation.archive
            ? `<a href="${escapeHtml(annotation.archive)}">archive record</a>`
            : "";
        const open = isPdfPreview ? `<a href="${escapeHtml(annotation.href)}">open PDF</a>` : "";
        const meta = [source, date, fileSize, archive || open].filter(Boolean).join(" · ");
        const previewWidth = Number.isFinite(Number(annotation.preview_width)) ? ` width="${Number(annotation.preview_width)}"` : "";
        const previewHeight = Number.isFinite(Number(annotation.preview_height)) ? ` height="${Number(annotation.preview_height)}"` : "";
        const previewImage = hasPreviewImage
            ? `<figure class="link-preview__figure">
                <img src="${escapeHtml(annotation.preview_image)}"${previewWidth}${previewHeight} alt="${escapeHtml(annotation.title || annotation.text || "PDF")} preview" loading="lazy" decoding="async">
            </figure>`
            : "";
        box.innerHTML = `
            <div class="link-preview__header">
                <strong>${escapeHtml(annotation.title || annotation.text || annotation.href)}</strong>
            </div>
            <div class="link-preview__body">
                <p>${escapeHtml(annotation.summary || annotation.href)}</p>
                ${previewImage}
            </div>
            <small class="link-preview__meta">${meta}</small>
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

    const formatDate = (value) => {
        const match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(value));
        if (!match) return value;
        const date = new Date(`${value}T00:00:00Z`);
        if (Number.isNaN(date.valueOf())) return value;
        return date.toLocaleDateString("en-GB", {
            day: "numeric",
            month: "long",
            year: "numeric",
            timeZone: "UTC",
        });
    };

    const formatBytes = (value) => {
        if (!Number.isFinite(value) || value < 0) return "";
        if (value < 1024) return `${value} B`;
        const units = ["KB", "MB", "GB"];
        let scaled = value / 1024;
        let unitIndex = 0;
        while (scaled >= 1024 && unitIndex < units.length - 1) {
            scaled /= 1024;
            unitIndex += 1;
        }
        const precision = scaled >= 10 || unitIndex === 0 ? 0 : 1;
        return `${scaled.toFixed(precision)} ${units[unitIndex]}`;
    };

    const initAnnotations = () => {
        const anchors = document.querySelectorAll("main a[href]:not(.heading-anchor):not(.up-btn)");
        anchors.forEach((anchor) => {
            anchor.addEventListener("pointerenter", () => showPreview(anchor));
            anchor.addEventListener("focus", () => showPreview(anchor));
            anchor.addEventListener("pointerleave", () => {
                if (activeInteractive && activeAnchor === anchor) {
                    scheduleHide();
                } else {
                    hidePreview();
                }
            });
            anchor.addEventListener("blur", (event) => {
                if (activeInteractive && preview && preview.contains(event.relatedTarget)) {
                    scheduleHide();
                } else {
                    hidePreview();
                }
            });
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
