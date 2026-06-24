import os
import re
import glob
import pandas as pd
import numpy as np
from PIL import Image
import imageio.v2 as imageio

# ==========================================
# 参数
# ==========================================

WIDTH = 640
HEIGHT = 480

FPS = 10

OUTPUT_MP4 = "PocketScope_Waveform.mp4"

PNG_DIR = "png_frames"

KEEP_PNG = True

# ==========================================
# 创建目录
# ==========================================

os.makedirs(PNG_DIR, exist_ok=True)

# ==========================================
# 自动寻找 frame*.csv
# ==========================================

csv_files = glob.glob("frame*.csv")

if len(csv_files) == 0:
    print("ERROR: 未找到 frame*.csv")
    exit()

# ==========================================
# 按数字排序
# frame0.csv
# frame1.csv
# frame10.csv
# ==========================================

def frame_number(filename):

    m = re.search(r"frame(\d+)\.csv", filename)

    if m:
        return int(m.group(1))

    return -1

csv_files.sort(key=frame_number)

print("")
print("====================================")
print("FOUND CSV FILES")
print("====================================")

for f in csv_files:
    print(f)

print("====================================")
print("")

# ==========================================
# CSV -> PNG
# ==========================================

png_files = []

for csv_file in csv_files:

    print(f"Processing {csv_file}")

    df = pd.read_csv(csv_file)

    img = np.zeros(
        (HEIGHT, WIDTH, 3),
        dtype=np.uint8
    )

    for row in df.itertuples():

        x = int(row.x)
        y = int(row.y)

        if (
            x < 0 or x >= WIDTH
            or
            y < 0 or y >= HEIGHT
        ):
            continue

        img[y, x] = [
            int(row.r),
            int(row.g),
            int(row.b)
        ]

    frame_idx = frame_number(csv_file)

    png_file = os.path.join(
        PNG_DIR,
        f"frame{frame_idx}.png"
    )

    Image.fromarray(img).save(png_file)

    png_files.append(png_file)

    print(f"Saved {png_file}")

# ==========================================
# PNG -> MP4
# ==========================================

print("")
print("Generating MP4...")
print("")

writer = imageio.get_writer(
    OUTPUT_MP4,
    fps=FPS
)

for png_file in png_files:

    image = imageio.imread(png_file)

    writer.append_data(image)

writer.close()

print("")
print("====================================")
print("MP4 GENERATED")
print(OUTPUT_MP4)
print("====================================")
print("")

# ==========================================
# 删除临时PNG
# ==========================================

if not KEEP_PNG:

    print("Removing PNG files...")

    for png_file in png_files:

        os.remove(png_file)

    try:
        os.rmdir(PNG_DIR)
    except:
        pass

    print("PNG files removed")
