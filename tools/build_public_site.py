"""Build the small, script-free OAuth information site from tracked policies.

Only explicitly listed public assets are copied; private configs and APKs never
belong in the Hosting directory. Uses the Python standard library only.
"""
from html import escape
from pathlib import Path
import re
import shutil

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / '.hosting-public'


def inline(text):
    text = escape(text)
    text = re.sub(r'\*\*(.+?)\*\*', r'<strong>\1</strong>', text)
    text = re.sub(r'\[([^\]]+)\]\((https://[^\s)]+|/[^\s)]+)\)', r'<a href="\2">\1</a>', text)
    return re.sub(r'`([^`]+)`', r'<code>\1</code>', text)


def markdown(text):
    """Render the limited headings/paragraphs/table syntax used by our policies."""
    result, paragraph, table = [], [], []

    def flush():
        if paragraph:
            result.append('<p>' + inline(' '.join(paragraph)) + '</p>')
            paragraph.clear()
        if table:
            rows = []
            for n, row in enumerate(table):
                if re.fullmatch(r'[| :\-]+', row):
                    continue
                tag = 'th' if n == 0 else 'td'
                cells = row.strip('|').split('|')
                rows.append('<tr>' + ''.join(f'<{tag}>{inline(c.strip())}</{tag}>' for c in cells) + '</tr>')
            result.append('<div class="table-scroll"><table>' + ''.join(rows) + '</table></div>')
            table.clear()

    for line in text.splitlines():
        if line.startswith('#'):
            flush()
            level = len(line) - len(line.lstrip('#'))
            result.append(f'<h{level}>' + inline(line[level:].strip()) + f'</h{level}>')
        elif line.startswith('|'):
            if paragraph:
                flush()
            table.append(line)
        elif not line.strip():
            flush()
        else:
            if table:
                flush()
            paragraph.append(line.strip())
    flush()
    return '\n'.join(result)


def page(title, body, reading=True):
    return f'''<!doctype html>
<html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>{escape(title)} · Linqo</title><meta name="description" content="Linqo: a local bookmark library with optional on-device English AI and optional Google Drive backup.">
<link rel="icon" href="/assets/linqo-mascot.png"><link rel="stylesheet" href="/site.css"></head><body>
<a class="skip" href="#content">Skip to content</a>
<header><a class="brand" href="/"><img src="/assets/linqo-mascot.png" width="38" height="48" alt="">linqo</a>
<nav aria-label="Main navigation"><a href="/">About</a><a href="/privacy">Privacy</a><a href="/terms">Terms</a><a href="/purchases">Purchases</a><a href="/support">Support</a></nav></header>
<main id="content"{ ' class="reading"' if reading else ''}>{body}</main>
<footer><p>Linqo is in active development. Optional accounts and Drive backup are in a private development preview. Checkout is not live.</p>
<p><a href="https://github.com/NotAl2/Linqo">Open-source project</a> · <a href="/privacy">Privacy policy</a> · <a href="/terms">Terms</a> · <a href="/shipping">Digital delivery</a> · <a href="mailto:gamer12773@gmail.com">Contact support</a></p></footer>
</body></html>'''


