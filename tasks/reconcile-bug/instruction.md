# Fix the payment reconciler

`/app/reconcile.py` is a small CLI that reads a CSV of payment transactions and prints a JSON summary. It is currently broken. Make it behave as specified below by editing `/app/reconcile.py` in place.

## Usage

```
python3 /app/reconcile.py <transactions.csv>
```

Print exactly one line of JSON to stdout and exit with status 0. With a wrong number of arguments, print a usage message to stderr and exit non-zero.

## Input

A CSV file with a header row followed by data rows with these columns:

`tx_id,timestamp,amount,status`

- `tx_id`: transaction identifier (string).
- `timestamp`: ISO 8601 with a UTC offset, e.g. `2024-03-01T10:00:00Z` or `2024-03-01T15:30:00+05:30`. A timestamp with no offset is treated as UTC.
- `amount`: decimal number, e.g. `120.50`.
- `status`: one of `VALID`, `FAILED`, `PENDING`.

## Output

```
{"total_valid_amount": 123.45, "valid_count": 3, "failed_count": 1}
```

## Business rules

1. A `tx_id` may appear on more than one row (retries and status updates). Only the most recent row for each `tx_id` counts, where "most recent" is the row whose timestamp is the latest actual moment in time, taking the UTC offset into account. If two rows for the same `tx_id` have exactly the same moment in time, the one that appears later in the file wins.
2. After that, for the surviving rows:
   - `valid_count` is the number of `VALID` transactions and `total_valid_amount` is the sum of their amounts, rounded to 2 decimal places (round half up).
   - `failed_count` is the number of `FAILED` transactions.
   - `PENDING` transactions are not counted anywhere.
3. A malformed row is skipped entirely, as if it were not in the file. A row is malformed if it does not have exactly 4 fields, has an empty `tx_id`, has an amount that is not a finite decimal number, or has a timestamp that cannot be parsed. A skipped row never replaces or affects any other row.
