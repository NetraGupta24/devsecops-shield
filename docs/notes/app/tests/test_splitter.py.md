# `app/tests/test_splitter.py`

**What it tests:** The money maths.
- Valid and invalid amounts (negative, zero, 3 decimals, text, `NaN`, infinity, too large).
- Rounding: Rs 100 / 3 gives 33.34 / 33.33 / 33.33.
- **The key property:** for many totals and group sizes, the shares *always* add up to the exact
  total, and no two people differ by more than 1 paisa.
- Name validation: empty, duplicates (case-insensitive), too long, too many people.

**How it connects:** This is the *Unit tests* stage of the pipeline. If any test fails, Jenkins
stops and nothing is deployed (demo 2).

## v2 additions
Percentage maths (largest remainder, ties, the add-up-to-total property for many totals and
percentage mixes, must add up to 100%) and amount maths (must match the total).
