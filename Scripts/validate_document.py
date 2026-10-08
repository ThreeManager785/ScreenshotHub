from pathlib import Path
import argparse
import shutil
import subprocess
import tempfile

parser = argparse.ArgumentParser(description='Validate .sshub package persistence and snapshot exports.')
parser.add_argument('app', type=Path)
parser.add_argument('--source-assets', action='store_true', help='Load source assets without registering a GUI test bundle.')
args = parser.parse_args()
project = Path(__file__).resolve().parent.parent

with tempfile.TemporaryDirectory(prefix='ScreenshotHubDocumentValidation-') as temporary:
    root = Path(temporary)
    bundle = root / 'Validation.app' / 'Contents'
    resources = bundle / 'Resources'
    executable = bundle / 'MacOS' / 'ValidateDocument'
    resources.mkdir(parents=True)
    executable.parent.mkdir()
    if args.source_assets:
        executable = root / 'ValidateDocument'
        shutil.copy2(args.app / 'Contents/Resources/DeviceFrames.json', root / 'DeviceFrames.json')
    for name in ['Assets.car', 'DeviceFrames.json']:
        shutil.copy2(args.app / 'Contents' / 'Resources' / name, resources / name)
    (bundle / 'Info.plist').write_text('''<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>ValidateDocument</string>
<key>CFBundleIdentifier</key><string>com.memz233.ScreenshotHub.DocumentValidation</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>\n''')
    sources = ['ScreenshotConfiguration', 'DeviceFrameImages', 'StoredScreenshotConfiguration',
               'ScreenshotDraft', 'WatchConfiguration', 'WatchClockRenderer', 'ScreenshotHubDocument', 'ScreenshotRenderer', 'DeviceShadowRenderer', 'SnapshotImageExporter', 'ScreenshotPreviewRenderer']
    subprocess.run([
        'xcrun', 'swiftc', '-parse-as-library', '-module-cache-path', str(root / 'ModuleCache'),
        *[str(project / 'ScreenshotHub' / f'{name}.swift') for name in sources],
        str(project / 'Scripts/ValidateDocument.swift'), '-o', str(executable)
    ], check=True)
    asset_args = [str(project / 'ScreenshotHub/Assets.xcassets')] if args.source_assets else []
    subprocess.run([str(executable), str(root / 'Output'), *asset_args], check=True)
