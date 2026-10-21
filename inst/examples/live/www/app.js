// The page's only script. spigot_app() adds spigot.js, which defines spigot.get(),
// spigot.post() and spigot.on().

const $ = (id) => document.getElementById(id);

// The count only goes up, so show the highest value seen. A reply and a push
// can arrive in either order: R sends the push while the endpoint runs, so it
// can reach the page before the reply to the same request.
let shown = -1;
function showCount(n) {
  if (n <= shown) return;
  shown = n;
  $("count").textContent = n;
}

const lines = [];
function log(line) {
  lines.push(`${new Date().toLocaleTimeString()}  ${line}`);
  $("log").textContent = lines.slice(-10).join("\n");
}

// Push: R calls spigot_broadcast() when the count changes or a tab opens or closes.
spigot.on("count", (msg) => {
  showCount(msg.count);
  log(`push  count: ${msg.count} (+${msg.by})`);
});

// The number of tabs goes down as well as up, so "highest seen" does not work
// for it. Once one push has arrived, every later change arrives as a push too,
// and a reply that lands after it may be older, so the reply is ignored.
let tabsPushed = false;
spigot.on("tabs", (msg) => {
  tabsPushed = true;
  $("tabs").textContent = msg.tabs;
  log(`push  tabs: ${msg.tabs}`);
});

// HTTP: read the current state once. spigot.get() waits for the Shiny session.
spigot.get("state").then((s) => {
  showCount(s.count);
  if (!tabsPushed) $("tabs").textContent = s.tabs;
});

async function add(by) {
  try {
    const reply = await spigot.post("increment", { by });
    showCount(reply.count);
    log(`reply count: ${reply.count}`);
  } catch (err) {
    if (!(err instanceof spigot.SpigotError)) throw err;
    log(`reply ${err.status}: ${err.message}`);
  }
}

$("plus-one").addEventListener("click", () => add(1));
$("plus-five").addEventListener("click", () => add(5));
$("plus-bad").addEventListener("click", () => add(11));
