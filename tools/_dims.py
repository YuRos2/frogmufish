import bpy, os
P = os.environ.get("MOKUGYO_PICTURES", os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
    "reference_photos"))
for f in sorted(os.listdir(P)):
    if f.lower().endswith((".jpg", ".png")):
        try:
            img = bpy.data.images.load(os.path.join(P, f))
            print("DIM %-20s %d x %d" % (f, img.size[0], img.size[1]))
            bpy.data.images.remove(img)
        except Exception as e:
            print("ERR", f, e)
