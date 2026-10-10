"""Resize the selected home icon as opaque iOS app icons."""
from pathlib import Path
from PIL import Image

output = Path(__file__).resolve().parents[1] / 'ios/Assets.xcassets/AppIcon.appiconset'
image = Image.open(Path(__file__).resolve().parents[1] / 'icon.png').convert('RGB')
for filename, size in [('AppIcon.png', 1024), ('AppIcon-60@2x.png', 120),
                       ('AppIcon-60@3x.png', 180), ('AppIcon-76@2x.png', 152),
                       ('AppIcon-83.5@2x.png', 167)]:
    image.resize((size, size), Image.Resampling.LANCZOS).save(output / filename)
