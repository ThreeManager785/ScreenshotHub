from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description='Validate Apple Watch composition, clock caching, touch/crown/scroll routing, and frame update cost.')
parser.add_argument('app', type=Path)
parser.add_argument('--output', type=Path, default=Path('/tmp/ScreenshotHubWatchValidation'))
args = parser.parse_args()
project = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='ScreenshotHubWatchValidation-') as temporary:
    root = Path(temporary)
    executable = root / 'ValidateWatch'
    shutil.copy2(args.app / 'Contents/Resources/DeviceFrames.json', root / 'DeviceFrames.json')
    bridge = root / 'SimulatorFramebuffer.o'
    subprocess.run(['xcrun', 'clang', '-fobjc-arc', '-c', str(project / 'ScreenshotHub/SimulatorFramebuffer.m'), '-o', str(bridge)], check=True)
    sources = ['ScreenshotConfiguration', 'StoredScreenshotConfiguration', 'WatchConfiguration', 'WatchClockRenderer', 'DeviceFrameImages',
               'ScreenshotRenderer', 'DeviceShadowRenderer', 'SimulatorClient', 'SimulatorFeed',
               'SimulatorStatusBarConfiguration', 'NativeViewportSizing', 'PreviewScreenGeometry',
               'PreviewScreenMask', 'LiveScreenshotPreview']
    subprocess.run([
        'xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5', '-default-isolation', 'MainActor', '-disable-sandbox',
        '-module-cache-path', str(root / 'ModuleCache'),
        '-import-objc-header', str(project / 'ScreenshotHub/ScreenshotHub-Bridging-Header.h'),
        '-framework', 'IOSurface', str(bridge),
        *[str(project / 'ScreenshotHub' / f'{name}.swift') for name in sources],
        str(project / 'Scripts/ValidateWatch.swift'), '-o', str(executable)
    ], check=True)
    subprocess.run([str(executable), str(project / 'ScreenshotHub/Assets.xcassets'), str(args.output),
                    str(project / 'Scripts/Fixtures/WatchClock')], check=True, timeout=90)
