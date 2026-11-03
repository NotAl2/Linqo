"""Package supplied/generated Linqo artwork into Flutter and Android assets.

Only technical sizing, transparent padding and launcher-mask packaging occur
here. The mascot edit was created with image_gen; the supplied full logo is
copied unchanged. Sources/prompts are embedded in shipped PNG metadata.
"""
from pathlib import Path
import argparse
from PIL import Image, PngImagePlugin

ROOT = Path(__file__).resolve().parent.parent
ORIGIN = 'User-supplied Linqo’s cheerful bookmark collector.png; mascot isolated with image_gen from that reference; technical asset sizing only.'
MASCOT_PROMPT = "Create a faithful isolated app-icon asset from the supplied Linqo brand artwork. Keep ONLY the exact cheerful purple bookmark mascot holding the mint green, yellow and pink bookmarks. Remove the entire lowercase 'linqo' wordmark below it and all surrounding padding. Preserve the mascot design, proportions, chunky dark-purple outlines, purple gradients, face, eyes, highlights, pink cheeks, mouth and three held bookmarks as faithfully as possible. Do not redesign, add detail, change pose, add letters, add text or add an icon tile. Transparent background. Center the complete unclipped mascot in a square image with modest equal transparent padding, optimized for a mobile app icon. This is an asset extraction/edit from the reference, not a new logo."

def write(image, path, source):
    path.parent.mkdir(parents=True, exist_ok=True)
    meta = PngImagePlugin.PngInfo()
    meta.add_text('Source', source)
    meta.add_text('impeccable:prompt', MASCOT_PROMPT if source == ORIGIN else source)
    image.save(path, pnginfo=meta, optimize=True)

def fit(image, size):
    result = image.copy()
    result.thumbnail(size, Image.Resampling.LANCZOS)
    return result

def center(image, canvas, color=(0,0,0,0)):
    result=Image.new('RGBA', canvas, color)
    result.alpha_composite(image, ((canvas[0]-image.width)//2,(canvas[1]-image.height)//2))
    return result

def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--full',type=Path,default=ROOT/'assets/brand/linqo-full.png')
    parser.add_argument('--mascot',type=Path,default=ROOT/'assets/brand/linqo-mascot.png')
    args=parser.parse_args()
    brand=ROOT/'assets/brand'
    full=Image.open(args.full).convert('RGBA')
    write(full,brand/'linqo-full.png','User-supplied Linqo’s cheerful bookmark collector.png; original RGBA pixels, no redesign')
    art=Image.open(args.mascot).convert('RGBA')
    bounds=art.getchannel('A').point(lambda a:255 if a>8 else 0).getbbox()
    art=art.crop(bounds)
    write(center(fit(art,(440,464)),(512,512)),brand/'linqo-mascot.png',ORIGIN)
    res=ROOT/'android/app/src/main/res'
    write(center(fit(art,(246,260)),(432,432)),res/'drawable-nodpi/linqo_mascot_foreground.png',ORIGIN)
    # Keep the entire supplied lockup within Android 12's circular splash mask.
    write(center(fit(full,(220,246)),(432,432)),res/'drawable-nodpi/linqo_splash_safe.png','User-supplied complete lockup padded for native splash mask')
    write(fit(full,(720,805)),res/'drawable-nodpi/linqo_full_logo.png','User-supplied full lockup resized for legacy launch background')
    for density,size in [('mdpi',48),('hdpi',72),('xhdpi',96),('xxhdpi',144),('xxxhdpi',192)]:
        write(center(fit(art,(round(size*.7),round(size*.78))),(size,size),(244,234,255,255)),res/f'mipmap-{density}/ic_launcher.png',ORIGIN)
    print('Packaged full logo, isolated mascot, Android splash and launcher assets.')

if __name__=='__main__': main()
