(function () {
  var root = document.documentElement;
  var media = window.matchMedia ? window.matchMedia("(prefers-color-scheme: dark)") : null;
  var storageKey = "plosca:theme";
  var channelName = "plosca:theme";
  var memoryTheme = null;
  var channel = null;
  var controlsReady = false;

  function isTheme(value) {
    return value === "light" || value === "dark";
  }

  function systemTheme() {
    return media && media.matches ? "dark" : "light";
  }

  function readSessionTheme() {
    try {
      var value = window.sessionStorage && window.sessionStorage.getItem(storageKey);
      if (isTheme(value)) return value;
      if (value !== null && window.sessionStorage) window.sessionStorage.removeItem(storageKey);
    } catch (_) {
      return null;
    }
    return null;
  }

  function writeSessionTheme(theme) {
    memoryTheme = theme;
    try {
      if (window.sessionStorage) window.sessionStorage.setItem(storageKey, theme);
    } catch (_) {
      // Keep the choice for this page when sessionStorage is unavailable.
    }
  }

  function effectiveTheme() {
    return readSessionTheme() || memoryTheme || systemTheme();
  }

  function syncMeta(theme) {
    var themeMeta = document.querySelector('meta[name="theme-color"]');
    if (themeMeta) {
      themeMeta.setAttribute("content", theme === "dark" ? "#171717" : "#ffffff");
    }
  }

  function syncButtons(theme) {
    if (!controlsReady) return;

    var buttons = Array.prototype.slice.call(document.querySelectorAll(".theme-toggle"));
    var next = theme === "dark" ? "light" : "dark";

    buttons.forEach(function (button) {
      var glyph = button.querySelector("[aria-hidden='true']");
      button.setAttribute("aria-label", "Switch to " + next + " theme");
      button.setAttribute("aria-pressed", theme === "dark" ? "true" : "false");
      if (glyph) glyph.textContent = theme === "dark" ? "<{ ◑ }>" : "<{ ◐ }>";
    });
  }

  function applyTheme(theme) {
    root.dataset.theme = theme;
    syncMeta(theme);
    syncButtons(theme);
  }

  function broadcastTheme(theme) {
    if (!channel) return;
    channel.postMessage({ type: "theme-state", theme: theme });
  }

  function setupControls() {
    controlsReady = true;

    Array.prototype.slice.call(document.querySelectorAll(".theme-toggle")).forEach(function (button) {
      button.addEventListener("click", function () {
        var next = effectiveTheme() === "dark" ? "light" : "dark";
        writeSessionTheme(next);
        applyTheme(next);
        broadcastTheme(next);
      });
    });

    syncButtons(effectiveTheme());
  }

  if ("BroadcastChannel" in window) {
    channel = new window.BroadcastChannel(channelName);
    channel.addEventListener("message", function (event) {
      var message = event.data || {};

      if (message.type === "request-theme") {
        var storedTheme = readSessionTheme() || memoryTheme;
        if (storedTheme) broadcastTheme(storedTheme);
        return;
      }

      if (message.type === "theme-state" && isTheme(message.theme)) {
        writeSessionTheme(message.theme);
        applyTheme(message.theme);
      }
    });
  }

  if (media) {
    var onSystemThemeChange = function () {
      if (!readSessionTheme() && !memoryTheme) applyTheme(systemTheme());
    };
    if (media.addEventListener) {
      media.addEventListener("change", onSystemThemeChange);
    } else if (media.addListener) {
      media.addListener(onSystemThemeChange);
    }
  }

  var initialTheme = readSessionTheme();
  applyTheme(initialTheme || systemTheme());

  if (!initialTheme && channel) {
    channel.postMessage({ type: "request-theme" });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", setupControls);
  } else {
    setupControls();
  }
})();
