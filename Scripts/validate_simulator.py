from pathlib import Path
import subprocess
import tempfile

project = Path(__file__).resolve().parent.parent
fixture_source = r'''
from pathlib import Path
import json
import struct
import sys
import time
import zlib

root = Path(__file__).parent
args = sys.argv[1:]
if args == ['list', 'devices', 'booted', '--json']:
    devices = [
        {'udid': 'PHONE', 'name': 'Studio Phone', 'state': 'Booted', 'isAvailable': True,
         'deviceTypeIdentifier': 'com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro'},
        {'udid': 'IPAD', 'name': 'iPad Pro', 'state': 'Booted', 'isAvailable': True},
        {'udid': 'OFF', 'name': 'iPhone 16', 'state': 'Shutdown', 'isAvailable': True},
        {'udid': 'UNAVAILABLE', 'name': 'iPhone 15', 'state': 'Booted', 'isAvailable': False},
        {'udid': 'WATCH', 'name': 'Apple Watch', 'state': 'Booted', 'isAvailable': True}
    ]
    if (root / 'stop-devices').exists():
        devices = []
    print(json.dumps({'devices': {'com.apple.CoreSimulator.SimRuntime.iOS-27-0': devices}}))
    sys.exit(0)
if args[0] == 'status_bar':
    with (root / 'status-commands.jsonl').open('a') as log:
        log.write(json.dumps(args, ensure_ascii=False) + '\n')
    if args[1] == 'ERROR':
        sys.stderr.write('status bar unavailable')
        sys.exit(1)
    if args[1] == 'SLOW':
        time.sleep(2)
    if args[2] == 'clear':
        assert len(args) == 3, args
    else:
        assert args[2] == 'override', args
        values = dict(zip(args[3::2], args[4::2]))
        assert set(values) == {'--time', '--dataNetwork', '--wifiMode', '--wifiBars', '--cellularMode',
                               '--cellularBars', '--operatorName', '--batteryState', '--batteryLevel'}, values
        assert values['--dataNetwork'] in {'hide', 'wifi', '3g', '4g', 'lte', 'lte-a', 'lte+', '5g', '5g+', '5g-uwb', '5g-uc'}
        assert values['--wifiMode'] in {'searching', 'failed', 'active'}
        assert values['--cellularMode'] in {'notSupported', 'searching', 'failed', 'active'}
        assert values['--batteryState'] in {'charging', 'charged', 'discharging'}
        assert 0 <= int(values['--wifiBars']) <= 3
        assert 0 <= int(values['--cellularBars']) <= 4
        assert 0 <= int(values['--batteryLevel']) <= 100
    sys.exit(0)
assert args[0] == 'io' and args[2:5] == ['screenshot', '--type=png', '--mask=ignored'], args
identifier = args[1]
if identifier == 'ERROR':
    sys.stderr.write('synthetic failure\n' + 'x' * 1024 * 1024)
    sys.exit(1)
if identifier == 'SLOW':
    time.sleep(2)
if identifier == 'INVALID':
    Path(args[-1]).write_bytes(b'not a PNG')
    sys.exit(0)
if identifier == 'MALFORMED':
    Path(args[-1]).write_bytes(b'\x89PNG\r\n\x1a\n')
    sys.exit(0)
count_path = root / 'capture-count'
count = int(count_path.read_text()) + 1 if count_path.exists() else 1
count_path.write_text(str(count))
def chunk(kind, data):
    return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data) & 0xffffffff)
rows = b''.join(b'\0' + bytes([count % 255, 100, 200]) * 12 for _ in range(24))
png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', 12, 24, 8, 2, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress(rows)) + chunk(b'IEND', b'')
Path(args[-1]).write_bytes(png)
'''

with tempfile.TemporaryDirectory(prefix='ScreenshotHubSimulatorTest-') as directory:
    root = Path(directory)
    fixture = root / 'simctl_fixture.py'
    fixture.write_text(fixture_source)
    executable = root / 'ValidateSimulator'
    geometry_test = root / 'ValidatePreviewInteraction'
    subprocess.run([
        'xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(root / 'ModuleCache'),
        str(project / 'ScreenshotHub/PreviewScreenGeometry.swift'),
        str(project / 'ScreenshotHub/NativeViewportSizing.swift'),
        str(project / 'Scripts/ValidatePreviewInteraction.swift'), '-o', str(geometry_test)
    ], check=True)
    subprocess.run([str(geometry_test)], check=True, timeout=10)
    bridge = root / 'SimulatorFramebuffer.o'
    framebuffer_test = root / 'ValidateFramebuffer'
    subprocess.run([
        'xcrun', 'clang', '-fobjc-arc', '-c',
        str(project / 'ScreenshotHub/SimulatorFramebuffer.m'), '-o', str(bridge)
    ], check=True)
    subprocess.run([
        'xcrun', 'clang', '-fobjc-arc', '-DSCREENSHOT_HUB_TESTING=1',
        '-I', str(project / 'ScreenshotHub'),
        '-framework', 'Foundation', '-framework', 'CoreGraphics', '-framework', 'IOSurface',
        str(project / 'ScreenshotHub/SimulatorFramebuffer.m'),
        str(project / 'Scripts/ValidateFramebuffer.m'), '-o', str(framebuffer_test)
    ], check=True)
    subprocess.run([str(framebuffer_test)], check=True, timeout=10)
    subprocess.run([
        'xcrun', 'swiftc', '-parse-as-library', '-disable-sandbox',
        '-module-cache-path', str(root / 'ModuleCache'),
        '-import-objc-header', str(project / 'ScreenshotHub/ScreenshotHub-Bridging-Header.h'),
        '-framework', 'IOSurface', str(bridge),
        str(project / 'ScreenshotHub/SimulatorClient.swift'),
        str(project / 'ScreenshotHub/SimulatorStatusBarConfiguration.swift'),
        str(project / 'ScreenshotHub/SimulatorFeed.swift'),
        str(project / 'Scripts/ValidateSimulator.swift'), '-o', str(executable)
    ], check=True)
    subprocess.run([str(executable), str(fixture)], check=True, timeout=30)
