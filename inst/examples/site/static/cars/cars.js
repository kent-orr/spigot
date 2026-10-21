// The table arrives rendered in R. Filtering asks the API for matching rows
// and redraws the table body.

const $ = (id) => document.getElementById(id);
const columns = ["model", "mpg", "cyl", "hp", "wt"];

function draw(rows) {
  const body = $("cars").tBodies[0];
  body.replaceChildren(...rows.map((row) => {
    const tr = document.createElement("tr");
    tr.dataset.car = row.model;
    for (const col of columns) {
      const td = document.createElement("td");
      td.textContent = row[col];
      tr.append(td);
    }
    return tr;
  }));
  $("status").textContent = `${rows.length} of 32 cars`;
}

$("filter").addEventListener("submit", async (e) => {
  e.preventDefault();
  try {
    const reply = await spigot.get("cars", { q: $("q").value, min_mpg: $("min_mpg").value });
    draw(reply.rows);
  } catch (err) {
    if (!(err instanceof spigot.SpigotError)) throw err;
    $("status").textContent = `Error ${err.status}: ${err.message}`;
  }
});

$("status").textContent = `${$("cars").tBodies[0].rows.length} cars`;
