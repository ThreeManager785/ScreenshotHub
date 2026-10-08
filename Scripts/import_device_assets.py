from pathlib import Path
from PIL import Image, ImageFilter, ImageChops
import argparse
import hashlib
import json
import shutil
import tempfile
from urllib.parse import quote

parser = argparse.ArgumentParser(description='Import Apple PNG bezels and generate exact screen masks.')
parser.add_argument('source', type=Path, nargs='?', default=Path.home() / 'Desktop/Apple Design Resources/Bazels')
source = parser.parse_args().source
project = Path(__file__).resolve().parent.parent
catalog = project / 'ScreenshotHub/Assets.xcassets'
registry = project / 'ScreenshotHub/DeviceFrames.json'
frames = json.loads(registry.read_text()) if registry.exists() else []
existing_names = {frame['name'] for frame in frames}
next_index = max((int(frame['id'].removeprefix('DeviceFrame')) for frame in frames), default=-1) + 1
imported_count = 0

def add_asset(name, path):
    folder = catalog / f'{name}.imageset'
    folder.mkdir(parents=True, exist_ok=True)
    shutil.copy2(path, folder / 'image.png')
    (folder / 'Contents.json').write_text(json.dumps({
        'images': [{'filename': 'image.png', 'idiom': 'universal'}],
        'info': {'author': 'xcode', 'version': 1}
    }, indent=2) + '\n')

def screen_region(hole):
    width, height = hole.size
    pixels = bytearray(hole.tobytes())
    pending = [(width // 2, height // 2)]
    while pending:
        x, y = pending.pop()
        offset = y * width
        if pixels[offset + x] != 255:
            continue
        left = pixels.rfind(0, offset, offset + x) + 1
        right = pixels.find(0, offset + x, offset + width)
        if right == -1:
            right = offset + width
        pixels[left:right] = b'\x80' * (right - left)
        for adjacent in (y - 1, y + 1):
            if not 0 <= adjacent < height:
                continue
            start = adjacent * width + left - offset
            end = adjacent * width + right - offset
            while start < end:
                seed = pixels.find(255, start, end)
                if seed == -1:
                    break
                pending.append((seed % width, adjacent))
                boundary = pixels.find(0, seed, end)
                start = end if boundary == -1 else boundary + 1
    return Image.frombytes('L', hole.size, bytes(pixels)).point(lambda value: 255 if value == 128 else 0)

for path in sorted(source.rglob('*.png')):
    if any(part.startswith('.') for part in path.relative_to(source).parts):
        continue
    family = ('mac' if any(model in path.name for model in ('MacBook', 'iMac', 'Studio Display'))
              else 'appleWatch' if 'Apple Watch' in path.name else 'iPad' if 'iPad' in path.name else 'iPhone' if 'iPhone' in path.name else None)
    if family is None or (family == 'iPhone' and 'Portrait' not in path.name):
        continue
    display_name = path.stem
    for orientation in ('Portrait', 'Landscape'):
        suffix = f' - {orientation}' if display_name.endswith(f' - {orientation}') else f' {orientation}'
        if display_name.endswith(suffix):
            display_name = display_name.removesuffix(suffix) + f' · {orientation}'
            break
    if display_name in existing_names:
        continue
    image = Image.open(path).convert('RGBA')
    width, height = image.size
    alpha = image.getchannel('A')
    hole = alpha.point(lambda value: 255 if value < 128 else 0)
    if hole.getpixel((width // 2, height // 2)) != 255:
        raise ValueError(f'No transparent screen at the center of {path}')
    screen = screen_region(hole)
    bounds = screen.getbbox()
    if not bounds or bounds[0] == 0 or bounds[1] == 0 or bounds[2] == width or bounds[3] == height:
        raise ValueError(f'Screen is not an enclosed transparent region: {path}')
    name = f'DeviceFrame{next_index:02}'
    mask = ImageChops.multiply(screen.filter(ImageFilter.MaxFilter(3)), ImageChops.invert(alpha))
    mask_image = Image.new('RGBA', image.size, 'white')
    mask_image.putalpha(mask)
    add_asset(name, path)
    with tempfile.TemporaryDirectory(prefix='ScreenshotHubMask-') as temporary:
        mask_path = Path(temporary) / 'mask.png'
        mask_image.save(mask_path)
        add_asset(f'{name}Mask', mask_path)
    frame = {
        'id': name, 'name': display_name,
        'family': family, 'width': width, 'height': height,
        'screenX': bounds[0], 'screenY': bounds[1],
        'screenWidth': bounds[2] - bounds[0], 'screenHeight': bounds[3] - bounds[1],
        'isLandscape': width > height
    }
    package = next((part for part in path.relative_to(source).parts if part.startswith('Bezel-')), None)
    if package:
        frame['sourceURL'] = 'https://devimages-cdn.apple.com/design/resources/download/' + quote(package + '.dmg')
        frame['sourceFile'] = path.name
        frame['sourceSHA256'] = hashlib.sha256(path.read_bytes()).hexdigest()
    frames.append(frame)
    existing_names.add(display_name)
    next_index += 1
    imported_count += 1
    registry.write_text(json.dumps(frames, ensure_ascii=False, indent=2) + '\n')
add_asset('DeviceShadow', project / 'iphone-shadow.png')
registry.write_text(json.dumps(frames, ensure_ascii=False, indent=2) + '\n')
print(f'Added {imported_count} PNG frames and matching screen masks; {len(frames)} frames available.')
