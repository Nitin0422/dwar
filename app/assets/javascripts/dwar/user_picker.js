// frozen_string_literal: true -- (JS counterpart: strict mode, no build step)
//
// Dwar user picker autocomplete (vanilla JS, no framework or build step).
//
// Usage:
//   DwarUserPicker.init(input, {url: "/dwar/admin/users.json", hiddenField: hiddenInput});
//
// Contract:
// - input: visible text <input> the admin types into.
// - options.url: picker endpoint returning [{id, label}, ...].
// - options.hiddenField: hidden <input> receiving the selected record id.
// - options.list (optional): <ul> for results; created after the input when omitted.
// - options.debounceMs (optional, default 200).
//
// Behavior: debounced fetch on input -> render selectable list -> click/Enter
// selects (sets hidden id + visible label, clears list). Empty query or any
// fetch/parse failure renders the empty state and never throws.

(function(global) {
  "use strict";

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

  function init(input, options) {
    try {
      if (!input) {
        return;
      }
      var opts = options || {};
      var url = opts.url;
      if (!url) {
        return;
      }
      var hiddenField = opts.hiddenField || null;
      var debounceMs = opts.debounceMs || 200;
      var list = opts.list || findOrCreateList(input);
      var timer = null;
      var items = [];
      var activeIndex = -1;

      try {
        input.setAttribute("autocomplete", "off");
        input.setAttribute("role", "combobox");
        input.setAttribute("aria-expanded", "false");
      } catch (_e) {
        // Non-fatal: attributes are progressive enhancement.
      }

      function render(results) {
        try {
          items = Array.isArray(results) ? results : [];
          activeIndex = -1;
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
            li.setAttribute("data-index", String(index));
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
        try {
          global.fetch(url + "?q=" + global.encodeURIComponent(query), {
            headers: {Accept: "application/json"}
          }).then(function(response) {
            if (!response || !response.ok) {
              throw new Error("request failed");
            }
            return response.json();
          }).then(function(data) {
            render(data);
          }).catch(function() {
            clearList(list);
          });
        } catch (_e) {
          clearList(list);
        }
      }

      input.addEventListener("input", function() {
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
      });

      input.addEventListener("keydown", function(event) {
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
          var children = list.children;
          for (var i = 0; i < children.length; i++) {
            try {
              children[i].style.background = (i === activeIndex) ? "#eef" : "";
            } catch (_e) {
              // ignore per-row styling failures
            }
          }
        } catch (_e) {
          // Never throw from keyboard handling.
        }
      });

      global.document.addEventListener("click", function(event) {
        try {
          if (event.target !== input && list && !list.contains(event.target)) {
            clearList(list);
          }
        } catch (_e) {
          // ignore
        }
      });
    } catch (_e) {
      // DwarUserPicker.init never throws.
    }
  }

  global.DwarUserPicker = global.DwarUserPicker || {};
  global.DwarUserPicker.init = init;
})(typeof window !== "undefined" ? window : this);
