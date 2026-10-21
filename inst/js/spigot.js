/* spigot.js: the browser client for a spigot app. See ?spigot::spigot_dependency.
 *
 * ES2017 syntax and no build step: the file is served as it is. It uses
 * fetch, URL, AbortController and ReadableStream; every browser with those
 * has ES2017. A classic script, not a module, so document.currentScript works
 * and it runs after shiny.js. Defines window.spigot.
 */
(function (window, document) {
  "use strict";

  const HEADER = "X-Spigot-Session";
  const script = document.currentScript;
  const prefix = (script && script.getAttribute("data-prefix")) || "/api";

  // ---- errors ----------------------------------------------------------------

  // Rejection value of every call: a non-2xx reply (status is the HTTP status),
  // or no reply at all (status 0: timeout or network failure).
  class SpigotError extends Error {
    constructor(status, message, body) {
      super(message);
      this.name = "SpigotError";
      this.status = status;
      this.body = body;
    }
  }

  // ---- session ---------------------------------------------------------------

  function shinyToken() {
    const s = window.Shiny;
    return (s && s.shinyapp && s.shinyapp.config && s.shinyapp.config.sessionId) || null;
  }

  const spigot = {
    SpigotError,
    prefix,
    // URL of the API, ending in "/". Resolved against the page, so it follows
    // the app when it is served under a subpath.
    base: new URL(`${prefix.replace(/^\/+/, "")}/`, document.baseURI).href,
    sessionId: null
  };

  let resolveReady;
  spigot.ready = new Promise((resolve) => { resolveReady = resolve; });

  // Shiny sets config.sessionId and then triggers shiny:sessioninitialized (a
  // jQuery event); the token is not there yet at shiny:connected. After a
  // reconnect the event fires again with a new token.
  function initialized() {
    const id = shinyToken();
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
    const parts = [];
    Object.keys(query || {}).forEach((key) => {
      const value = query[key];
      (Array.isArray(value) ? value : [value]).forEach((v) => {
        if (v === null || v === undefined) return;
        if (v instanceof Date) v = v.toISOString();
        parts.push(`${encodeURIComponent(key)}=${encodeURIComponent(v)}`);
      });
    });
    return parts.join("&");
  }

  // Paths are always relative to the API: "items" and "/items" are the same.
  function apiUrl(path, query) {
    let url = spigot.base + String(path).replace(/^\/+/, "");
    const q = encodeQuery(query);
    if (q) url += (url.indexOf("?") === -1 ? "?" : "&") + q;
    return url;
  }

  // Bodies fetch() sends as they are. Anything else, strings included, is
  // sent as JSON; send text with a Blob.
  function isRawBody(body) {
    return body instanceof FormData || body instanceof Blob ||
      body instanceof URLSearchParams || body instanceof ReadableStream ||
      body instanceof ArrayBuffer || ArrayBuffer.isView(body);
  }

  // JSON when the reply says so and parses, else text; null when empty.
  async function readBody(res) {
    const text = await res.text();
    if (text === "") return null;
    if (/[\/+]json\b/i.test(res.headers.get("Content-Type") || "")) {
      try { return JSON.parse(text); } catch (e) { /* fall through to text */ }
    }
    return text;
  }

  function errorMessage(res, body) {
    if (body && typeof body === "object" && typeof body.error === "string") return body.error;
    return res.statusText || `HTTP ${res.status}`;
  }

  // options: query (object), body, headers (object or Headers), timeout (ms).
  // Calls made before the session exists wait for it; the timeout counts from
  // the call.
  async function request(method, path, options) {
    const opts = options || {};
    const verb = String(method).toUpperCase();
    const url = apiUrl(path, opts.query);
    const label = `${verb} ${path}`;
    const init = { method: verb, headers: new Headers({ Accept: "application/json" }) };
    if (opts.body !== undefined) {
      if (isRawBody(opts.body)) {
        init.body = opts.body;
      } else {
        init.body = JSON.stringify(opts.body);
        init.headers.set("Content-Type", "application/json");
      }
    }
    new Headers(opts.headers || {}).forEach((value, name) => init.headers.set(name, value));
    const controller = new AbortController();
    init.signal = controller.signal;

    let timer = null;
    const timeout = new Promise((resolve, reject) => {
      if (!(opts.timeout > 0)) return;
      timer = setTimeout(() => {
        controller.abort();
        reject(new SpigotError(0, `spigot: ${label} timed out after ${opts.timeout} ms`, null));
      }, opts.timeout);
    });

    const run = async () => {
      await spigot.ready;
      if (controller.signal.aborted) return null;
      // Set last, so options.headers cannot replace it.
      init.headers.set(HEADER, shinyToken() || spigot.sessionId);
      let res, body;
      try {
        res = await fetch(url, init);
        body = await readBody(res);
      } catch (err) {
        throw new SpigotError(0, `spigot: ${label} failed: network error (${err && err.message})`, null);
      }
      if (res.ok) return body;
      throw new SpigotError(res.status, errorMessage(res, body), body);
    };

    try {
      return await Promise.race([timeout, run()]);
    } finally {
      clearTimeout(timer);
    }
  }

  // spigot.get(path, query, options) and friends: the second argument is
  // options.query or options.body when it is given.
  const withOption = (method, name) => (path, value, options) =>
    request(method, path, value === undefined ? options : Object.assign({}, options, { [name]: value }));

  spigot.request = request;
  spigot.get = withOption("GET", "query");
  spigot.del = withOption("DELETE", "query");
  spigot.post = withOption("POST", "body");
  spigot.put = withOption("PUT", "body");

  // ---- push ------------------------------------------------------------------

  // event name -> array of listeners. spigot_emit() and spigot_broadcast() in R
  // send a "spigot:event" custom message {event, json}.
  const listeners = Object.create(null);

  function checkEvent(event) {
    if (typeof event !== "string" || event === "") {
      throw new TypeError("spigot: event must be a non-empty string");
    }
  }

  // Calls fn(data, event) for each `event` pushed from R. Adding the same fn
  // twice has no effect. Returns a function that removes it.
  spigot.on = (event, fn) => {
    checkEvent(event);
    if (typeof fn !== "function") throw new TypeError("spigot.on: listener must be a function");
    const list = listeners[event] || (listeners[event] = []);
    if (list.indexOf(fn) === -1) list.push(fn);
    return () => spigot.off(event, fn);
  };

  // Removes fn from `event`, or every listener of `event` when fn is omitted.
  spigot.off = (event, fn) => {
    checkEvent(event);
    const list = listeners[event];
    if (!list) return;
    if (fn === undefined) {
      delete listeners[event];
      return;
    }
    const i = list.indexOf(fn);
    if (i !== -1) list.splice(i, 1);
    if (!list.length) delete listeners[event];
  };

  // Rethrown asynchronously so it is still reported, as a DOM event
  // listener's error is.
  const report = (err) => setTimeout(() => { throw err; }, 0);

  // Each listener runs even if an earlier one throws. Iterates a copy, so
  // listeners may call on/off while the event runs.
  function dispatch(event, data) {
    (listeners[event] || []).slice().forEach((fn) => {
      try {
        fn.call(spigot, data, event);
      } catch (err) {
        report(err);
      }
    });
  }

  function onEventMessage(msg) {
    let data;
    try {
      data = JSON.parse(msg.json);
    } catch (err) {
      report(err);
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
    window.Shiny.setInputValue(`${msg.name}:spigot.ref`, msg.id, { priority: "event" });
  }

  function addHandlers() {
    const s = window.Shiny;
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
    const a = e.target && e.target.closest ? e.target.closest("a[href]") : null;
    if (!a || (a.target && a.target !== "_self")) return;
    const href = a.getAttribute("href");
    if (href.charAt(0) !== "#") return;
    e.preventDefault();
    window.location.hash = href;
  }
  document.addEventListener("click", onFragmentClick);

  window.spigot = spigot;
})(window, document);
