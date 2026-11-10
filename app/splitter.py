"""Bill-splitting maths for SplitEase.

All money is handled as whole paise (1 rupee = 100 paise) using integers.
Floating point numbers are never used for money, because 0.1 + 0.2 != 0.3
in floating point and the shares would not add up exactly.
"""

from decimal import Decimal, InvalidOperation

MAX_PEOPLE = 50
MAX_NAME_LENGTH = 40
MAX_TOTAL_PAISE = 100_000_000 * 100  # Rs 10 crore is plenty for a bill


class SplitError(ValueError):
    """Invalid input. The message is safe to show to the user."""


def to_paise(amount, field="Total"):
    """Convert a rupee amount such as "1250.50", 1250.5 or 1250 into paise (125050)."""
    if amount is None or isinstance(amount, bool):
        raise SplitError(f"{field} must be a number, for example 1250.50")
    try:
        value = Decimal(str(amount).strip())
    except InvalidOperation:
        raise SplitError(f"{field} must be a number, for example 1250.50") from None
    if not value.is_finite():
        raise SplitError(f"{field} must be a number, for example 1250.50")
    if value <= 0:
        raise SplitError(f"{field} must be greater than zero")
    if value * 100 > MAX_TOTAL_PAISE:
        raise SplitError(f"{field} is too large")
    if value != value.quantize(Decimal("0.01")):
        raise SplitError(f"{field} can have at most 2 decimal places")
    return int(value * 100)


def format_paise(paise):
    """Turn 125050 paise back into the string "1250.50"."""
    return f"{paise // 100}.{paise % 100:02d}"


def clean_names(names):
    """Validate the list of people and return the names with spaces trimmed."""
    if not isinstance(names, list):
        raise SplitError("People must be a list of names")
    cleaned = []
    seen = set()
    for name in names:
        if not isinstance(name, str) or not name.strip():
            raise SplitError("Every person needs a name")
        name = name.strip()
        if len(name) > MAX_NAME_LENGTH:
            raise SplitError(f"Names can be at most {MAX_NAME_LENGTH} characters")
        if name.lower() in seen:
            raise SplitError(f"The name '{name}' appears twice")
        seen.add(name.lower())
        cleaned.append(name)
    if not cleaned:
        raise SplitError("Add at least one person")
    if len(cleaned) > MAX_PEOPLE:
        raise SplitError(f"At most {MAX_PEOPLE} people can share a bill")
    return cleaned


def split_equal(total_paise, names):
    """Split total_paise equally between names.

    If the total does not divide exactly, the leftover paise (always fewer
    than the number of people) are handed out one each to the first people
    in the list, so the shares always add up to the exact total.
    Example: Rs 100.00 between 3 people -> 33.34, 33.33, 33.33
    """
    base, remainder = divmod(total_paise, len(names))
    return [(name, base + (1 if i < remainder else 0)) for i, name in enumerate(names)]
