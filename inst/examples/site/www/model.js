// Ask the API for a bootstrapped fit. The reply comes from a future worker.

const $ = (id) => document.getElementById(id);
const fmt = (x) => x.toFixed(3);

$("fit").addEventListener("submit", async (e) => {
  e.preventDefault();
  const out = $("fit-out");
  const button = $("fit").querySelector("button");
  out.classList.remove("err");
  out.textContent = "Fitting ...";
  button.disabled = true;
  try {
    const r = await spigot.post("fit", { x: $("x").value, reps: Number($("reps").value) },
                                { timeout: 60000 });
    out.textContent =
      `mpg ~ ${r.x}\n\n` +
      `slope     ${fmt(r.slope.estimate)}\n` +
      `95% CI    ${fmt(r.slope.lower)} to ${fmt(r.slope.upper)}  (${r.reps} resamples)\n\n` +
      `Took ${r.seconds.toFixed(2)} s in worker process ${r.worker_pid}; ` +
      `the app runs in process ${r.app_pid}.`;
  } catch (err) {
    if (!(err instanceof spigot.SpigotError)) throw err;
    out.textContent = err.status ? `${err.status}: ${err.message}` : `No reply: ${err.message}`;
    out.classList.add("err");
  } finally {
    button.disabled = false;
  }
});
