(() => {
    const blocks = Array.from(document.querySelectorAll("[data-code-block]"));
    if (blocks.length === 0) return;

    const copyTimers = new WeakMap();

    const updateOverflow = (block) => {
        const scroller = block.querySelector("pre.sourceCode");
        if (!scroller) return;

        const edgeTolerance = 2;
        const maxScroll = Math.max(0, scroller.scrollWidth - scroller.clientWidth);
        const overflowing = maxScroll > edgeTolerance;
        if (overflowing) {
            scroller.setAttribute("tabindex", "0");
            scroller.setAttribute("role", "region");
            scroller.setAttribute("aria-describedby", `${block.id}-guidance`);
        } else {
            scroller.removeAttribute("tabindex");
            scroller.removeAttribute("role");
            scroller.removeAttribute("aria-describedby");
        }
        block.classList.toggle("can-scroll-left", scroller.scrollLeft > edgeTolerance);
        block.classList.toggle("can-scroll-right", scroller.scrollLeft < maxScroll - edgeTolerance);
        block.classList.add("code-block-ready");
    };

    const setCopyState = (button, status, label, announcement) => {
        button.textContent = label;
        status.textContent = announcement;
        const currentTimer = copyTimers.get(button);
        if (currentTimer !== undefined) window.clearTimeout(currentTimer);
        copyTimers.set(button, window.setTimeout(() => {
            button.textContent = "Copy";
            status.textContent = "";
            copyTimers.delete(button);
        }, 2200));
    };

    blocks.forEach((block) => {
        const scroller = block.querySelector("pre.sourceCode");
        const code = scroller?.querySelector("code.sourceCode");
        const button = block.querySelector(".code-copy");
        const status = block.querySelector(".code-copy-status");
        if (!scroller || !code || !(button instanceof HTMLButtonElement) || !status) return;

        button.hidden = false;
        button.addEventListener("click", async () => {
            const source = code.textContent.replace(/\n$/, "");
            try {
                await navigator.clipboard.writeText(source);
                setCopyState(button, status, "Copied", "Code copied to the clipboard.");
            } catch (_) {
                setCopyState(button, status, "Select", "Copy failed. Select the code manually.");
            }
        });

        let frame = null;
        const scheduleOverflowUpdate = () => {
            if (frame !== null) return;
            frame = window.requestAnimationFrame(() => {
                frame = null;
                updateOverflow(block);
            });
        };

        scroller.addEventListener("scroll", scheduleOverflowUpdate, { passive: true });
        window.addEventListener("resize", scheduleOverflowUpdate, { passive: true });
        updateOverflow(block);
    });
})();
