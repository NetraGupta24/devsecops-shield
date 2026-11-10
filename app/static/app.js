// Sends the form to POST /api/split and shows the result table.
(function () {
  const form = document.getElementById("split-form");
  const mode = document.getElementById("mode");
  const people = document.getElementById("people");
  const label = document.getElementById("people-label");
  const hint = document.getElementById("people-hint");
  const errorBox = document.getElementById("error");
  const table = document.getElementById("result");

  const HELP = {
    equal: ["People (one per line or separated by commas)", "Asha\nBen\nChitra", ""],
    percentage: ["People and their percentage", "Asha: 50\nBen: 30\nChitra: 20", "Write Name: percent. The percentages must add up to 100."],
    amount: ["People and the amount each pays (Rs)", "Asha: 500\nBen: 300\nChitra: 200", "Write Name: amount. The amounts must add up to the total."],
  };

  function updateHelp() {
    const [labelText, placeholder, hintText] = HELP[mode.value];
    label.textContent = labelText;
    people.placeholder = placeholder;
    hint.textContent = hintText;
    hint.hidden = hintText === "";
  }
  mode.addEventListener("change", updateHelp);

  function showError(message) {
    errorBox.textContent = message;
    errorBox.hidden = false;
    table.hidden = true;
  }

  // "Asha: 50" -> {name: "Asha", value: "50"} (split at the LAST colon)
  function parsePeople() {
    const entries = people.value.split(/[\n,]/).map((s) => s.trim()).filter((s) => s.length > 0);
    if (mode.value === "equal") {
      return entries;
    }
    return entries.map((entry) => {
      const at = entry.lastIndexOf(":");
      if (at === -1) {
        throw new Error('Write each person as "Name: value", for example "Asha: 50".');
      }
      return { name: entry.slice(0, at).trim(), value: entry.slice(at + 1).trim() };
    });
  }

  form.addEventListener("submit", async function (event) {
    event.preventDefault();
    errorBox.hidden = true;

    let peopleList;
    try {
      peopleList = parsePeople();
    } catch (err) {
      showError(err.message);
      return;
    }

    let response;
    try {
      response = await fetch("/api/split", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ total: document.getElementById("total").value, mode: mode.value, people: peopleList }),
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
