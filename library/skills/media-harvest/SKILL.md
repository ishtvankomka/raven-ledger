---
name: media-harvest
description: >
  Download EVERY media asset of a web page for exact replication — images, video, audio, fonts,
  SVG, icons — at all cost. Covers DOM assets, CSS backgrounds, srcset, lazy/blob/canvas images,
  data-URIs, media pulled from network requests, and streaming video (HLS/DASH/embeds). Emulates
  "save image/video as", decodes base64/blobs, and uses ffmpeg/yt-dlp where needed. Use during
  website recon to obtain identical media.
always_on: false
activation: "stage 3 of the replication pipeline — invoked by replica-scout after content-capture; also invoke standalone when every image/video/audio/font/SVG a page uses must be downloaded locally, including lazy, blob, canvas, sprite and streamed (HLS/DASH) media"
context_cost: low
---

# Media harvest — get every asset, identically

Goal: obtain the SAME media the original page uses, byte-for-byte where possible. Save to
`recon/<route-slug>/media/` and record everything in `media-manifest.json`.

## 1. Enumerate every asset reference (rendered DOM, via browser MCP JS)
Collect from: `<img src/srcset>`, `<picture><source srcset>`, `<video>/<audio>` + their
`<source src>` + `poster`, inline and external `<svg>`, `<link rel=icon|apple-touch-icon|preload as=image>`,
OpenGraph/Twitter image tags, and every CSS `background-image: url(...)` (walk stylesheets +
inline styles + `::before/::after`). Resolve protocol-relative `//`, relative, and query URLs.

```js
const urls = new Set();
document.querySelectorAll('img').forEach(i=>{ if(i.currentSrc)urls.add(i.currentSrc); (i.srcset||'').split(',').forEach(s=>urls.add(s.trim().split(' ')[0])); });
document.querySelectorAll('source').forEach(s=>{ (s.src||s.srcset||'').split(',').forEach(u=>u&&urls.add(u.trim().split(' ')[0])); });
document.querySelectorAll('video,audio').forEach(v=>{ if(v.src)urls.add(v.src); if(v.poster)urls.add(v.poster); });
[...document.querySelectorAll('*')].forEach(e=>{ const b=getComputedStyle(e).backgroundImage; if(b&&b!=='none')[...b.matchAll(/url\(["']?(.*?)["']?\)/g)].forEach(m=>urls.add(m[1])); });
JSON.stringify([...urls].map(u=>new URL(u, location.href).href));
```

## 2. Pull from network requests (catches lazy/XHR/streamed media)
Use browser MCP `read_network_requests` (or a fresh reload while recording) to list ALL responses
whose type is image/video/audio/font or whose URL ends in a media extension or `.m3u8`/`.mpd`.
This catches media the DOM scan misses (lazy-loaded, fetched by JS, sprite atlases, API-served
images). Add every such URL to the download set.

## 3. Download direct assets
`curl --compressed -L -A "<copy the page's UA>" -e "<page url>" "<asset>" -o media/<name>`.
Preserve original filenames; keep `?query` versions distinct. Use the page's cookies/referer if a
host 403s. Retry failures with a different referer/UA before giving up.

## 4. "Save as" emulation for blob / canvas / lazy / obfuscated images
When an image is a `blob:`/`data:` URL, a `<canvas>`, or only appears after interaction, fetch it
in-page and return base64, then decode to a file:
```js
// in page: return a data URL for any element/url
async function grab(url){ const r=await fetch(url,{credentials:'include'}); const b=await r.blob();
  return await new Promise(res=>{const fr=new FileReader();fr.onload=()=>res(fr.result);fr.readAsDataURL(b);}); }
// canvas: document.querySelector('canvas').toDataURL('image/png')
```
Then `base64 --decode` (or `python3 -c` / `node`) the payload to `media/<name>`. For `data:` URIs
already in the HTML/CSS, decode them directly.

## 5. Video & streaming
- Direct `.mp4`/`.webm`: download with curl (range/`-C -` resume for big files).
- **HLS** (`.m3u8`) / **DASH** (`.mpd`): `ffmpeg -i "<manifest url>" -c copy out.mp4` (or download
  segments from the network list and concat). 
- **Embedded players** (YouTube/Vimeo/Wistia/flipbook embeds/etc. in an `<iframe>`): record the embed
  URL; try `yt-dlp "<url>"` for downloadable sources. If the media is third-party hosted/DRM and can't
  be pulled, capture the embed URL + a poster frame and record it in the manifest as
  `embedOnly: true` with the provider — the builder reproduces the embed, not a local file.
- Capture the poster/thumbnail regardless so the placeholder matches.

## 6. Decode / normalize
- `curl --compressed` handles gzip/brotli. Keep original formats (webp/avif/svg) as-is; only
  convert if the build needs it (`cwebp`, `ffmpeg`, `rsvg-convert`) and keep the original too.
- For CSS sprite sheets, download the sheet and record each icon's background-position + size so
  the builder can slice or reuse it.

## 7. Manifest — `recon/<route-slug>/media-manifest.json`
```json
{ "originalUrl": "//.../Cover-1_a.jpg", "localPath": "media/cover-1.jpg",
  "type": "image|video|audio|font|svg|sprite|embed", "bytes": 110137,
  "dimensions": "1600x600", "sha256": "…", "usedOn": "/", "usedAs": "hero slide 1",
  "status": "downloaded|embedOnly|failed", "note": "" }
```
De-duplicate by sha256. Verify each file: non-zero size and correct type (`file <path>`); re-fetch
any that are HTML error bodies or truncated.

**Done when:** every URL from steps 1–2 is either downloaded and verified, or recorded with a
concrete reason it couldn't be (embed/DRM/auth) + a fallback. No asset is silently skipped.
