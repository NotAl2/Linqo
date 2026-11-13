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
<footer><p>Linqo is in active development. Optional accounts, encrypted backups and Polar checkout are in beta qualification. Tier limits apply in the current prebuild; public payments remain paused by choice.</p>
<p><a href="https://github.com/NotAl2/Linqo">Open-source project</a> · <a href="/privacy">Privacy policy</a> · <a href="/terms">Terms</a> · <a href="/shipping">Digital delivery</a> · <a href="mailto:aryandurgude123@gmail.com">Contact support</a></p></footer>
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
        'support': ('Support', '<h1>A little help with Linqo.</h1><p>Email <a href="mailto:aryandurgude123@gmail.com">aryandurgude123@gmail.com</a> privately for account, backup, privacy or payment questions. Keep the email thread as your reference. Never send passwords, authentication tokens, identity documents, full card/bank details or private library content to public issues.</p><p>For reproducible bugs and feature requests, use <a href="https://github.com/NotAl2/Linqo/issues">GitHub issues</a>. A public post is never required for support or a refund.</p><h2>Purchase and refund complaints</h2><p>Public paid checkout and new manual upgrade sales remain unavailable. For full prebuild access, email aryandurgude123@gmail.com with your requested tier and Linqo account code; requests are reviewed manually and donations do not automatically unlock access. Do not send upgrade payments without a separate availability confirmation. See the <a href="/purchases">purchase and refund policy</a> for the 15-calendar-day request window, verification, actual-amount refunds, original payment method and statutory remedies outside that window. A separately agreed manual upgrade is a purchase, not an ordinary donation.</p><p>Support will acknowledge complaints within 48 hours and work to resolve them within one month, without extending a shorter mandatory deadline. Provider and bank credit time is separate. Include the order/payment reference privately; if you cannot access the original Google account, explain that so a safe verification route can be considered.</p><h2>Privacy and backups</h2><p>See the <a href="/privacy">privacy notice</a> for deletion/correction requests, retention limits and differences between older unencrypted ZIP backups and updated password-protected exports. Account deletion does not delete your local library or copies held by your document provider. Forgotten backup passwords cannot be recovered.</p><p>Linqo is made by NotAl2, the developer’s public creator alias. Public paid sales remain paused; formal individual-seller disclosures and applicable operational checks must be completed before any future sales activation.</p>'),
        'shipping': ('Digital delivery', '<h1>Digital delivery.</h1><p>Linqo is an Android application distributed as an APK through <a href="https://github.com/NotAl2/Linqo/releases">GitHub Releases</a>. No physical goods are shipped.</p><p>The Polar beta integration provides account-bound one-time XL/XXL unlocks, but public checkout remains paused. A verified paid unlock belongs to the Google account used to start checkout; a return page alone does not establish payment. Downloading an APK or making an ordinary voluntary donation does not create an upgrade purchase. A separately agreed manual upgrade is a sale covered by the purchase policy.</p><p>See <a href="/purchases">purchases and refund information</a> or <a href="/support">contact support</a>.</p>'),
    }
    for slug, (title, body) in pages.items():
        (OUT / f'{slug}.html').write_text(page(title, body), encoding='utf-8')
    home = '''<section class="intro"><div><h1>Found it.<br>Keep it close.</h1><p>A cheerful home for recipes, videos, places, links and notes. Save the things you love, then find them again in your own local library.</p><a class="button" href="https://github.com/NotAl2/Linqo/releases">Get Linqo for Android</a><a href="https://github.com/NotAl2/Linqo">Explore the code</a></div><img src="/assets/linqo-full.png" width="250" height="300" alt="Linqo’s purple bookmark collector hugging colourful bookmarks"></section>
<aside class="notice"><p><strong>Still growing, with care.</strong> Linqo is in active development. The public v0.8.3 release is unlimited and donation-supported. Google accounts and Drive backups are being tested in the private v0.9.0 preview. Polar checkout and restoration passed a private zero-price acceptance test. The current prebuild enforces Free 100 saves/5 collections, XL 500/30, and XXL without product quotas. Payments remain disabled by choice. For full prebuild access, email <a href="mailto:aryandurgude123@gmail.com">aryandurgude123@gmail.com</a> with your requested tier and Linqo account code. Donations are separate from access requests.</p></aside>
<section class="features"><h2>Your library stays with you.</h2><p>Save from Android’s share menu, organise collections and search locally. English AI extraction is optional and runs on your device with a separately downloaded model. Public titles and previews use the original provider and are best effort.</p><h2>A backup, when you choose.</h2><p>Updated builds that request a backup password export protected .linqo files through Android’s Files picker, including Drive when its document provider is available. Earlier previews may export unencrypted ZIPs and may offer automatic Drive app-data backups; an update does not encrypt existing copies. Keep your password: Linqo cannot recover it. Import merges your saves and preserves current settings. Models and credentials are excluded. New automatic Drive API uploads are disabled in the updated flow; earlier unencrypted app-data snapshots remain restorable with separate Google permission. Legacy ZIP imports remain available.</p><p>Sign-in alone never uploads a library. <a href="/privacy">Read what Linqo accesses and how to control it.</a></p><h2>Small app. Thoughtful choices.</h2><p>No hosted AI inference or continuous library sync. No website analytics or advertising scripts. Donations through <a href="https://buymeacoffee.com/notal2">Buy Me a Coffee</a> or <a href="https://buymeatea.online/notal2">Buy Me a Tea (India)</a> are voluntary and separate from planned purchases.</p></section>'''
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
