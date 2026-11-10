// Sends the form to POST /api/split and shows the result table.
(function () {
  const form = document.getElementById("split-form");
  const errorBox = document.getElementById("error");
  const table = document.getElementById("result");

  function showError(message) {
    errorBox.textContent = message;
    errorBox.hidden = false;
    table.hidden = true;
  }

  form.addEventListener("submit", async function (event) {
    event.preventDefault();
    errorBox.hidden = true;

    const people = document.getElementById("people").value
      .split(/[\n,]/)
      .map((name) => name.trim())
      .filter((name) => name.length > 0);

    let response;
    try {
      response = await fetch("/api/split", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ total: document.getElementById("total").value, people: people }),
      });
    } catch (err) {
      showError("Could not reach the server. Please try again.");
      return;
    }

    let data;
    try {
      data = await response.json();
    } catch (err) {
      showError("The server sent an unexpected reply (HTTP " + response.status + ").");
      return;
    }
    if (!response.ok) {
      showError(data.error || "Something went wrong.");
      return;
    }

    const body = table.querySelector("tbody");
    body.replaceChildren();
    for (const share of data.shares) {
      const row = document.createElement("tr");
      const name = document.createElement("td");
      const amount = document.createElement("td");
      name.textContent = share.name; // textContent (not innerHTML) prevents HTML injection
      amount.textContent = share.amount;
      amount.className = "num";
      row.append(name, amount);
      body.append(row);
    }
    document.getElementById("result-total").textContent = data.total;
    table.hidden = false;
  });
})();
