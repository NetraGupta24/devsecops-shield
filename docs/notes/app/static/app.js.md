# `app/static/app.js`

**What it does:** When you click "Split the bill", it turns the names into a list, sends them to
`POST /api/split` with `fetch()`, and fills the result table (or shows the error message).

**Security detail:** Names are inserted with `textContent`, not `innerHTML`, so a "name" like
`<script>...</script>` is shown as plain text instead of running as code.

## v2 additions
A "How to split" selector. In percentage/amount mode each line is `Name: value`. The script splits
at the *last* colon, sends `{name, value}` objects, and updates the label and hint text to match the
chosen mode.
