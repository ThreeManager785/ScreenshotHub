from pathlib import Path
import argparse
import shutil
import plistlib
import subprocess
import tempfile

parser = argparse.ArgumentParser(description='Exercise native document window constraints during horizontal resizing.')
parser.add_argument('app', type=Path, help='Path to a built ScreenshotHub.app')
parser.add_argument('--split-view-only', action='store_true', help='Test the production split view with lightweight SwiftUI content.')
parser.add_argument('--output-app', type=Path, help='Build a native validation app for pasteboard access; launch it through the GUI.')
args = parser.parse_args()
project = Path(__file__).resolve().parent.parent

with tempfile.TemporaryDirectory(prefix='ScreenshotHubWindowLayout-') as temporary:
    root = Path(temporary)
    executable = root / 'ValidateWindowLayout'
    if args.output_app:
        contents = args.output_app / 'Contents'
        resources = contents / 'Resources'
        executable = contents / 'MacOS/ValidateWindowLayout'
        resources.mkdir(parents=True, exist_ok=True)
        executable.parent.mkdir(exist_ok=True)
        info = plistlib.loads((args.app / 'Contents/Info.plist').read_bytes())
        info.pop('CFBundleDocumentTypes', None)
        info['UTExportedTypeDeclarations'] = [entry for entry in info.get('UTExportedTypeDeclarations', [])
                                              if entry['UTTypeIdentifier'] == 'com.memz233.screenshothub.snapshot']
        info.update({
            'CFBundleExecutable': 'ValidateWindowLayout',
            'CFBundleIdentifier': 'com.memz233.ScreenshotHub.NativeDragValidation',
            'CFBundleName': 'Snapshot Drag Validation',
            'CFBundleDisplayName': 'Snapshot Drag Validation',
            'NativeDragValidation': True,
            'ValidationAssetCatalog': str(project / 'ScreenshotHub/Assets.xcassets'),
            'LSUIElement': True,
        })
        (contents / 'Info.plist').write_bytes(plistlib.dumps(info))
        for name in ['DeviceFrames.json', 'Assets.car']:
            shutil.copy2(args.app / 'Contents/Resources' / name, resources / name)

    for name in ['DeviceFrames.json']:
        shutil.copy2(args.app / 'Contents' / 'Resources' / name, root / name)
    bridge = root / 'SimulatorFramebuffer.o'
    subprocess.run([
        'xcrun', 'clang', '-fobjc-arc', '-c',
        str(project / 'ScreenshotHub/SimulatorFramebuffer.m'), '-o', str(bridge)
    ], check=True)
    sources = sorted(path for path in (project / 'ScreenshotHub').glob('*.swift')
                     if path.name != 'ScreenshotHubApp.swift')
    subprocess.run([
        'xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5',
        '-default-isolation', 'MainActor', '-disable-sandbox',
        '-module-cache-path', str(root / 'ModuleCache'),
        '-import-objc-header', str(project / 'ScreenshotHub/ScreenshotHub-Bridging-Header.h'),
        '-framework', 'IOSurface', str(bridge),
        *map(str, sources), str(project / 'Scripts/ValidateWindowLayout.swift'), '-o', str(executable)
    ], check=True)
    arguments = [str(executable), str(project / 'ScreenshotHub/Assets.xcassets')]
    if args.split_view_only:
        arguments.append('--split-view-only')
    if not args.output_app:
        subprocess.run(arguments, check=True, timeout=90)
