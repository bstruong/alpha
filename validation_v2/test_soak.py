import sys

from soak import calculate_drift


def test_swap_freed():
    # If we start with 1000MB free, and end with 1300MB free, swap usage went DOWN. Drift is 0 or negative.
    drift = calculate_drift(start_free_mb=1000.0, end_free_mb=1300.0)
    assert drift <= 0.0, f"Drift incorrectly penalized freed memory: {drift}"

def test_swap_leaked():
    # If we start with 1000MB free, and end with 700MB free, swap usage went UP by 300MB.
    drift = calculate_drift(start_free_mb=1000.0, end_free_mb=700.0)
    assert drift == 300.0, f"Drift missed memory leak: {drift}"

if __name__ == "__main__":
    test_swap_freed()
    test_swap_leaked()
    print("All tests passed.")
    sys.exit(0)
