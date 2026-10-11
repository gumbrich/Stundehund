"""Build the dog-and-clock vector mark and native icons. Requires Pillow."""
from pathlib import Path
from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parent.parent
SIZE = 2048
SCALE = SIZE / 256
NAVY = '#202c3c'
AMBER = '#f4bd83'
CREAM = '#fff8eb'

# A single side-profile silhouette: raised tail, long body, floppy ear,
# two visible legs, and a projecting muzzle. Coordinates use a 256px viewBox.
DOG = [
    ('M', 72, 117), ('C', 60, 117, 52, 129, 52, 145),
    ('L', 52, 182), ('Q', 52, 194, 65, 194),
    ('L', 84, 194), ('L', 84, 182), ('L', 75, 182),
    ('L', 75, 164), ('L', 149, 164), ('L', 149, 182),
    ('Q', 149, 194, 162, 194), ('L', 182, 194),
    ('L', 182, 182), ('L', 172, 182), ('L', 172, 153),
    ('C', 180, 144, 185, 130, 184, 117), ('L', 198, 117),
    ('C', 217, 117, 228, 108, 228, 95), ('L', 228, 86),
    ('L', 206, 86), ('L', 199, 72),
    ('C', 190, 57, 172, 53, 156, 61),
    ('C', 142, 68, 136, 83, 139, 99), ('L', 142, 117), ('Z',),
]
TAIL = [('M', 63, 132), ('C', 45, 128, 32, 115, 28, 94)]
EAR = [('M', 164, 70), ('C', 157, 79, 155, 95, 163, 106)]


def points(commands):
    """Flatten vector curves at high resolution for the Pillow rasterizer."""
    result = []
    current = (0, 0)
    first = None
    for op, *args in commands:
        if op in ('M', 'L'):
            current = tuple(args)
            first = first or current
            result.append(current)
        elif op in ('C', 'Q'):
            start = current
            controls = list(zip(args[::2], args[1::2]))
            for i in range(1, 65):
                t = i / 64
                u = 1 - t
                if op == 'C':
                    a, b, end = controls
                    point = tuple(u**3 * start[j] + 3*u*u*t*a[j] + 3*u*t*t*b[j] + t**3*end[j] for j in (0, 1))
                else:
                    a, end = controls
                    point = tuple(u*u*start[j] + 2*u*t*a[j] + t*t*end[j] for j in (0, 1))
                result.append(point)
            current = controls[-1]
        elif op == 'Z':
            result.append(first)
    return [(round(x*SCALE), round(y*SCALE)) for x, y in result]


def svg_path(commands):
    return ' '.join(' '.join(map(str, command)) for command in commands)


def ellipse(draw, bounds, fill):
    draw.ellipse(tuple(round(v*SCALE) for v in bounds), fill=fill)


def stroke(draw, path, width, fill):
    coords = points(path)
    draw.line(coords, fill=fill, width=round(width*SCALE), joint='curve')
    radius = width*SCALE/2
    for x, y in (coords[0], coords[-1]):
        draw.ellipse((round(x-radius), round(y-radius), round(x+radius), round(y+radius)), fill=fill)


image = Image.new('RGBA', (SIZE, SIZE))
draw = ImageDraw.Draw(image)
draw.rounded_rectangle(tuple(round(v*SCALE) for v in (3, 3, 253, 253)), radius=round(55*SCALE), fill=AMBER)
stroke(draw, TAIL, 15, NAVY)
draw.polygon(points(DOG), fill=NAVY)
stroke(draw, EAR, 6, AMBER)
ellipse(draw, (189, 77, 197, 85), AMBER)
# Uncluttered clock: a plain face and just two rounded hands.
ellipse(draw, (82, 111, 138, 167), CREAM)
stroke(draw, [('M', 110, 123), ('L', 110, 139), ('L', 122, 145)], 5, NAVY)

icon = image.resize((1024, 1024), Image.Resampling.LANCZOS)
icon.save(ROOT / 'windows/runner/resources/app_icon.ico', sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
for size in (16, 32, 64, 128, 256, 512, 1024):
    image.resize((size, size), Image.Resampling.LANCZOS).save(ROOT / f'macos/Runner/Assets.xcassets/AppIcon.appiconset/app_icon_{size}.png')
for folder in ('assets', 'docs'):
    (ROOT / folder).mkdir(exist_ok=True)
image.resize((256, 256), Image.Resampling.LANCZOS).save(ROOT / 'assets/stundehund.png')
image.resize((256, 256), Image.Resampling.LANCZOS).save(ROOT / 'docs/icon.png')
svg = f'''<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 256 256">
  <title>Stundehund: dog in profile with a clock</title>
  <rect x="3" y="3" width="250" height="250" rx="55" fill="{AMBER}"/>
  <path d="{svg_path(TAIL)}" fill="none" stroke="{NAVY}" stroke-width="15" stroke-linecap="round"/>
  <path d="{svg_path(DOG)}" fill="{NAVY}"/>
  <path d="{svg_path(EAR)}" fill="none" stroke="{AMBER}" stroke-width="6" stroke-linecap="round"/>
  <circle cx="193" cy="81" r="4" fill="{AMBER}"/>
  <circle cx="110" cy="139" r="28" fill="{CREAM}"/>
  <path d="M110 123 V139 L122 145" fill="none" stroke="{NAVY}" stroke-width="5" stroke-linecap="round" stroke-linejoin="round"/>
</svg>
'''
(ROOT / 'docs/stundehund.svg').write_text(svg)
print('Generated dog-and-clock icon: Windows ICO, macOS iconset, in-app PNG, and SVG source.')
