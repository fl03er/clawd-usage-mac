"""Frames from the app's recorder (CLAWD_RECORD) -> an animated GIF, and image grids.

  python3 make_gif.py gif <frames dir> <out.gif> [crop_height_px]
  python3 make_gif.py grid <out.png> <columns> <label=image.png>...  [--crop x,y,w,h]
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFont


def make_gif(src, out, crop_h=None):
    names = sorted(n for n in os.listdir(src) if n.endswith(".png"))
    times = [float(t) for t in open(os.path.join(src, "times.txt")).read().split()]
    frames = []
    for n in names:
        im = Image.open(os.path.join(src, n)).convert("RGBA")
        if crop_h:
            im = im.crop((0, 0, im.width, min(im.height, crop_h)))
        # The widget has rounded corners: flatten on a dark background.
        bg = Image.new("RGBA", im.size, (13, 17, 23, 255))
        bg.alpha_composite(im)
        frames.append(bg.convert("RGB"))
    # One shared palette, so colours do not flicker between frames.
    pal = frames[len(frames) // 2].quantize(colors=255, method=Image.Quantize.MEDIANCUT)
    q = [f.quantize(palette=pal, dither=Image.Dither.NONE) for f in frames]
    n = min(len(q), len(times))
    durations = [max(20, int(round((times[i + 1] - times[i]) * 1000))) for i in range(n - 1)] + [600]
    q[0].save(out, save_all=True, append_images=q[1:n], duration=durations, loop=0, optimize=True, disposal=1)
    print(out, n, "frames", os.path.getsize(out) // 1024, "KB")


def make_grid(out, cols, items, crop=None):
    ims = []
    for label, path in items:
        im = Image.open(path).convert("RGBA")
        if crop:
            x, y, w, h = crop
            im = im.crop((x, y, x + w, y + h))
        ims.append((label, im))
    w = max(im.width for _, im in ims)
    h = max(im.height for _, im in ims)
    gap, lab = 24, 44
    rows = (len(ims) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * w + (cols + 1) * gap, rows * (h + lab) + (rows + 1) * gap), (13, 17, 23, 255))
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Helvetica.ttc", 26)
    except OSError:
        font = ImageFont.load_default()
    d = ImageDraw.Draw(sheet)
    for i, (label, im) in enumerate(ims):
        cx = gap + (i % cols) * (w + gap)
        cy = gap + (i // cols) * (h + lab + gap)
        sheet.alpha_composite(im, (cx + (w - im.width) // 2, cy))
        tw = d.textlength(label, font=font)
        d.text((cx + (w - tw) / 2, cy + h + 8), label, fill=(201, 209, 217), font=font)
    sheet.convert("RGB").save(out, optimize=True)
    print(out, sheet.size)


if __name__ == "__main__":
    if sys.argv[1] == "gif":
        make_gif(sys.argv[2], sys.argv[3], int(sys.argv[4]) if len(sys.argv) > 4 else None)
    else:
        args = sys.argv[4:]
        crop = None
        if "--crop" in args:
            i = args.index("--crop")
            crop = tuple(int(v) for v in args[i + 1].split(","))
            args = args[:i] + args[i + 2:]
        make_grid(sys.argv[2], int(sys.argv[3]), [a.split("=", 1) for a in args], crop)
