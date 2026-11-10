# `app/static/app.js`

**What it does:** When you click "Split the bill", it turns the names into a list, sends them to
`POST /api/split` with `fetch()`, and fills the result table (or shows the error message).

**Security detail:** Names are inserted with `textContent`, not `innerHTML`, so a "name" like
`<script>...</script>` is shown as plain text instead of running as code.
