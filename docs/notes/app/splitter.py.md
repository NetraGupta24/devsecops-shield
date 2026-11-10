# `app/splitter.py`

**What it does:** All the money maths, kept separate from the web code so it is easy to test.
- `to_paise("1250.50")` returns `125050`. It validates the amount: must be a number, greater than
  zero, at most 2 decimals, not too large.
- `split_equal(total, names)` splits the paise equally.
- `clean_names()` validates the people list: not empty, no duplicates, at most 50 people.

**Why paise (integers)?** Computers store decimals like 0.1 inexactly (floating point), so
`0.1 + 0.2 = 0.30000000000000004`. Integers are exact. `Decimal` is used only to *read* the input
safely.

**Rounding rule:** Rs 100 / 3 = 3333.33 paise each. `divmod(10000, 3)` gives `3333` with remainder
`1`, and that one leftover paisa goes to the first person. Result: 33.34 + 33.33 + 33.33 = 100.00
exactly. The leftover is always smaller than the number of people, so nobody pays more than 1 paisa
more than anyone else.

**How it connects:** `app.py` calls these functions, and `tests/test_splitter.py` tests them.
