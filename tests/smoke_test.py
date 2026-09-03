"""
tests/smoke_test.py
--------------------
Container-level smoke test. Unlike test_api.py (which talks to the Flask
test client in-process), this script sends real HTTP requests over the
network to a *running container*. The GitHub Actions pipeline starts the
built image, waits for /health to go green, then runs this script before
the image is allowed to be published/rolled out.

Usage:
    python tests/smoke_test.py --host http://localhost:8000
Exit code 0 = all checks passed, non-zero = failure (fails the pipeline).
"""
import argparse
import sys
import time

import requests

VALID_FEATURES = {
    "alcohol": 13.2, "malic_acid": 1.78, "ash": 2.14, "alcalinity_of_ash": 11.2,
    "magnesium": 100.0, "total_phenols": 2.65, "flavanoids": 2.76,
    "nonflavanoid_phenols": 0.26, "proanthocyanins": 1.28, "color_intensity": 4.38,
    "hue": 1.05, "od280/od315_of_diluted_wines": 3.4, "proline": 1050.0,
}


def wait_for_health(base_url, timeout=30):
    deadline = time.time() + timeout
    last_err = None
    while time.time() < deadline:
        try:
            r = requests.get(f"{base_url}/health", timeout=2)
            if r.status_code == 200 and r.json().get("status") == "healthy":
                return True
        except requests.RequestException as exc:
            last_err = exc
        time.sleep(1)
    print(f"Service never became healthy: {last_err}")
    return False


def run(base_url):
    checks = []

    ok = wait_for_health(base_url)
    checks.append(("health check reachable", ok))
    if not ok:
        return checks

    r = requests.post(f"{base_url}/predict", json={"features": VALID_FEATURES}, timeout=5)
    checks.append(("predict valid payload -> 200", r.status_code == 200))
    checks.append(("predict response has prediction", "prediction" in r.json()))

    r_bad = requests.post(f"{base_url}/predict", json={"features": {"alcohol": 1.0}}, timeout=5)
    checks.append(("predict incomplete payload -> 400", r_bad.status_code == 400))

    r_ver = requests.get(f"{base_url}/version", timeout=5)
    checks.append(("version endpoint -> 200", r_ver.status_code == 200))

    return checks


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--host", default="http://localhost:8000")
    args = parser.parse_args()

    results = run(args.host)
    failed = [name for name, passed in results if not passed]

    for name, passed in results:
        print(f"[{'PASS' if passed else 'FAIL'}] {name}")

    if failed:
        print(f"\n{len(failed)} smoke check(s) failed.")
        sys.exit(1)
    print(f"\nAll {len(results)} smoke checks passed.")
    sys.exit(0)
