"""يجمع أصواتاً من Mixkit (رخصة Mixkit المجانية: تُستخدم في التطبيقات بلا ذكر صاحبها) للتجربة فقط — لا يغيّر أصوات التطبيق."""
import html, os, re, subprocess, sys, urllib.request

SLUGS = sys.argv[1:]
OUT = 'candidates'
UA = {'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120 Safari/537.36'}
os.makedirs(OUT, exist_ok=True)


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=60) as r:
        return r.read()


seen = set()
for slug in SLUGS:
    try:
        page = get(f'https://mixkit.co/free-sound-effects/{slug}/').decode('utf-8', 'replace')
    except Exception as e:
        print('skip', slug, e); continue
    cards = re.split(r'(?=<div[^>]+class="[^"]*item-grid__item)', page)
    n = 0
    for c in cards:
        m = re.search(r'https://assets\.mixkit\.co/active_storage/sfx/(\d+)/\1-preview\.mp3', c)
        t = re.search(r'item-grid-card__title[^>]*>\s*([^<]+?)\s*<', c)
        if not m or m.group(1) in seen:
            continue
        seen.add(m.group(1))
        title = html.unescape(t.group(1)) if t else m.group(1)
        name = f"{slug}__{m.group(1)}__{re.sub(r'[^A-Za-z0-9]+', '_', title)[:40]}"
        try:
            data = get(m.group(0))
        except Exception as e:
            print('  fail', m.group(0), e); continue
        open('/tmp/x.mp3', 'wb').write(data)
        subprocess.run(['ffmpeg', '-nostdin', '-loglevel', 'error', '-y', '-i', '/tmp/x.mp3', '-t', '8', '-ac', '1', '-ar', '44100', '-b:a', '96k', f'{OUT}/{name}.mp3'])
        n += 1
    print('mixkit', slug, n)
