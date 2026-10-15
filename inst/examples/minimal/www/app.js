// The page's only script. It calls the mounted API with spigot.js, which
// spigot_app() adds to every page: spigot.get() and spigot.post() take paths
// relative to the API ("hello" means api/hello, relative to this page, so the
// app also works under a subpath on Shiny Server or Posit Connect), send this
// tab's Shiny session token, and wait for the session if it has not started.
// They resolve with the parsed JSON reply and reject with a SpigotError
// ({status, message, body}) for any non-2xx reply.

// Run one call and describe the outcome for show().
async function call(label, promise) {
  const t0 = performance.now();
  const ms = () => Math.round(performance.now() - t0);
  try {
    const data = await promise;
    return { label, ok: true, outcome: "OK", ms: ms(), data };
  } catch (err) {
    if (!(err instanceof spigot.SpigotError)) throw err;
    // status 0 means no reply: a timeout or a network failure.
    const outcome = err.status ? String(err.status) : "no reply";
    return { label, ok: false, outcome, ms: ms(), data: err.body ?? err.message };
  }
}

function show(el, r) {
  el.textContent = `${r.label}  →  ${r.outcome}  (${r.ms} ms)\n\n` +
    (typeof r.data === "string" ? r.data : JSON.stringify(r.data, null, 2));
  el.classList.toggle("err", !r.ok);
}

function showError(el, err) {
  el.textContent = err.message;
  el.classList.add("err");
}

const $ = (id) => document.getElementById(id);

$("hello-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const name = $("hello-name").value;
  show($("hello-out"), await call("GET api/hello", spigot.get("hello", { name })));
});

$("echo-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const out = $("echo-out");
  let body;
  try { body = JSON.parse($("echo-body").value); }
  catch (err) { showError(out, new Error("the box does not hold valid JSON")); return; }
  show(out, await call("POST api/echo", spigot.post("echo", body)));
});

$("summary-form").addEventListener("submit", async (e) => {
  e.preventDefault();
  const n = $("summary-n").value;
  show($("summary-out"), await call("GET api/summary", spigot.get("summary", { n })));
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
  const r = await call("slow", spigot.get("slow", { seconds: 3 }));
  logLine(`slow: ${r.outcome} after ${r.ms} ms`);
});

$("ping-btn").addEventListener("click", async () => {
  const r = await call("ping", spigot.get("hello", { name: "ping" }));
  logLine(`ping: ${r.outcome} after ${r.ms} ms`);
});
