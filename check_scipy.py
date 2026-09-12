#!/usr/bin/env python3
"""check_scipy.py — scipy 사용 가능 여부."""
try:
    import scipy
    print("scipy", scipy.__version__)
except ImportError as e:
    print("no scipy:", e)
