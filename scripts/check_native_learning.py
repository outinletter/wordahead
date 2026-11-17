#!/usr/bin/env python3
"""Exercise the shipping native persistence and dictionary services on macOS."""
import os
import shutil
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parent.parent
with tempfile.TemporaryDirectory(prefix='wordahead-native-tests-') as temporary:
    folder = Path(temporary)
    store = (root / 'ios/NativeLearningStore.swift').read_text().split('// Read the existing WebKit')[0]
    store = store.replace('        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .default, options: [.mixWithOthers])\n', '')
    store = store.replace('        try? AVAudioSession.sharedInstance().setActive(true)\n', '')
    resource = 'Optional(URL(fileURLWithPath: ' + __import__('json').dumps(str(root)) + '))'
    store = store.replace('Bundle.main.url(forResource: "Web", withExtension: nil)', resource)
    services = (root / 'ios/WordAheadApp.swift').read_text().split('enum CaptionFailure:', 1)[1]
    services = ('import Foundation\nimport CryptoKit\nimport StoreKit\nenum CaptionFailure:' + services).replace('Bundle.main.url(forResource:"Web",withExtension:nil)', resource)
    (folder / 'Store.swift').write_text(store)
    (folder / 'Services.swift').write_text(services)
    binary = folder / 'check'
    result = subprocess.run(['xcrun', 'swiftc', '-parse-as-library', str(folder / 'Store.swift'), str(folder / 'Services.swift'), str(root / 'scripts/NativeLearningTests.swift'), '-o', str(binary)], capture_output=True, text=True)
    if result.returncode:
        print(result.stderr)
        raise SystemExit(result.returncode)
    reference = folder / 'caption-reference.json'
    node = shutil.which('node') or str(Path.home() / '.cache/codex-runtimes/codex-primary-runtime/dependencies/node/bin/node')
    subprocess.run([node, str(root / 'scripts/native_caption_reference.cjs'), str(root), str(reference)], check=True)
    subprocess.run([str(binary), str(root), str(reference)], check=True)
