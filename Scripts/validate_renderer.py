from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description='Validate export sizes, PNG opacity, device masks, shadows, and Unicode text.')
parser.add_argument('app', type=Path, help='Path to a built ScreenshotHub.app')
parser.add_argument('--source-assets', action='store_true', help='Load source assets without registering a GUI test bundle.')
parser.add_argument('--output', type=Path, default=Path('/tmp/ScreenshotHubValidation'))
args = parser.parse_args()
project = Path(__file__).resolve().parent.parent

with tempfile.TemporaryDirectory(prefix='ScreenshotHubValidation-') as temporary:
    root = Path(temporary)
    bundle = root / 'Validation.app' / 'Contents'
    resources = bundle / 'Resources'
    executable = bundle / 'MacOS' / 'ValidateRenderer'
    resources.mkdir(parents=True)
    executable.parent.mkdir()
    if args.source_assets:
        executable = root / 'ValidateRenderer'
        shutil.copy2(args.app / 'Contents/Resources/DeviceFrames.json', root / 'DeviceFrames.json')
    for name in ['Assets.car', 'DeviceFrames.json']:
        shutil.copy2(args.app / 'Contents' / 'Resources' / name, resources / name)
    (bundle / 'Info.plist').write_text('''<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ValidateRenderer</string>
<key>CFBundleIdentifier</key><string>com.memz233.ScreenshotHub.Validation</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>\n''')
    subprocess.run([
        'xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(root / 'ModuleCache'),
        str(project / 'ScreenshotHub/ScreenshotConfiguration.swift'),
        str(project / 'ScreenshotHub/DeviceFrameImages.swift'),
        str(project / 'ScreenshotHub/StoredScreenshotConfiguration.swift'),
        str(project / 'ScreenshotHub/WatchConfiguration.swift'),
        str(project / 'ScreenshotHub/WatchClockRenderer.swift'),
        str(project / 'ScreenshotHub/ScreenshotRenderer.swift'),
        str(project / 'ScreenshotHub/DeviceShadowRenderer.swift'),
        str(project / 'ScreenshotHub/PreviewScreenMask.swift'),
        str(project / 'ScreenshotHub/NativeViewportSizing.swift'),
        str(project / 'Scripts/ValidateRenderer.swift'), '-o', str(executable)
    ], check=True)
    asset_args = [str(project / 'ScreenshotHub/Assets.xcassets')] if args.source_assets else []
    subprocess.run([str(executable), str(args.output.resolve()), *asset_args], check=True)
