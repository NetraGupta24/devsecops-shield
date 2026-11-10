"""Unit tests for the money maths in splitter.py."""

import pytest

from splitter import MAX_PEOPLE, SplitError, clean_names, format_paise, split_equal, to_paise


# ---- converting rupees to paise ------------------------------------------

@pytest.mark.parametrize(
    "amount, expected",
    [("100", 10000), ("1250.50", 125050), ("0.01", 1), (99.99, 9999), (5, 500), (" 12.5 ", 1250), ("10.500", 1050)],
)
def test_to_paise_valid(amount, expected):
    assert to_paise(amount) == expected


@pytest.mark.parametrize("amount", ["abc", "", None, True, "-5", "0", "0.00", "12.345", "nan", "inf", "1e20", [], {}])
def test_to_paise_invalid(amount):
    with pytest.raises(SplitError):
        to_paise(amount)


def test_format_paise():
    assert format_paise(125050) == "1250.50"
    assert format_paise(5) == "0.05"
    assert format_paise(100) == "1.00"


# ---- equal split and rounding ---------------------------------------------

def test_equal_split_exact():
    assert split_equal(30000, ["A", "B", "C"]) == [("A", 10000), ("B", 10000), ("C", 10000)]


def test_equal_split_rounding_remainder_goes_to_first_people():
    # Rs 100.00 / 3 = 33.333... -> one leftover paisa goes to the first person
    assert split_equal(10000, ["A", "B", "C"]) == [("A", 3334), ("B", 3333), ("C", 3333)]


def test_equal_split_two_leftover_paise():
    # Rs 0.05 / 3 -> 2, 2, 1 paise
    assert split_equal(5, ["A", "B", "C"]) == [("A", 2), ("B", 2), ("C", 1)]


def test_more_people_than_paise():
    # Rs 0.02 between 3 people: somebody pays nothing, but the total is still exact
    assert split_equal(2, ["A", "B", "C"]) == [("A", 1), ("B", 1), ("C", 0)]


@pytest.mark.parametrize("total", [1, 7, 999, 10000, 123457, 99999999])
@pytest.mark.parametrize("people", [1, 2, 3, 7, 13, MAX_PEOPLE])
def test_shares_always_add_up_to_total(total, people):
    names = [f"P{i}" for i in range(people)]
    shares = split_equal(total, names)
    assert sum(p for _, p in shares) == total
    # nobody pays more than 1 paisa more than anybody else
    amounts = [p for _, p in shares]
    assert max(amounts) - min(amounts) <= 1


# ---- validating names -------------------------------------------------------

def test_clean_names_trims_spaces():
    assert clean_names(["  Asha ", "Ben"]) == ["Asha", "Ben"]


@pytest.mark.parametrize(
    "names",
    [[], "Asha,Ben", None, ["Asha", ""], ["Asha", "   "], ["Asha", 5], ["Asha", "asha"], ["x" * 41],
     [f"P{i}" for i in range(MAX_PEOPLE + 1)]],
)
def test_clean_names_invalid(names):
    with pytest.raises(SplitError):
        clean_names(names)


# ---- v2: percentage split -------------------------------------------------

from splitter import split_by_amount, split_by_percentage, to_basis_points  # noqa: E402


def test_to_basis_points():
    assert to_basis_points("33.33", "p") == 3333
    assert to_basis_points(50, "p") == 5000
    assert to_basis_points("0", "p") == 0


@pytest.mark.parametrize("value", ["-1", "100.01", "33.333", "abc", None, True])
def test_to_basis_points_invalid(value):
    with pytest.raises(SplitError):
        to_basis_points(value, "p")


def test_percentage_split_exact():
    assert split_by_percentage(100000, ["A", "B"], [6000, 4000]) == [("A", 60000), ("B", 40000)]


def test_percentage_split_largest_remainder():
    # Rs 100.00 at 33.33 / 33.33 / 33.34 % -> exact 3333, 3333, 3334 paise
    assert split_by_percentage(10000, ["A", "B", "C"], [3333, 3333, 3334]) == [("A", 3333), ("B", 3333), ("C", 3334)]
    # Rs 0.10 at 33.33/33.33/33.34 % -> exact 3.333, 3.333, 3.334 -> floors 3,3,3, leftover 1
    # goes to C (largest cut-off fraction .334)
    assert split_by_percentage(10, ["A", "B", "C"], [3333, 3333, 3334]) == [("A", 3), ("B", 3), ("C", 4)]


def test_percentage_split_tie_goes_to_first_person():
    # Rs 0.01 at 50/50 -> exact 0.5 each; the single paisa goes to the first person
    assert split_by_percentage(1, ["A", "B"], [5000, 5000]) == [("A", 1), ("B", 0)]


@pytest.mark.parametrize("total", [1, 7, 999, 10000, 123457, 99999999])
@pytest.mark.parametrize("points", [[10000], [5000, 5000], [3333, 3333, 3334], [1, 9999], [2500, 2500, 2500, 2500], [0, 10000]])
def test_percentage_shares_always_add_up(total, points):
    names = [f"P{i}" for i in range(len(points))]
    assert sum(p for _, p in split_by_percentage(total, names, points)) == total


def test_percentage_must_add_up_to_100():
    with pytest.raises(SplitError, match="add up to 100"):
        split_by_percentage(10000, ["A", "B"], [5000, 4000])


# ---- v2: amount split -------------------------------------------------------

def test_amount_split():
    assert split_by_amount(100000, ["A", "B"], [70000, 30000]) == [("A", 70000), ("B", 30000)]


def test_amount_split_must_match_total():
    with pytest.raises(SplitError, match="add up to 900.00"):
        split_by_amount(100000, ["A", "B"], [60000, 30000])
