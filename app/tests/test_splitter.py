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
