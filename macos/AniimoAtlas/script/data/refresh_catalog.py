"""Refresh the bundled catalog from public Aniidex page assets.
Run: python3 script/data/refresh_catalog.py
Fails on changed source schemas; does not run downloaded JavaScript.
"""
import pathlib,re,subprocess,tempfile,concurrent.futures,json,os,sys
from parse_literal import Reader
root=pathlib.Path(__file__).resolve().parents[2]
with tempfile.TemporaryDirectory(prefix='atlas-catalog-') as tmp:
 cache=pathlib.Path(tmp)
 def fetch(path):
  out=cache/(path.rstrip('/').rsplit('/',1)[-1])
  subprocess.run(['curl','--fail','--location','--silent','--show-error','--max-time','40','https://aniidex.com'+path,'-o',str(out)],check=True)
  return out.read_text()
 page=fetch('/aniimo/emberpup/')
 urls=list(dict.fromkeys(re.findall(r'(?:href|src)="(/_nuxt/[^" ]+\.js)',page)))
 assert urls,'No public page assets found'
 with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool: chunks=list(pool.map(fetch,urls))
 pet=next(s for s in chunks if re.search(r'var \w+=\{pets:JSON.parse',s))
 pets=Reader(pet,pet.index('{')).read()
 detail=next(s for s in chunks if 'basePetId:1005100,name:`Emberpup`' in s)
 match=re.search(r'\w+=(\{1005101:\{variantId:)',detail);assert match
 variants=Reader(detail,match.start(1)).read()
 match=re.search(r'\w+=(\{1001100:\{common:`/videos/aniimo/appearances-shadow/)',detail);assert match
 videos=Reader(detail,match.start(1)).read()
 imagesText=next(s for s in chunks if re.match(r'var \w+=\{1001100:\{common:`/images/',s))
 images=Reader(imagesText,imagesText.index('{')).read()
 assert len(pets['pets'])>=100 and len(variants)>=123 and len(images)>=209,'Catalog coverage unexpectedly shrank'
 for name,value in [('atlas-data',pets),('atlas-Mn',variants),('atlas-Tr',videos),('atlas-images',images)]:
  (cache/(name+'.json')).write_text(json.dumps(value))
 subprocess.run([sys.executable,str(root/'script/data/build_catalog.py')],env={**os.environ,'ATLAS_CATALOG_INPUTS':str(cache)},check=True)
