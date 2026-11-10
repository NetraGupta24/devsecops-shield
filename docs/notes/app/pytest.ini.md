# `app/pytest.ini`

**What it does:** Configures pytest. `pythonpath = .` lets tests `import app` and `import splitter`.
`testpaths = tests` tells pytest where the tests live, and `-ra` prints a short summary of any
skipped or failed tests.

**How it connects:** Jenkins runs `pytest` from the `app/` folder and this file is picked up
automatically.
