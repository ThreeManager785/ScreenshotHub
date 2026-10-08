from pathlib import Path
import subprocess
import tempfile

project = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='ScreenshotHubHeadlineEditor-') as temporary:
    root = Path(temporary)
    executable = root / 'ValidateHeadlineEditor'
    subprocess.run([
        'xcrun', 'swiftc', '-parse-as-library', '-swift-version', '5',
        '-default-isolation', 'MainActor', '-disable-sandbox',
        '-module-cache-path', str(root / 'ModuleCache'),
        str(project / 'ScreenshotHub/NativeViewportSizing.swift'),
        str(project / 'ScreenshotHub/HeadlineEditor.swift'),
        str(project / 'Scripts/ValidateHeadlineEditor.swift'), '-o', str(executable)
    ], check=True)
    subprocess.run([str(executable)], check=True, timeout=30)
