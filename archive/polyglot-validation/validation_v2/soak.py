"""Swap memory drift calculator for soak testing."""


def calculate_drift(start_free_mb: float, end_free_mb: float) -> float:
    """Calculate swap drift from free swap values.

    Increased SwapFree means less swap is used. Drift is the amount of
    swap *consumed* (positive = leak, negative = freed).

    Args:
        start_free_mb: Swap free space at start (MB).
        end_free_mb: Swap free space at end (MB).

    Returns:
        Positive drift means swap usage increased (leak).
        Negative drift means swap usage decreased (freed).
    """
    return start_free_mb - end_free_mb
