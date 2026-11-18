#!/bin/bash
# True fix: overwrites /app/reconcile.py with a version that resolves all 3 bugs.
cat > /app/reconcile.py <<'PYEOF'
#!/usr/bin/env python3
"""Reconcile payment transactions: read a CSV, print a JSON summary."""
import csv
import json
import sys
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation, ROUND_HALF_UP


def parse_row(row):
    """Return (tx_id, raw_ts, instant, amount, status) or None if malformed."""
    if len(row) != 4:
        return None
    tx_id, ts, amount, status = (c.strip() for c in row)
    if not tx_id:
        return None
    try:
        when = datetime.fromisoformat(ts)
        if when.tzinfo is None:
            when = when.replace(tzinfo=timezone.utc)
        amt = Decimal(amount)
    except (ValueError, InvalidOperation):
        return None
    if not amt.is_finite():
        return None
    return tx_id, ts, when, amt, status


def main():
    if len(sys.argv) != 2:
        print("usage: reconcile.py <transactions.csv>", file=sys.stderr)
        sys.exit(2)

    latest = {}
    with open(sys.argv[1], newline="") as f:
        reader = csv.reader(f)
        next(reader, None)  # skip header
        for row in reader:
            rec = parse_row(row)
            if rec is None:
                continue
            tx_id, ts, when, amt, status = rec
            if tx_id not in latest or when >= latest[tx_id][0]:
                latest[tx_id] = (when, amt, status)

    total = Decimal("0")
    valid = failed = 0
    for _, amt, status in latest.values():
        if status == "VALID":
            valid += 1
            total += amt
        elif status == "FAILED":
            failed += 1

    total = total.quantize(Decimal("0.01"), rounding=ROUND_HALF_UP)
    print(json.dumps({
        "total_valid_amount": float(total),
        "valid_count": valid,
        "failed_count": failed,
    }))


if __name__ == "__main__":
    main()
PYEOF
echo "Done!"
