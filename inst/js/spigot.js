/* spigot.js: the browser client for a spigot app. See ?spigot::spigot_dependency.
 *
 * Plain ES5 syntax and no build step: the file is served as it is. It uses
 * fetch, Promise, URL and AbortController, which every current browser has.
 * Defines window.spigot.
 */
(function (window, document) {
  "use strict";

  var HEADER = "X-Spigot-Session";
  var script = document.currentScript;
  var prefix = (script && script.getAttribute("data-prefix")) || "/api";

  // ---- errors ----------------------------------------------------------------

  // Rejection value of every call: a non-2xx reply (status is the HTTP status),
  // or no reply at all (status 0: timeout or network failure).
  function SpigotError(status, message, body) {
    this.name = "SpigotError";
    this.status = status;
    this.message = message;
    this.body = body;
    this.stack = new Error(message).stack;
  }
  SpigotError.prototype = Object.create(Error.prototype);
  SpigotError.prototype.constructor = SpigotError;
  SpigotError.prototype.name = "SpigotError";

  // ---- session ---------------------------------------------------------------

  function shinyToken() {
    var s = window.Shiny;
    return (s && s.shinyapp && s.shinyapp.config && s.shinyapp.config.sessionId) || null;
  }

  var spigot = {
    SpigotError: SpigotError,
    prefix: prefix,
    // URL of the API, ending in "/". Resolved against the page, so it follows
    // the app when it is served under a subpath.
    base: new URL(prefix.replace(/^\/+/, "") + "/", document.baseURI).href,
    sessionId: null
  };

  var resolveReady;
  spigot.ready = new Promise(function (resolve) { resolveReady = resolve; });

  // Shiny sets config.sessionId and then triggers shiny:sessioninitialized (a
  // jQuery event); the token is not there yet at shiny:connected. After a
  // reconnect the event fires again with a new token.
  function initialized() {
    var id = shinyToken();
    if (!id) return;
    spigot.sessionId = id;
    resolveReady(id);
  }
  function listen() {
    if (window.jQuery) window.jQuery(document).on("shiny:sessioninitialized", initialized);
  }
  if (window.jQuery) listen(); else document.addEventListener("DOMContentLoaded", listen);
  initialized();

  // ---- requests --------------------------------------------------------------

  // {a: 1, b: [2, 3], c: null} -> "a=1&b=2&b=3". %20 for spaces, not "+".
  function encodeQuery(query) {
    var parts = [];
    Object.keys(query || {}).forEach(function (key) {
      var value = query[key];
      (Array.isArray(value) ? value : [value]).forEach(function (v) {
        if (v === null || v === undefined) return;
        if (v instanceof Date) v = v.toISOString();
        parts.push(encodeURIComponent(key) + "=" + encodeURIComponent(v));
      });
    });
    return parts.join("&");
  }

  // Paths are always relative to the API: "items" and "/items" are the same.
  function apiUrl(path, query) {
    var url = spigot.base + String(path).replace(/^\/+/, "");
    var q = encodeQuery(query);
    if (q) url += (url.indexOf("?") === -1 ? "?" : "&") + q;
    return url;
  }

  // Bodies fetch() sends as they are. Anything else, strings included, is
  // sent as JSON; send text with a Blob.
  function isRawBody(body) {
    return (typeof FormData !== "undefined" && body instanceof FormData) ||
      (typeof Blob !== "undefined" && body instanceof Blob) ||
      (typeof URLSearchParams !== "undefined" && body instanceof URLSearchParams) ||
      (typeof ReadableStream !== "undefined" && body instanceof ReadableStream) ||
      body instanceof ArrayBuffer || ArrayBuffer.isView(body);
  }

  // JSON when the reply says so and parses, else text; null when empty.
  function readBody(res) {
    return res.text().then(function (text) {
      if (text === "") return null;
      if (/[\/+]json\b/i.test(res.headers.get("Content-Type") || "")) {
        try { return JSON.parse(text); } catch (e) { /* fall through to text */ }
      }
      return text;
    });
  }

  function errorMessage(res, body) {
    if (body && typeof body === "object" && typeof body.error === "string") return body.error;
    return res.statusText || "HTTP " + res.status;
  }

  // options: query (object), body, headers (object or Headers), timeout (ms).
  // Calls made before the session exists wait for it; the timeout counts from
  // the call.
  function request(method, path, options) {
    var opts = options || {};
    var url = apiUrl(path, opts.query);
    var label = String(method).toUpperCase() + " " + path;
    var init = { method: String(method).toUpperCase(), headers: new Headers({ Accept: "application/json" }) };
    if (opts.body !== undefined) {
      if (isRawBody(opts.body)) {
        init.body = opts.body;
      } else {
        init.body = JSON.stringify(opts.body);
        init.headers.set("Content-Type", "application/json");
      }
    }
    new Headers(opts.headers || {}).forEach(function (value, name) {
      init.headers.set(name, value);
    });
    var controller = new AbortController();
    init.signal = controller.signal;

    return new Promise(function (resolve, reject) {
      var timedOut = false;
      var timer = opts.timeout > 0 ? setTimeout(function () {
        timedOut = true;
        controller.abort();
        reject(new SpigotError(0, "spigot: " + label + " timed out after " + opts.timeout + " ms", null));
      }, opts.timeout) : null;

      spigot.ready.then(function () {
        if (timedOut) return null;
        // Set last, so options.headers cannot replace it.
        init.headers.set(HEADER, shinyToken() || spigot.sessionId);
        return fetch(url, init).then(function (res) {
          return readBody(res).then(function (body) {
            if (res.ok) return body;
            throw new SpigotError(res.status, errorMessage(res, body), body);
          });
        });
      }).then(resolve, function (err) {
        if (timedOut) return;
        if (!(err instanceof SpigotError)) {
          err = new SpigotError(0, "spigot: " + label + " failed: network error (" +
                                (err && err.message) + ")", null);
        }
        reject(err);
      }).then(function () {
        clearTimeout(timer);
      });
    });
  }

  function withOption(options, name, value) {
    var out = {};
    Object.keys(options || {}).forEach(function (k) { out[k] = options[k]; });
    if (value !== undefined) out[name] = value;
    return out;
  }

  spigot.request = request;
  spigot.get = function (path, query, options) {
    return request("GET", path, withOption(options, "query", query));
  };
  spigot.del = function (path, query, options) {
    return request("DELETE", path, withOption(options, "query", query));
  };
  spigot.post = function (path, body, options) {
    return request("POST", path, withOption(options, "body", body));
  };
  spigot.put = function (path, body, options) {
    return request("PUT", path, withOption(options, "body", body));
  };

  // ---- push ------------------------------------------------------------------

  // event name -> array of listeners. spigot_emit() and spigot_broadcast() in R
  // send a "spigot:event" custom message {event, json}.
  var listeners = Object.create(null);

  function checkEvent(event) {
    if (typeof event !== "string" || event === "") {
      throw new TypeError("spigot: event must be a non-empty string");
    }
  }

  // Calls fn(data, event) for each `event` pushed from R. Adding the same fn
  // twice has no effect. Returns a function that removes it.
  spigot.on = function (event, fn) {
    checkEvent(event);
    if (typeof fn !== "function") throw new TypeError("spigot.on: listener must be a function");
    var list = listeners[event] || (listeners[event] = []);
    if (list.indexOf(fn) === -1) list.push(fn);
    return function () { spigot.off(event, fn); };
  };

  // Removes fn from `event`, or every listener of `event` when fn is omitted.
  spigot.off = function (event, fn) {
    checkEvent(event);
    var list = listeners[event];
    if (!list) return;
    if (fn === undefined) {
      delete listeners[event];
      return;
    }
    var i = list.indexOf(fn);
    if (i !== -1) list.splice(i, 1);
    if (!list.length) delete listeners[event];
  };

  // Each listener runs even if an earlier one throws; the error is rethrown
  // asynchronously so it is still reported, as a DOM event listener's is.
  // Iterates a copy, so listeners may call on/off while the event runs.
  function dispatch(event, data) {
    (listeners[event] || []).slice().forEach(function (fn) {
      try {
        fn.call(spigot, data, event);
      } catch (err) {
        setTimeout(function () { throw err; }, 0);
      }
    });
  }

  function onEventMessage(msg) {
    var data;
    try {
      data = JSON.parse(msg.json);
    } catch (err) {
      setTimeout(function () { throw err; }, 0);
      return;
    }
    dispatch(msg.event, data);
  }

  // ---- reactive bridge -------------------------------------------------------

  // spigot_trigger() in R keeps the value and sends {name, id}. Sending the id
  // back as input "<name>:spigot.ref" makes Shiny's spigot.ref input handler
  // set input[[name]] to the value. "event" priority sends it right away
  // instead of waiting to batch it with other input changes.
  function onSetInputMessage(msg) {
    window.Shiny.setInputValue(msg.name + ":spigot.ref", msg.id, { priority: "event" });
  }

  function addHandlers() {
    var s = window.Shiny;
    if (!s || !s.addCustomMessageHandler) return false;
    s.addCustomMessageHandler("spigot:event", onEventMessage);
    s.addCustomMessageHandler("spigot:set-input", onSetInputMessage);
    return true;
  }
  // shiny.js loads before this script on spigot pages; wait for it otherwise.
  if (!addHandlers()) document.addEventListener("DOMContentLoaded", addHandlers);

  // ---- nested pages ----------------------------------------------------------

  // spigot_app() gives a page below the top level <base href="../" data-spigot>
  // so relative URLs resolve from the app root. A base also sends
  // href="#section" to the root, so keep those links on this page. Leaves
  // alone clicks the page has handled, modified clicks and other targets.
  function onFragmentClick(e) {
    if (e.defaultPrevented || e.button !== 0 ||
        e.metaKey || e.ctrlKey || e.shiftKey || e.altKey) return;
    if (!document.querySelector("base[data-spigot]")) return;
    var a = e.target && e.target.closest ? e.target.closest("a[href]") : null;
    if (!a || (a.target && a.target !== "_self")) return;
    var href = a.getAttribute("href");
    if (href.charAt(0) !== "#") return;
    e.preventDefault();
    window.location.hash = href;
  }
  document.addEventListener("click", onFragmentClick);

  window.spigot = spigot;
})(window, document);
