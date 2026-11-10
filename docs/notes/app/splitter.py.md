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

## v2 additions (branch `feature/v2`)
- `to_basis_points("33.33")` gives `3333`. Percentages are stored as whole *basis points*
  (1% = 100 bp, 100% = 10000 bp), so they are also integers with no floating point.
- `split_by_percentage(total, names, basis_points)` uses the **largest remainder method**:
  1. Each exact share is `total × bp / 10000` paise. Everyone first gets the rounded-*down* part.
  2. The few paise left over go, one each, to the people whose share had the **largest fraction cut
     off**. Ties go to whoever is earlier in the list.
  3. Result: the shares add up to the exact total, and each person is within 1 paisa of their exact
     share.
  - Example: Rs 0.10 at 33.33/33.33/33.34% gives exact shares 3.333, 3.333, 3.334 paise. The floors
    are 3, 3, 3 with 1 paisa left over, which goes to C (fraction .334 is the largest): 3, 3, 4.
- `split_by_amount(total, names, amounts)`: everyone pays exactly what was entered, and the amounts
  must add up to the total, otherwise you get a clear error ("The amounts add up to 900.00, but the
  total is 1000.00").
