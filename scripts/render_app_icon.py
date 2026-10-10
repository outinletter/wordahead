"""Render the home screen's teal W mark as opaque iOS app icons."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

output = Path(__file__).resolve().parents[1] / 'ios/Assets.xcassets/AppIcon.appiconset'
image = Image.new('RGB', (1024, 1024), '#138775')
font = ImageFont.truetype('/System/Library/Fonts/Supplemental/Arial Bold.ttf', 704)
ImageDraw.Draw(image).text((512, 720), 'W', font=font, fill='white', anchor='ms')
for filename, size in [('AppIcon.png', 1024), ('AppIcon-60@2x.png', 120),
                       ('AppIcon-60@3x.png', 180), ('AppIcon-76@2x.png', 152),
                       ('AppIcon-83.5@2x.png', 167)]:
    image.resize((size, size), Image.Resampling.LANCZOS).save(output / filename)
