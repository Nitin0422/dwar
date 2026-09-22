// frozen_string_literal: true -- (JS counterpart: strict mode, no build step)
//
// Dwar user picker autocomplete (vanilla JS, no framework or build step).
//
// Usage:
//   var picker = DwarUserPicker.init(input, {url: "/dwar/admin/users.json", hiddenField: hiddenInput});
//   // ... later, e.g. on Turbo navigation: picker.destroy();
//
// Contract:
// - input: visible text <input> the admin types into.
// - options.url: picker endpoint returning [{id, label}, ...]. May already
//   contain a query string; the search term is appended with ? or & as needed.
// - options.hiddenField: hidden <input> receiving the selected record id.
// - options.list (optional): <ul> for results; created after the input when omitted.
// - options.debounceMs (optional, default 200; 0 disables debouncing).
//
// Behavior: debounced fetch on input -> render selectable list -> click/Enter
// selects (sets hidden id + visible label, clears list). Empty query or any
// fetch/parse failure renders the empty state and never throws. Responses are
// guarded by a monotonic request token so a slow earlier response can never
// overwrite newer results (stale-response race).

(function(global) {
  "use strict";

  var listCounter = 0;

  function findOrCreateList(input) {
    try {
      var existing = null;
      if (input.parentElement) {
        existing = input.parentElement.querySelector("[data-dwar-user-picker-list]");
      }
      if (existing) {
        return existing;
      }
      var list = global.document.createElement("ul");
      list.setAttribute("data-dwar-user-picker-list", "");
      list.setAttribute("role", "listbox");
      list.style.listStyle = "none";
      list.style.margin = "0.25rem 0 0";
      list.style.padding = "0";
      if (input.parentElement) {
        input.parentElement.appendChild(list);
      } else if (input.insertAdjacentElement) {
        input.insertAdjacentElement("afterend", list);
      }
      return list;
    } catch (_e) {
      return null;
    }
  }

  function clearList(list) {
    try {
      if (list) {
        list.innerHTML = "";
      }
    } catch (_e) {
      // Never throw from UI cleanup.
    }
  }

  function buildSearchUrl(url, query) {
    var separator = (url.indexOf("?") === -1) ? "?" : "&";
    return url + separator + "q=" + global.encodeURIComponent(query);
  }

  function init(input, options) {
    try {
      if (!input) {
        return undefined;
      }
      var opts = options || {};
      var url = opts.url;
      if (!url) {
        return undefined;
      }
      var hiddenField = opts.hiddenField || null;
      var debounceMs = (opts.debounceMs === undefined || opts.debounceMs === null) ? 200 : opts.debounceMs;
      var list = opts.list || findOrCreateList(input);
      var timer = null;
      var items = [];
      var activeIndex = -1;
      var requestId = 0;
      var destroyed = false;

      if (list) {
        try {
          if (!list.id) {
            listCounter += 1;
            list.id = "dwar-user-picker-list-" + listCounter;
          }
        } catch (_e) {
          // ignore: id assignment is progressive enhancement
        }
      }

      try {
        input.setAttribute("autocomplete", "off");
        input.setAttribute("role", "combobox");
        input.setAttribute("aria-expanded", "false");
        if (list && list.id) {
          input.setAttribute("aria-controls", list.id);
        }
      } catch (_e) {
        // Non-fatal: attributes are progressive enhancement.
      }

      function syncActiveDescendant() {
        try {
          if (!list || !list.id) {
            return;
          }
          if (activeIndex >= 0) {
            input.setAttribute("aria-activedescendant", list.id + "-" + activeIndex);
          } else {
            input.removeAttribute("aria-activedescendant");
          }
        } catch (_e) {
          // ignore
        }
      }

      function render(results) {
        try {
          if (destroyed) {
            return;
          }
          items = Array.isArray(results) ? results : [];
          activeIndex = -1;
          syncActiveDescendant();
          if (!list) {
            return;
          }
          clearList(list);
          if (items.length === 0) {
            return;
          }
          items.forEach(function(item, index) {
            var li = global.document.createElement("li");
            li.setAttribute("role", "option");
            if (list.id) {
              li.id = list.id + "-" + index;
            }
            li.setAttribute("data-index", String(index));
            li.setAttribute("aria-selected", "false");
            li.style.cursor = "pointer";
            li.style.padding = "0.25rem 0.5rem";
            li.textContent = item && item.label != null ? String(item.label) : "";
            li.addEventListener("mousedown", function(event) {
              try {
                event.preventDefault();
                select(index);
              } catch (_e) {
                // Never throw from selection.
              }
            });
            list.appendChild(li);
          });
          try {
            input.setAttribute("aria-expanded", "true");
          } catch (_e) {
            // ignore
          }
        } catch (_e) {
          // Never throw from rendering; fall back to empty state.
          try {
            clearList(list);
          } catch (_ignore) {
            // ignore
          }
        }
      }

      function select(index) {
        try {
          var item = items[index];
          if (!item) {
            return;
          }
          input.value = item.label != null ? String(item.label) : "";
          if (hiddenField) {
            hiddenField.value = item.id != null ? String(item.id) : "";
          }
          clearList(list);
          items = [];
          activeIndex = -1;
          syncActiveDescendant();
          try {
            input.setAttribute("aria-expanded", "false");
          } catch (_e) {
            // ignore
          }
        } catch (_e) {
          // Never throw from selection.
        }
      }

      function search(query) {
        // Monotonic token: only the latest issued request may render, so a
        // slow earlier response can never overwrite newer results.
        var myId = requestId + 1;
        requestId = myId;
        try {
          global.fetch(buildSearchUrl(url, query), {
            headers: {Accept: "application/json"}
          }).then(function(response) {
            if (!response || !response.ok) {
              throw new Error("request failed");
            }
            return response.json();
          }).then(function(data) {
            if (myId !== requestId || destroyed) {
              return;
            }
            render(data);
          }).catch(function() {
            if (myId === requestId) {
              clearList(list);
            }
          });
        } catch (_e) {
          clearList(list);
        }
      }

      function onInput() {
        try {
          if (hiddenField) {
            hiddenField.value = "";
          }
          var query = input.value;
          if (timer) {
            global.clearTimeout(timer);
            timer = null;
          }
          if (!query) {
            clearList(list);
            return;
          }
          timer = global.setTimeout(function() {
            search(query);
          }, debounceMs);
        } catch (_e) {
          try {
            clearList(list);
          } catch (_ignore) {
            // ignore
          }
        }
      }

      function highlightActive() {
        var children = list ? list.children : [];
        for (var i = 0; i < children.length; i++) {
          try {
            children[i].style.background = (i === activeIndex) ? "#eef" : "";
            children[i].setAttribute("aria-selected", (i === activeIndex) ? "true" : "false");
          } catch (_e) {
            // ignore per-row styling failures
          }
        }
        syncActiveDescendant();
      }

      function onKeydown(event) {
        try {
          if (!list || items.length === 0) {
            return;
          }
          if (event.key === "ArrowDown") {
            event.preventDefault();
            activeIndex = (activeIndex + 1) % items.length;
          } else if (event.key === "ArrowUp") {
            event.preventDefault();
            activeIndex = (activeIndex - 1 + items.length) % items.length;
          } else if (event.key === "Enter") {
            if (activeIndex >= 0) {
              event.preventDefault();
              select(activeIndex);
            }
          } else if (event.key === "Escape") {
            clearList(list);
            items = [];
            activeIndex = -1;
          } else {
            return;
          }
          highlightActive();
        } catch (_e) {
          // Never throw from keyboard handling.
        }
      }

      function onDocumentClick(event) {
        try {
          if (event.target !== input && list && !list.contains(event.target)) {
            clearList(list);
          }
        } catch (_e) {
          // ignore
        }
      }

      function destroy() {
        try {
          destroyed = true;
          if (timer) {
            global.clearTimeout(timer);
            timer = null;
          }
          requestId += 1;
          input.removeEventListener("input", onInput);
          input.removeEventListener("keydown", onKeydown);
          global.document.removeEventListener("click", onDocumentClick);
          clearList(list);
        } catch (_e) {
          // Never throw from teardown.
        }
      }

      input.addEventListener("input", onInput);
      input.addEventListener("keydown", onKeydown);
      global.document.addEventListener("click", onDocumentClick);

      return {destroy: destroy};
    } catch (_e) {
      // DwarUserPicker.init never throws.
      return undefined;
    }
  }

  global.DwarUserPicker = global.DwarUserPicker || {};
  global.DwarUserPicker.init = init;
})(typeof window !== "undefined" ? window : this);
