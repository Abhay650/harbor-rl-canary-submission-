#!/bin/bash
# Dense, randomized, anti-cheat verifier. Writes a reward in [0.00, 1.00].
#   0.20  check 1: clean data (VALID/FAILED, unique ids, UTC)           -> base CLI works
#   0.30  check 2: adds PENDING rows (status filtering)
#   0.50  check 3: duplicate tx_ids across timezones + malformed rows
mkdir -p /logs/verifier
rm -f /logs/verifier/reward.txt

python3 - <<'PYEOF'
import json, os, random, re, subprocess, sys, tempfile, shutil
from datetime import datetime, timedelta, timezone
from decimal import Decimal, ROUND_HALF_UP

SCRIPT = "/app/reconcile.py"
REWARD = "/logs/verifier/reward.txt"
WEIGHTS = {"basic": 0.20, "status": 0.30, "dedupe": 0.50}
N_CASES = 4  # every random case must pass for a check to earn its weight
rng = random.Random(int.from_bytes(os.urandom(16), "big"))  # fresh each run


def write_reward(x):
    with open(REWARD, "w") as f:
        f.write(f"{x:.2f}\n")


# ---- anti-tamper: the script must be a real, self-contained program ----------
try:
    src = open(SCRIPT).read()
except OSError:
    write_reward(0.0); sys.exit(0)
if re.search(r"/logs|/tests|reward\.txt|verifier", src):
    print("TAMPER: script references verifier paths"); write_reward(0.0); sys.exit(0)
if subprocess.run([sys.executable, "-m", "py_compile", SCRIPT],
                  capture_output=True).returncode != 0:
    print("script does not compile"); write_reward(0.0); sys.exit(0)


# ---- independent reference implementation ------------------------------------
def reference(rows):
    latest = {}
    for r in rows:
        if len(r) != 4:
            continue
        tx, ts, amt, st = (c.strip() for c in r)
        if not tx:
            continue
        try:
            when = datetime.fromisoformat(ts)
            a = Decimal(amt)
        except Exception:
            continue
        if not a.is_finite():
            continue
        if when.tzinfo is None:
            when = when.replace(tzinfo=timezone.utc)
        if tx not in latest or when >= latest[tx][0]:
            latest[tx] = (when, a, st)
    total, v, f = Decimal(0), 0, 0
    for _, a, st in latest.values():
        if st == "VALID":
            v += 1; total += a
        elif st == "FAILED":
            f += 1
    return {"total_valid_amount": float(total.quantize(Decimal("0.01"), ROUND_HALF_UP)),
            "valid_count": v, "failed_count": f}


# ---- random data generators ---------------------------------------------------
def fmt(dt_utc, off_h, off_m=0):
    off = timezone(timedelta(hours=off_h, minutes=off_m if off_h >= 0 else -off_m))
    s = dt_utc.astimezone(off).isoformat()
    return s.replace("+00:00", "Z") if (off_h == 0 and off_m == 0 and rng.random() < .5) else s


def rand_instant():
    return datetime(2024, 1, 1, tzinfo=timezone.utc) + timedelta(minutes=rng.randrange(0, 60 * 24 * 300))


def rand_amount():
    return f"{rng.randrange(1, 999999) / 100:.2f}"


def new_id(used):
    while True:
        t = f"TX{rng.randrange(10**6):06d}"
        if t not in used:
            used.add(t); return t


def gen_basic(statuses):
    used, rows = set(), []
    for _ in range(rng.randint(8, 30)):
        rows.append([new_id(used), fmt(rand_instant(), 0), rand_amount(), rng.choice(statuses)])
    return rows


