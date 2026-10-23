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

# Selectable in-app / running-window icons share the same simple clock mark.
animal_dir = ROOT / 'assets/animals'
animal_dir.mkdir(exist_ok=True)

def save_animal(name, artwork):
    artwork.resize((256, 256), Image.Resampling.LANCZOS).save(animal_dir / f'{name}.png')
    artwork.resize((1024, 1024), Image.Resampling.LANCZOS).save(animal_dir / f'{name}.ico', sizes=[(16, 16), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])

def canvas(background):
    artwork = Image.new('RGBA', (SIZE, SIZE))
    pen = ImageDraw.Draw(artwork)
    pen.rounded_rectangle(tuple(round(v*SCALE) for v in (3, 3, 253, 253)), radius=round(55*SCALE), fill=background)
    return artwork, pen

def clock_mark(pen, x, y, r):
    ellipse(pen, (x-r, y-r, x+r, y+r), CREAM)
    stroke(pen, [('M', x, y-r*0.55), ('L', x, y), ('L', x+r*0.45, y+r*0.23)], 5, NAVY)

save_animal('dog', image)
squirrel, pen = canvas('#add3c5')
ellipse(pen, (25, 53, 139, 181), NAVY)
ellipse(pen, (49, 76, 113, 132), '#add3c5')
stroke(pen, [('M', 80, 166), ('C', 93, 193, 120, 198, 147, 180)], 22, NAVY)
ellipse(pen, (105, 114, 188, 205), NAVY)
ellipse(pen, (135, 68, 208, 129), NAVY)
pen.polygon(points([('M', 139, 82), ('L', 146, 45), ('L', 170, 77), ('Z',)]), fill=NAVY)
pen.polygon(points([('M', 177, 78), ('L', 187, 50), ('L', 198, 89), ('Z',)]), fill=NAVY)
ellipse(pen, (191, 95, 228, 118), NAVY)
ellipse(pen, (185, 86, 193, 94), '#add3c5')
stroke(pen, [('M', 144, 199), ('L', 188, 199)], 12, NAVY)
clock_mark(pen, 148, 157, 26)
save_animal('squirrel', squirrel)

owl, pen = canvas('#bcc7ee')
ellipse(pen, (58, 50, 198, 210), NAVY)
pen.polygon(points([('M', 64, 82), ('L', 67, 34), ('L', 110, 61), ('Z',)]), fill=NAVY)
pen.polygon(points([('M', 146, 61), ('L', 189, 34), ('L', 192, 82), ('Z',)]), fill=NAVY)
ellipse(pen, (79, 75, 121, 117), CREAM)
ellipse(pen, (135, 75, 177, 117), CREAM)
ellipse(pen, (94, 87, 109, 103), NAVY)
ellipse(pen, (147, 87, 162, 103), NAVY)
pen.polygon(points([('M', 118, 116), ('L', 138, 116), ('L', 128, 130), ('Z',)]), fill=AMBER)
stroke(pen, [('M', 77, 126), ('C', 66, 145, 73, 172, 87, 182)], 6, '#bcc7ee')
stroke(pen, [('M', 179, 126), ('C', 190, 145, 183, 172, 169, 182)], 6, '#bcc7ee')
clock_mark(pen, 128, 162, 26)
stroke(pen, [('M', 96, 209), ('L', 113, 209)], 8, NAVY)
stroke(pen, [('M', 143, 209), ('L', 160, 209)], 8, NAVY)
save_animal('owl', owl)
print('Generated selectable dog, squirrel and owl icons.')
