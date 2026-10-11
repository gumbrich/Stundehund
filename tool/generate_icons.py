"""Generate native app icons from simple geometric artwork. Requires Pillow."""
from pathlib import Path
from PIL import Image, ImageDraw

size = 1024
image = Image.new('RGBA', (size, size))
draw = ImageDraw.Draw(image)
draw.rounded_rectangle((12, 12, 1012, 1012), radius=220, fill='#202c3c')
# A warm paw mark, with a small clock on its pad.
for bounds in [(210, 330, 360, 540), (350, 175, 495, 410), (530, 175, 675, 410), (680, 330, 830, 540)]:
    draw.ellipse(bounds, fill='#f4bd83')
draw.ellipse((300, 460, 730, 850), fill='#f4bd83')
draw.rounded_rectangle((500, 525, 525, 660), radius=12, fill='#202c3c')
draw.line((512, 655, 610, 710), fill='#202c3c', width=26)
draw.ellipse((493, 638, 531, 676), fill='#202c3c')
image.save('windows/runner/resources/app_icon.ico', sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
for n in [16, 32, 64, 128, 256, 512, 1024]:
    image.resize((n, n), Image.Resampling.LANCZOS).save(f'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{n}.png')
Path('docs').mkdir(exist_ok=True)
image.resize((256, 256), Image.Resampling.LANCZOS).save('docs/icon.png')
