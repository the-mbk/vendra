# Vendra brand icons

## The mark

The Vendra mark is a geometric **V**. Its right arm stops short, and a dot sits above it: the "nearby" pin that every Vendra app is built around.

All three apps share the mark. Each app gets its own background, so the icons are easy to tell apart on a phone:

| App | Background | V | Dot | Extra |
|---|---|---|---|---|
| Vendra (customer) | orange `#FD761A` | white | navy `#232774` | none |
| Vendra Vendor | navy `#232774` | white | orange | none |
| Vendra Rider | white | navy | orange | two motion trails behind the dot |
| Vendra Admin (web) | navy | white | orange | none |

## Files

- **`svg/vendra-<app>.svg`:** the master artwork. It is a 512 × 512 rounded tile.
- **`svg/vendra-<app>-maskable.svg`:** a full-bleed square. The mark sits inside the maskable safe circle.
- **`svg/vendra-mark.svg`:** the bare mark on a transparent background, for slides and documents.
- **`png/`:** 1024 and 512 px exports of the masters, for app stores and the presentation.
- **`generate-icons.mjs`:** draws all of the above and installs the icons into the apps.

## Regenerate

```
node branding/generate-icons.mjs
```

The script uses `sharp`, which the admin panel already has in its node_modules, so install the admin panel's packages first. It overwrites the following:

**Each Flutter app, under `android/app/src/main/res/`:**
- `mipmap-*/ic_launcher.png`: the legacy icon, 48–192 px.
- `mipmap-*/ic_launcher_foreground.png` and `ic_launcher_monochrome.png`, plus `mipmap-anydpi-v26/ic_launcher.xml`: the adaptive icon and the Android 13 themed icon.
- `values/ic_launcher_background.xml`: the background colour.
- `drawable*/launch_background.xml`: the splash screen while Flutter starts.

**Each Flutter app, under `web/`:**
- `favicon.png`
- `icons/Icon-*.png`
- the colours in `manifest.json`

**The admin panel, under `frontend-admin/app/`:**
- `favicon.ico`
- `icon.svg`

Edit the shapes or colours at the top of the script, then run it again. Never edit the PNGs by hand.
