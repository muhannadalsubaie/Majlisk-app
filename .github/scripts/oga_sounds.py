"""يجمع أصواتاً مسجّلة مجانية (CC0) من OpenGameArt للتجربة قبل اعتمادها — لا يغيّر أصوات التطبيق."""
import os, re, subprocess, sys, urllib.request, zipfile, io

PAGES = sys.argv[1:]
OUT = 'candidates'
UA = {'User-Agent': 'Mozilla/5.0 (compatible; majlisk-sound-candidates)'}
os.makedirs(OUT, exist_ok=True)


def get(url):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=120) as r:
        return r.read()


def conv(data, name, src):
    tmp = f'/tmp/src-{name}{os.path.splitext(src)[1]}'
    open(tmp, 'wb').write(data)
    subprocess.run(['ffmpeg', '-nostdin', '-loglevel', 'error', '-y', '-i', tmp, '-t', '6', '-ac', '1', '-ar', '44100', '-b:a', '96k', f'{OUT}/{name}.mp3'])


for page in PAGES:
    slug = page.rstrip('/').split('/')[-1]
    try:
        html = get(page).decode('utf-8', 'replace')
    except Exception as e:
        print('skip', page, e); continue
    lic = re.findall(r'(CC0|CC-BY[ -][0-9.]+|CC-BY-SA[ -][0-9.]+|GPL[ 0-9.]*|OGA-BY[ 0-9.]*)', html)
    files = sorted(set(re.findall(r'https://opengameart\.org/sites/default/files/[^"\']+\.(?:ogg|wav|mp3|zip|flac)', html)))
    print(f'== {slug} licenses={sorted(set(lic))} files={len(files)}')
    for i, f in enumerate(files):
        try:
            data = get(f)
        except Exception as e:
            print('  fail', f, e); continue
        base = re.sub(r'[^A-Za-z0-9_-]+', '_', os.path.splitext(os.path.basename(f))[0])[:40]
        if f.endswith('.zip'):
            z = zipfile.ZipFile(io.BytesIO(data))
            for j, n in enumerate([n for n in z.namelist() if re.search(r'\.(ogg|wav|mp3|flac)$', n, re.I)][:120]):
                nb = re.sub(r'[^A-Za-z0-9_-]+', '_', os.path.splitext(os.path.basename(n))[0])[:40]
                conv(z.read(n), f'{slug}__{nb}', n)
        else:
            conv(data, f'{slug}__{base}', f)
    print('  total now', len(os.listdir(OUT)))
