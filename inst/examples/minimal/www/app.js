// The page's only script: plain fetch() against the mounted API.
// URLs are relative ("api/..."), so the app also works under a subpath on
// Shiny Server or Posit Connect.

async function api(method, path, body) {
  const opts = { method, headers: {} };
  if (body !== undefined) {
    opts.headers["Content-Type"] = "application/json";
    opts.body = typeof body === "string" ? body : JSON.stringify(body);
  }
  const t0 = performance.now();
  const res = await fetch("api/" + path, opts);
  const text = await res.text();
  let data;
  try { data = JSON.parse(text); } catch (e) { data = text; }
  return { method, path, status: res.status, ms: Math.round(performance.now() - t0), data };
}

function show(el, r) {
  el.textContent = `${r.method} api/${r.path}  →  ${r.status}  (${r.ms} ms)\n\n` +
    (typeof r.data === "string" ? r.data : JSON.stringify(r.data, null, 2));
  el.classList.toggle("err", r.status >= 400);
}

function showError(el, err) {
  el.textContent = "Request failed: " + err.message;
  el.classList.add("err");
}

const $ = (id) => document.getElementById(id);

$("hello-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const name = encodeURIComponent($("hello-name").value);
  try { show($("hello-out"), await api("GET", "hello?name=" + name)); }
  catch (err) { showError($("hello-out"), err); }
});

$("echo-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const out = $("echo-out");
  let body;
  try { body = JSON.parse($("echo-body").value); }
  catch (err) { showError(out, new Error("the box does not hold valid JSON")); return; }
  try { show(out, await api("POST", "echo", body)); }
  catch (err) { showError(out, err); }
});

$("summary-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const n = encodeURIComponent($("summary-n").value);
  try { show($("summary-out"), await api("GET", "summary?n=" + n)); }
  catch (err) { showError($("summary-out"), err); }
});

// The async demo appends to a running log.
const slowLog = [];
function logLine(line) {
  slowLog.push(`${new Date().toLocaleTimeString()}  ${line}`);
  $("slow-out").textContent = slowLog.slice(-12).join("\n");
  $("slow-out").classList.remove("err");
}

$("slow-btn").addEventListener("click", async () => {
  logLine("slow: sent, waiting 3 s ...");
  try {
    const r = await api("GET", "slow?seconds=3");
    logLine(`slow: ${r.status} after ${r.ms} ms`);
  } catch (err) { logLine("slow: failed: " + err.message); }
});

$("ping-btn").addEventListener("click", async () => {
  try {
    const r = await api("GET", "hello?name=ping");
    logLine(`ping: ${r.status} after ${r.ms} ms`);
  } catch (err) { logLine("ping: failed: " + err.message); }
});
