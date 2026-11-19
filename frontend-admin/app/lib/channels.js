"use client";

// ══════════════════════════════════════════════════════════════
// Vendra Admin Dashboard - Sales channel analytics (walk-in POS vs online)
// Data: `channels` from GET /api/admin/stats (14 days) and /api/admin/finance (30 days)
// ══════════════════════════════════════════════════════════════

import { useEffect, useRef, useState } from "react";
import { formatRs } from "./ui";

/** Fixed channel order and colours (tokens in globals.css, with dark-mode steps) */
export const CHANNELS = [
  { key: "walkIn", label: "Walk-in POS", swatch: "bg-channel-walkin", fill: "fill-channel-walkin" },
  { key: "online", label: "Online marketplace", swatch: "bg-channel-online", fill: "fill-channel-online" },
];

/** "Rs. 12.5k" / "Rs. 1.2M" for axis labels */
function compactRs(value) {
  const n = Number(value) || 0;
  if (n >= 1e6) return `Rs. ${Number((n / 1e6).toFixed(1))}M`;
  if (n >= 1e3) return `Rs. ${Number((n / 1e3).toFixed(1))}k`;
  return `Rs. ${Math.round(n)}`;
}

/** "2026-11-18" → local date (no UTC shift) */
function parseDay(day) {
  const [y, m, d] = String(day).split("-").map(Number);
  return new Date(y, m - 1, d);
}

const dayLabel = (day) => parseDay(day).toLocaleDateString("en-PK", { day: "numeric", month: "short" });

/** Round numbers for the y axis: 1, 2, 2.5, 5 × 10^n */
function niceMax(value) {
  if (value <= 0) return 1;
  const power = 10 ** Math.floor(Math.log10(value));
  const step = [1, 2, 2.5, 5, 10].find((f) => f * power >= value);
  return step * power;
}

export function ChannelSwatch({ channel }) {
  return <span className={`w-2.5 h-2.5 rounded-sm shrink-0 ${channel.swatch}`} />;
}

/** One horizontal bar split by channel share of `walkIn + online` */
export function ChannelSplitBar({ walkIn, online }) {
  const values = { walkIn: Math.max(Number(walkIn) || 0, 0), online: Math.max(Number(online) || 0, 0) };
  const total = values.walkIn + values.online;
  return (
    <div className="h-3 rounded-full bg-surface-container-low overflow-hidden flex gap-0.5" role="img" aria-label="GMV split by channel">
      {total > 0 &&
        CHANNELS.map((c) =>
          values[c.key] > 0 ? (
            <div
              key={c.key}
              className={`h-full ${c.swatch}`}
              style={{ width: `${(values[c.key] / total) * 100}%` }}
              title={`${c.label}: ${formatRs(values[c.key])} (${Math.round((values[c.key] / total) * 100)}%)`}
            />
          ) : null
        )}
    </div>
  );
}

/** Path for a bar with only its top corners rounded */
function topRoundedBar(x, y, w, h, r) {
  const rr = Math.min(r, w / 2, h);
  return `M ${x} ${y + h} V ${y + rr} Q ${x} ${y} ${x + rr} ${y} H ${x + w - rr} Q ${x + w} ${y} ${x + w} ${y + rr} V ${y + h} Z`;
}

/**
 * Daily GMV as stacked bars (walk-in at the base, online on top), one bar per day.
 * Hover a day for its exact values. Pure SVG, coloured by theme tokens.
 */
export function ChannelSeriesChart({ series }) {
  // Drawn at the container's real pixel width so axis text stays 11px at any card width
  const boxRef = useRef(null);
  const [W, setW] = useState(640);
  useEffect(() => {
    const box = boxRef.current;
    if (!box) return undefined;
    const observer = new ResizeObserver(([entry]) => setW(Math.max(Math.round(entry.contentRect.width), 240)));
    observer.observe(box);
    return () => observer.disconnect();
  }, []);

  const days = series || [];
  return (
    <div ref={boxRef} className="w-full">
      {days.length > 0 ? (
        <StackedBars days={days} W={W} />
      ) : (
        <p className="text-sm text-outline py-8 text-center">No sales recorded in this period.</p>
      )}
    </div>
  );
}

function StackedBars({ days, W }) {
  const H = 210;
  const M = { top: 12, right: 8, bottom: 26, left: 58 };
  const plotW = W - M.left - M.right;
  const plotH = H - M.top - M.bottom;
  const max = niceMax(Math.max(...days.map((d) => (Number(d.walkIn) || 0) + (Number(d.online) || 0))));
  const slot = plotW / days.length;
  const barW = Math.max(Math.min(slot * 0.6, 28), 3);
  const y = (v) => M.top + plotH - (v / max) * plotH;
  const ticks = [0, max / 2, max];
  // Label about one day per 80px (always including the last day) so labels never collide
  const labelEvery = Math.ceil(days.length / Math.max(Math.floor(plotW / 80), 2));
  const GAP = 2; // surface gap between stacked segments

  return (
    <svg width={W} height={H} viewBox={`0 0 ${W} ${H}`} className="block max-w-full" role="img" aria-label="Daily GMV by channel">
      {ticks.map((t) => (
        <g key={t}>
          <line
            x1={M.left}
            x2={W - M.right}
            y1={y(t)}
            y2={y(t)}
            className={t === 0 ? "stroke-outline-variant" : "stroke-outline-variant/40"}
            strokeDasharray={t === 0 ? undefined : "3 3"}
          />
          <text x={M.left - 8} y={y(t)} dy="0.32em" textAnchor="end" fontSize="11" className="fill-outline">
            {compactRs(t)}
          </text>
        </g>
      ))}

      {days.map((d, i) => {
        const walkIn = Math.max(Number(d.walkIn) || 0, 0);
        const online = Math.max(Number(d.online) || 0, 0);
        const cx = M.left + slot * i + slot / 2;
        const x = cx - barW / 2;
        const walkH = (walkIn / max) * plotH;
        const onlineH = (online / max) * plotH;
        const base = M.top + plotH;
        const showLabel = (days.length - 1 - i) % labelEvery === 0;
        const label = dayLabel(d.day);
        return (
          <g key={d.day} className="group">
            <title>{`${label}\nWalk-in POS: ${formatRs(walkIn)}\nOnline: ${formatRs(online)}\nTotal: ${formatRs(walkIn + online)}`}</title>
            {/* Hover target spans the whole day column */}
            <rect x={M.left + slot * i} y={M.top} width={slot} height={plotH} className="fill-transparent group-hover:fill-on-surface/5" />
            {walkIn > 0 &&
              (online > 0 ? (
                <rect x={x} y={base - walkH} width={barW} height={walkH} className="fill-channel-walkin" />
              ) : (
                <path d={topRoundedBar(x, base - walkH, barW, walkH, 4)} className="fill-channel-walkin" />
              ))}
            {online > 0 && (
              // Sits on the walk-in segment with a 2px gap taken out of its own height, so the bar total stays exact
              <path
                d={topRoundedBar(x, base - walkH - onlineH, barW, Math.max(onlineH - (walkIn > 0 ? GAP : 0), 1), 4)}
                className="fill-channel-online"
              />
            )}
            {showLabel && (
              <text x={cx} y={H - 8} textAnchor="middle" fontSize="11" className="fill-outline">
                {label}
              </text>
            )}
          </g>
        );
      })}
    </svg>
  );
}
