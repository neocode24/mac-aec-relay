#!/usr/bin/env python3
"""numpy 사용 가능 여부 및 샘플 개수 확인."""
try:
    import numpy as np
    print("numpy", np.__version__)
except ImportError as e:
    print("no numpy:", e)
