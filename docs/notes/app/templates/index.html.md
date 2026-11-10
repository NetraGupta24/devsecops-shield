# `app/templates/index.html`

**What it does:** The HTML page served at `/`, with a form for the total and the names, plus a
results table. Flask fills in `{{ url_for(...) }}` with the right paths to the CSS and JS files.

**Why no inline JavaScript/CSS:** The app sends a *Content-Security-Policy* header that only allows
scripts and styles from the app's own files. That blocks injected scripts (XSS), so the JS and CSS
live in `static/`.

**v1 vs v2:** In v2 the footer shows the version and build number, so you can *see* the
Blue-Green switch happen in the browser.
