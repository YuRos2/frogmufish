import sys
try:
    from PIL import Image
    print("PIL OK", Image.__version__)
except Exception as e:
    print("NO PIL:", e)