def gen_dedupe():
    used, rows = set(), gen_basic(["VALID", "FAILED", "PENDING"])
    used.update(r[0] for r in rows)
    # Trap pairs: the EARLIER instant has a LATER local-clock string (bigger +offset).
    for _ in range(rng.randint(3, 6)):
        tx, late = new_id(used), rand_instant()
        early = late - timedelta(minutes=rng.randint(10, 120))
        e = [tx, fmt(early, rng.choice([5, 8, 10, 12, 14]), rng.choice([0, 30])),
             rand_amount(), rng.choice(["VALID", "FAILED", "PENDING"])]
        l = [tx, fmt(late, rng.choice([0, -3, -5, -8])), rand_amount(),
             rng.choice(["VALID", "FAILED", "PENDING"])]
        rows += [e, l] if rng.random() < .5 else [l, e]
    # Exact-instant tie in different notations: later row in file wins.
    tx, t = new_id(used), rand_instant()
    rows += [[tx, fmt(t, 0), rand_amount(), "FAILED"], [tx, fmt(t, 5, 30), rand_amount(), "VALID"]]
    # Same-offset retries.
    for _ in range(rng.randint(1, 3)):
        tx, t = new_id(used), rand_instant()
        rows += [[tx, fmt(t, 0), rand_amount(), "FAILED"],
                 [tx, fmt(t + timedelta(minutes=rng.randint(1, 500)), 0), rand_amount(), "VALID"]]
    # Malformed rows, including ones that reuse a real tx_id with a *later* timestamp.
    real = [r[0] for r in rows]
    for _ in range(rng.randint(3, 6)):
        tx = rng.choice(real)
        rows.append(rng.choice([
            [tx, "2030-01-01T00:00:00Z", "N/A", "VALID"],
            [tx, "not-a-time", rand_amount(), "VALID"],
            [tx, "2030-01-01T00:00:00Z", "nan", "VALID"],
            ["", fmt(rand_instant(), 0), rand_amount(), "VALID"],
            [tx, "2030-01-01T00:00:00Z", rand_amount()],
            [tx, "2030-01-01T00:00:00Z", rand_amount(), "VALID", "extra"],
        ]))
    rng.shuffle(rows)
    return rows


# ---- run the candidate on one dataset ----------------------------------------
def run_case(rows):
    d = tempfile.mkdtemp(prefix="v_")
    try:
        path = os.path.join(d, f"in_{rng.randrange(10**6)}.csv")
        with open(path, "w", newline="") as f:
            f.write("tx_id,timestamp,amount,status\n")
            for r in rows:
                f.write(",".join(r) + "\n")
        p = subprocess.run([sys.executable, SCRIPT, path], cwd=d, capture_output=True,
                           text=True, timeout=15, env={"PATH": os.environ.get("PATH", "")})
        if p.returncode != 0:
            return False
        out = json.loads(p.stdout)
        exp = reference(rows)
        return (set(out) == set(exp)
                and isinstance(out["valid_count"], int) and isinstance(out["failed_count"], int)
                and out["valid_count"] == exp["valid_count"]
                and out["failed_count"] == exp["failed_count"]
                and abs(float(out["total_valid_amount"]) - exp["total_valid_amount"]) < 1e-6)
    except Exception:
        return False
    finally:
        shutil.rmtree(d, ignore_errors=True)


def check(gen):
    return all(run_case(gen()) for _ in range(N_CASES))


results = {
    "basic": check(lambda: gen_basic(["VALID", "FAILED"])),
    "status": check(lambda: gen_basic(["VALID", "FAILED", "PENDING"])),
    "dedupe": check(gen_dedupe),
}
# Usage check: no args must fail non-zero (guards against "always succeed" stubs).
u = subprocess.run([sys.executable, SCRIPT], capture_output=True, text=True)
results["usage"] = u.returncode != 0 and u.stdout.strip() == ""
if not results["usage"]:
    results["basic"] = False

score = sum(WEIGHTS[k] for k in WEIGHTS if results[k])
print(results, "->", f"{score:.2f}")
write_reward(score)
PYEOF

[ -f /logs/verifier/reward.txt ] || echo "0.00" > /logs/verifier/reward.txt
