#!/usr/bin/env python3
"""Rate-bounded odds fetcher for the MLB widget.

Usage: odds.py <cache-name> <budget-key> <url> <ttl-seconds> <monthly-cap>

Design goal: the user wants odds ONCE, not polled. So every pull is gated
twice:

1. TTL — don't refetch while the cache file is younger than ttl-seconds.
2. Monthly cap — a per-budget-key pull counter for the current calendar
   month; once `cap` pulls are spent, serve whatever is cached (however
   stale) and never hit the network again this month.

The caller derives ttl from the cap (month_seconds / cap) so pulls are
spread *evenly* across the month instead of clumped at the start. Typical:
cap=30 → one pull per day per source; cap=60 → one every ~12h.

Cache lives in $XDG_CACHE_HOME/omarchy-mlb (default ~/.cache), the pull
ledger next to it. A failed network attempt still counts against the month
(it was a real request), but serves stale cache when one exists. Writes are
atomic (tmp + rename) and the ledger is flock'd so the widget's parallel
source fetches can't lose increments.

Prints the raw API body to stdout on success or stale-serve; exits 0 in both
cases (empty stdout = nothing usable, caller keeps last-good data).
"""
import json
import fcntl
import os
import sys
import time
import urllib.request
import urllib.error

STATE = os.path.join(
    os.environ.get("XDG_CACHE_HOME") or os.path.expanduser("~/.cache"),
    "omarchy-mlb",
)
CACHE = os.path.join(STATE, "cache")
LEDGER = os.path.join(STATE, "pulls.json")
UA = "Mozilla/5.0 (X11; Linux x86_64) omarchy-mlb/0.1"
ALLOWED = ("https://", "file://")  # file:// keeps the helper testable offline


def fail(msg):
    sys.stderr.write("odds.py: %s\n" % msg)
    sys.exit(2)


def main():
    if len(sys.argv) < 6:
        fail("usage: odds.py <cache-name> <budget-key> <url> <ttl> <cap>")
    cache_name, budget_key, url = sys.argv[1], sys.argv[2], sys.argv[3]
    try:
        ttl = int(sys.argv[4])
        cap = max(1, int(sys.argv[5]))
    except ValueError:
        fail("ttl and cap must be integers")
    if not url.startswith(ALLOWED):
        fail("url must be https:// or file://")

    os.makedirs(CACHE, exist_ok=True)
    cache_path = os.path.join(CACHE, cache_name + ".body")

    def serve_cache():
        try:
            with open(cache_path, "r", encoding="utf-8") as f:
                sys.stdout.write(f.read())
            return True
        except OSError:
            return False

    month = time.strftime("%Y-%m")
    # Ledger read-modify-write under an exclusive lock: the widget fires the
    # three sources in parallel and an unlocked update would drop increments.
    with open(LEDGER, "a+", encoding="utf-8") as lf:
        fcntl.flock(lf, fcntl.LOCK_EX)
        lf.seek(0)
        try:
            ledger = json.load(lf)
        except (ValueError, OSError):
            ledger = {}
        if not isinstance(ledger, dict) or ledger.get("month") != month:
            ledger = {"month": month}
        used = int(ledger.get(budget_key, 0))

        if used >= cap:
            # Month's budget spent: stale cache beats an empty panel, and the
            # network stays untouched until the month rolls over.
            serve_cache()
            return

        # TTL gate: only spend budget when the cache is old enough.
        try:
            age = time.time() - os.path.getmtime(cache_path)
        except OSError:
            age = None
        if age is not None and age < ttl:
            serve_cache()
            return

        # Spend first: a flapping endpoint must not slip past the cap.
        ledger[budget_key] = used + 1
        lf.seek(0)
        lf.truncate()
        json.dump(ledger, lf)
        lf.flush()

    try:
        req = urllib.request.Request(url, headers={"User-Agent": UA})
        with urllib.request.urlopen(req, timeout=15) as resp:
            body = resp.read().decode("utf-8", "replace")
        json.loads(body)  # reject truncated/garbage before caching
    except (urllib.error.URLError, urllib.error.HTTPError, OSError,
            ValueError, TimeoutError) as e:
        sys.stderr.write("odds.py: fetch failed: %s\n" % e)
        serve_cache()  # stale beats empty
        return

    tmp = cache_path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        f.write(body)
    os.replace(tmp, cache_path)
    sys.stdout.write(body)


if __name__ == "__main__":
    main()
