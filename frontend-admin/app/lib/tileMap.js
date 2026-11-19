"use client";

// ══════════════════════════════════════════════════════════════
// Vendra Admin - TileMap: a small slippy map without a map library.
// CARTO raster tiles (the key the apps use) placed with Web Mercator
// maths, markers as positioned elements and routes as an SVG overlay.
// The view fits the given points; +/- zoom around the centre.
// ══════════════════════════════════════════════════════════════

import { useEffect, useRef, useState } from "react";
import { useTheme } from "./hooks";

const TILE = 256;
const CARTO_KEY = "cb1_5bea_1_834da8b386e3c4f989f8feca";
const MIN_ZOOM = 3;
const MAX_ZOOM = 17;

/** World pixel position of a point at zoom z */
export function project(lat, lng, z) {
  const scale = TILE * 2 ** z;
  const sin = Math.min(Math.max(Math.sin((lat * Math.PI) / 180), -0.9999), 0.9999);
  return {
    x: ((lng + 180) / 360) * scale,
    y: (0.5 - Math.log((1 + sin) / (1 - sin)) / (4 * Math.PI)) * scale,
  };
}

/** Largest zoom at which every point fits in width × height (with padding) */
export function fitZoom(points, width, height, padding = 48) {
  if (points.length < 2) return 14;
  for (let z = MAX_ZOOM - 1; z >= MIN_ZOOM; z--) {
    const ps = points.map((p) => project(p.lat, p.lng, z));
    const w = Math.max(...ps.map((p) => p.x)) - Math.min(...ps.map((p) => p.x));
    const h = Math.max(...ps.map((p) => p.y)) - Math.min(...ps.map((p) => p.y));
    if (w <= width - padding * 2 && h <= height - padding * 2) return z;
  }
  return MIN_ZOOM;
}

function centreOf(points) {
  const lats = points.map((p) => p.lat);
  const lngs = points.map((p) => p.lng);
  return { lat: (Math.min(...lats) + Math.max(...lats)) / 2, lng: (Math.min(...lngs) + Math.max(...lngs)) / 2 };
}

/**
 * @param markers  [{ id, lat, lng, render: () => JSX, title }]
 * @param lines    [{ id, from: {lat,lng}, to: {lat,lng}, color, dashed }]
 * @param fit      points the view should fit (defaults to every marker); change it to refocus
 */
export default function TileMap({ markers, lines = [], fit, height = 520 }) {
  const box = useRef(null);
  const [width, setWidth] = useState(800);
  const [theme] = useTheme();
  const [zoomDelta, setZoomDelta] = useState(0);
  const fitPoints = (fit && fit.length ? fit : markers).filter((p) => p.lat != null && p.lng != null);
  const fitKey = fitPoints.map((p) => `${p.lat.toFixed(4)},${p.lng.toFixed(4)}`).join("|");
  const [lastFitKey, setLastFitKey] = useState(fitKey);

  // A new focus resets the manual zoom (adjusting state during render, not in an effect)
  if (fitKey !== lastFitKey) {
    setLastFitKey(fitKey);
    setZoomDelta(0);
  }

  useEffect(() => {
    const el = box.current;
    if (!el) return undefined;
    const observer = new ResizeObserver(([entry]) => setWidth(Math.round(entry.contentRect.width)));
    observer.observe(el);
    return () => observer.disconnect();
  }, []);

  if (fitPoints.length === 0) {
    return (
      <div ref={box} style={{ height }} className="rounded-2xl bg-surface-container-low flex items-center justify-center text-sm text-outline">
        Nothing to show on the map yet.
      </div>
    );
  }

  const zoom = Math.min(MAX_ZOOM, Math.max(MIN_ZOOM, fitZoom(fitPoints, width, height) + zoomDelta));
  const c = project(centreOf(fitPoints).lat, centreOf(fitPoints).lng, zoom);
  const left = c.x - width / 2;
  const top = c.y - height / 2;
  const toScreen = (p) => {
    const w = project(p.lat, p.lng, zoom);
    return { x: w.x - left, y: w.y - top };
  };

  const style = theme === "dark" ? "dark_all" : "voyager";
  const n = 2 ** zoom;
  const tiles = [];
  for (let tx = Math.floor(left / TILE); tx <= Math.floor((left + width) / TILE); tx++) {
    for (let ty = Math.floor(top / TILE); ty <= Math.floor((top + height) / TILE); ty++) {
      if (ty < 0 || ty >= n) continue;
      const wx = ((tx % n) + n) % n;
      tiles.push({
        key: `${zoom}/${tx}/${ty}`,
        src: `https://basemaps.cartocdn.com/rastertiles/${style}/${zoom}/${wx}/${ty}@2x.png?key=${CARTO_KEY}`,
        x: tx * TILE - left,
        y: ty * TILE - top,
      });
    }
  }

  return (
    <div ref={box} style={{ height }} className="relative overflow-hidden rounded-2xl bg-surface-container-low select-none">
      {tiles.map((t) => (
        // eslint-disable-next-line @next/next/no-img-element
        <img key={t.key} src={t.src} alt="" draggable={false} width={TILE} height={TILE}
          className="absolute max-w-none pointer-events-none" style={{ left: t.x, top: t.y }} />
      ))}

      <svg className="absolute inset-0 pointer-events-none" width={width} height={height}>
        {lines.map((l) => {
          const a = toScreen(l.from);
          const b = toScreen(l.to);
          return (
            <line key={l.id} x1={a.x} y1={a.y} x2={b.x} y2={b.y} stroke={l.color} strokeWidth={3}
              strokeLinecap="round" strokeDasharray={l.dashed ? "8 7" : undefined} opacity={0.85} />
          );
        })}
      </svg>

      {markers.filter((m) => m.lat != null && m.lng != null).map((m) => {
        const p = toScreen(m);
        if (p.x < -40 || p.y < -40 || p.x > width + 40 || p.y > height + 40) return null;
        return (
          <div key={m.id} title={m.title} className="absolute -translate-x-1/2 -translate-y-1/2" style={{ left: p.x, top: p.y }}>
            {m.render()}
          </div>
        );
      })}

      <div className="absolute right-3 top-3 flex flex-col rounded-lg overflow-hidden shadow border border-outline-variant/30 bg-surface-container-lowest">
        <button type="button" aria-label="Zoom in" onClick={() => setZoomDelta((d) => d + 1)}
          className="material-symbols-outlined text-[20px] p-1.5 hover:bg-surface-container-low text-on-surface">add</button>
        <button type="button" aria-label="Zoom out" onClick={() => setZoomDelta((d) => d - 1)}
          className="material-symbols-outlined text-[20px] p-1.5 hover:bg-surface-container-low text-on-surface border-t border-outline-variant/30">remove</button>
      </div>
      <p className="absolute left-2 bottom-1 text-[10px] text-outline bg-surface-container-lowest/80 px-1.5 rounded">
        © OpenStreetMap contributors © CARTO
      </p>
    </div>
  );
}