def main():
    OUT.mkdir(exist_ok=True)
    assets = OUT / 'assets'
    assets.mkdir(exist_ok=True)
    for name in ['linqo-mascot.png', 'linqo-full.png']:
        shutil.copyfile(ROOT / 'assets/brand' / name, assets / name)
    for name in ['Fredoka.ttf', 'Nunito.ttf', 'fredoka-OFL.txt', 'nunito-OFL.txt']:
        shutil.copyfile(ROOT / 'assets/fonts' / name, assets / name)
    shutil.copyfile(ROOT / 'hosting/site.css', OUT / 'site.css')
    pages = {
        'privacy': ('Privacy policy', markdown((ROOT / 'policies/PRIVACY.md').read_text(encoding='utf-8'))),
        'purchases': ('Purchases and refunds', markdown((ROOT / 'policies/PURCHASES.md').read_text(encoding='utf-8'))),
        'terms': ('Terms of use', markdown((ROOT / 'policies/TERMS.md').read_text(encoding='utf-8'))),
        'support': ('Support', '<h1>A little help with Linqo.</h1><p>Email <a href="mailto:gamer12773@gmail.com">gamer12773@gmail.com</a> for private account, backup or payment questions.</p><p>For reproducible bugs and feature requests, use <a href="https://github.com/NotAl2/Linqo/issues">GitHub issues</a>. Never post passwords, authentication tokens, payment receipts or private library content publicly.</p><h2>Planned paid upgrades</h2><p>Indian purchases will use Cashfree hosted checkout: XL ₹449 once and XXL ₹649 once. Checkout is not live yet. After a verified payment, return to Linqo and choose Restore purchase with the Google account used to start checkout. If it does not update, email support privately with your Cashfree order reference. Sandbox payments and ordinary Buy Me a Coffee donations do not unlock a tier.</p><h2>Account and data controls</h2><p>In the connected preview, open Settings → Account, tiers &amp; Drive backup to sign out, disable backup or delete your account. Signing out and account deletion preserve the local library. Delete saved items separately in Linqo. Manage retained cloud snapshots through Google Drive’s app settings.</p>'),
        'shipping': ('Digital delivery', '<h1>Digital delivery.</h1><p>Linqo is an Android application distributed as an APK through <a href="https://github.com/NotAl2/Linqo/releases">GitHub Releases</a>. No physical goods are shipped.</p><p>Paid XL/XXL unlocks are planned, but checkout is not live. A future paid unlock will belong to the Google account used to start checkout and will be granted only after payment verification. Downloading an APK or donating does not create a purchase.</p><p>See <a href="/purchases">purchases and refund information</a> or <a href="/support">contact support</a>.</p>'),
    }
    for slug, (title, body) in pages.items():
        (OUT / f'{slug}.html').write_text(page(title, body), encoding='utf-8')
    home = '''<section class="intro"><div><h1>Found it.<br>Keep it close.</h1><p>A cheerful home for recipes, videos, places, links and notes. Save the things you love, then find them again in your own local library.</p><a class="button" href="https://github.com/NotAl2/Linqo/releases">Get Linqo for Android</a><a href="https://github.com/NotAl2/Linqo">Explore the code</a></div><img src="/assets/linqo-full.png" width="250" height="300" alt="Linqo’s purple bookmark collector hugging colourful bookmarks"></section>
<aside class="notice"><p><strong>Still growing, with care.</strong> Linqo is in active development. The public v0.8.3 release is unlimited and donation-supported. Google accounts and Drive backups are being tested in the private v0.9.0 preview. Paid checkout is not available.</p></aside>
<section class="features"><h2>Your library stays with you.</h2><p>Save from Android’s share menu, organise collections and search locally. English AI extraction is optional and runs on your device with a separately downloaded model. Public titles and previews use the original provider and are best effort.</p><h2>A backup, when you choose.</h2><p>The connected preview offers optional Google sign-in and a separate Enable Drive backup action. Linqo requests only its own app-data folder, not access to the rest of your Drive. Backups use your Google storage, exclude model weights and merge into your library when you explicitly restore them. Portable local ZIP backups remain available without an account.</p><p>Sign-in alone never uploads a library. <a href="/privacy">Read what Linqo accesses and how to control it.</a></p><h2>Small app. Thoughtful choices.</h2><p>No hosted AI inference or continuous library sync. No website analytics or advertising scripts. Donations through <a href="https://buymeacoffee.com/notal2">Buy Me a Coffee</a> are voluntary and separate from planned purchases.</p></section>'''
    (OUT / 'index.html').write_text(page('Your cheerful bookmark library', home, reading=False), encoding='utf-8')
    (OUT / '404.html').write_text(page('Page not found', '<h1>This page wandered off.</h1><p><a href="/">Back to Linqo</a> or <a href="/support">ask for help</a>.</p>'), encoding='utf-8')
    files = [p for p in OUT.rglob('*') if p.is_file()]
    expected = {'index.html', '404.html', 'site.css', *(f'{slug}.html' for slug in pages),
                *(f'assets/{name}' for name in ['linqo-mascot.png', 'linqo-full.png', 'Fredoka.ttf', 'Nunito.ttf', 'fredoka-OFL.txt', 'nunito-OFL.txt'])}
    for file in files:
        if file.relative_to(OUT).as_posix() not in expected:
            raise ValueError('Unexpected public file: ' + file.name)
    print(f'Built {len(files)} public files; {sum(p.stat().st_size for p in files):,} bytes. No scripts, credentials or APKs.')


if __name__ == '__main__':
    main()
