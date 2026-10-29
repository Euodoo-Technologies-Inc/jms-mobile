"""Recolor assets/images/logo.png — shift the saturated purple/blue pin to the
app theme's accent yellow (#e8e241) while leaving the dark background untouched.

Saturation is used as a soft blend mask: vivid pixels (the pin, the speed dots
and lines) take the target hue; near-grey pixels (the dark rounded-square
background and the pin's dark centre) keep their original hue, so the dark
backdrop stays dark. The original is backed up to logo_original.png first.
"""

import colorsys
import os

from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
ASSET = os.path.join(HERE, "..", "assets", "images", "logo.png")
BACKUP = os.path.join(HERE, "..", "assets", "images", "logo_original.png")

# Target accent yellow #e8e241 -> its hue, as a 0..255 channel value.
_r, _g, _b = (0xE8 / 255, 0xE2 / 255, 0x41 / 255)
TARGET_HUE = round(colorsys.rgb_to_hsv(_r, _g, _b)[0] * 255)

# Always work from the pristine original so the script is re-runnable.
if os.path.exists(BACKUP):
    src = Image.open(BACKUP).convert("RGBA")
else:
    src = Image.open(ASSET).convert("RGBA")
    src.save(BACKUP)

alpha = src.getchannel("A")
h, s, v = src.convert("RGB").convert("HSV").split()

# Near-binary saturation mask: vivid pixels (pin, dots, lines) -> recolour;
# near-grey pixels (dark background, pin's dark centre) -> keep. Hue is
# circular, so blending it numerically would pass through green — we want a
# hard pick of the target hue, with only a 1px feather to anti-alias edges.
mask = s.point(lambda x: 255 if x > 60 else 0).filter(
    ImageFilter.GaussianBlur(0.8)
)

# Recoloured pixels take the pure target hue; everything else keeps its own.
yellow_h = Image.new("L", src.size, TARGET_HUE)
new_h = Image.composite(yellow_h, h, mask)

# Lift saturation a touch on the recoloured pin so the yellow reads as vivid
# as the theme swatch.
boosted_s = s.point(lambda x: min(255, int(x * 1.15)))
new_s = Image.composite(boosted_s, s, mask)

out = Image.merge("HSV", (new_h, new_s, v)).convert("RGBA")
out.putalpha(alpha)
out.save(ASSET)
print(f"Recolored {ASSET} -> hue {TARGET_HUE}/255 (backup at {BACKUP})")
