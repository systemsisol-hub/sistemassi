/* global React */
const { useState, useEffect, useRef } = React;

// ---------- Icon system (minimal line icons, Lucide-esque) ----------
const Icon = ({ name, size = 18, className = "", style = {} }) => {
  const s = size;
  const common = {
    width: s, height: s, viewBox: "0 0 24 24",
    fill: "none", stroke: "currentColor",
    strokeWidth: 1.6, strokeLinecap: "round", strokeLinejoin: "round",
    className, style,
  };
  const paths = {
    user: <><circle cx="12" cy="8" r="4"/><path d="M4 21a8 8 0 0 1 16 0"/></>,
    users: <><circle cx="9" cy="8" r="4"/><path d="M2 21a7 7 0 0 1 14 0"/><path d="M16 4a4 4 0 0 1 0 8"/><path d="M22 21a7 7 0 0 0-5-6.7"/></>,
    calendar: <><rect x="3" y="5" width="18" height="16" rx="2"/><path d="M16 3v4M8 3v4M3 11h18"/></>,
    fingerprint: <><path d="M6 10a6 6 0 0 1 12 0v2"/><path d="M9 14v2a3 3 0 0 0 6 0"/><path d="M3 13a9 9 0 0 1 18 0v2"/></>,
    inventory: <><path d="M4 7l8-4 8 4-8 4-8-4z"/><path d="M4 7v10l8 4 8-4V7"/><path d="M12 11v10"/></>,
    chart: <><path d="M3 20h18"/><rect x="6" y="10" width="3" height="8"/><rect x="11" y="6" width="3" height="12"/><rect x="16" y="13" width="3" height="5"/></>,
    badge: <><path d="M6 4h12v4l-6 3-6-3V4z"/><path d="M6 8v12h12V8"/><circle cx="12" cy="14" r="2"/></>,
    file: <><path d="M14 3H6a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V9l-6-6z"/><path d="M14 3v6h6"/></>,
    users3: <><circle cx="12" cy="9" r="3"/><path d="M6 20a6 6 0 0 1 12 0"/><circle cx="5" cy="7" r="2"/><circle cx="19" cy="7" r="2"/></>,
    phone: <><path d="M5 4h4l2 5-2.5 1.5a11 11 0 0 0 5 5L15 13l5 2v4a2 2 0 0 1-2 2A16 16 0 0 1 3 6a2 2 0 0 1 2-2z"/></>,
    pen: <><path d="M12 20h9"/><path d="M16.5 3.5a2.1 2.1 0 0 1 3 3L7 19l-4 1 1-4 12.5-12.5z"/></>,
    logs: <><path d="M4 6h16M4 12h16M4 18h10"/></>,
    key: <><circle cx="8" cy="12" r="4"/><path d="M12 12h10l-2 2m2-2l-2-2"/></>,
    search: <><circle cx="11" cy="11" r="7"/><path d="m20 20-3-3"/></>,
    bell: <><path d="M6 19h12"/><path d="M18 16V11a6 6 0 0 0-12 0v5l-2 2h16l-2-2z"/><path d="M10 21a2 2 0 0 0 4 0"/></>,
    help: <><circle cx="12" cy="12" r="9"/><path d="M9.5 9a2.5 2.5 0 1 1 3.5 2.3c-.8.4-1 .9-1 1.7"/><circle cx="12" cy="17" r=".6" fill="currentColor"/></>,
    chevron: <path d="m9 6 6 6-6 6"/>,
    camera: <><path d="M4 8h3l2-2h6l2 2h3a1 1 0 0 1 1 1v9a1 1 0 0 1-1 1H4a1 1 0 0 1-1-1V9a1 1 0 0 1 1-1z"/><circle cx="12" cy="13" r="3.5"/></>,
    eye: <><path d="M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12z"/><circle cx="12" cy="12" r="3"/></>,
    eyeOff: <><path d="m3 3 18 18"/><path d="M10.6 10.6a2 2 0 0 0 2.8 2.8"/><path d="M9.9 5.1A10.5 10.5 0 0 1 12 5c6.5 0 10 7 10 7a16 16 0 0 1-3.1 3.9"/><path d="M6.4 6.4A16 16 0 0 0 2 12s3.5 7 10 7a10 10 0 0 0 4.2-.9"/></>,
    copy: <><rect x="9" y="9" width="11" height="11" rx="2"/><path d="M5 15V5a2 2 0 0 1 2-2h10"/></>,
    mail: <><rect x="3" y="5" width="18" height="14" rx="2"/><path d="m3 7 9 6 9-6"/></>,
    hash: <><path d="M4 9h16M4 15h16M10 3 8 21M16 3l-2 18"/></>,
    pin: <><path d="M12 21s7-6.5 7-12a7 7 0 0 0-14 0c0 5.5 7 12 7 12z"/><circle cx="12" cy="9" r="2.5"/></>,
    briefcase: <><rect x="3" y="7" width="18" height="13" rx="2"/><path d="M8 7V5a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/><path d="M3 13h18"/></>,
    tree: <><circle cx="6" cy="6" r="2"/><circle cx="18" cy="6" r="2"/><circle cx="12" cy="18" r="2"/><path d="M6 8v4h12V8M12 12v4"/></>,
    shield: <><path d="M12 3 4 6v6c0 5 3.5 8.5 8 9 4.5-.5 8-4 8-9V6l-8-3z"/></>,
    logout: <><path d="M15 3h4a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2h-4"/><path d="M10 17l-5-5 5-5M5 12h12"/></>,
    lock: <><rect x="5" y="11" width="14" height="10" rx="2"/><path d="M8 11V7a4 4 0 0 1 8 0v4"/></>,
    check: <path d="m5 12 5 5 10-10"/>,
    arrow: <><path d="M5 12h14M13 5l7 7-7 7"/></>,
    dot: <circle cx="12" cy="12" r="3" fill="currentColor" stroke="none"/>,
    sparkle: <><path d="M12 3v4M12 17v4M3 12h4M17 12h4M6 6l2.5 2.5M15.5 15.5 18 18M6 18l2.5-2.5M15.5 8.5 18 6"/></>,
    plus: <><path d="M12 5v14M5 12h14"/></>,
  };
  return <svg {...common}>{paths[name] || null}</svg>;
};

window.Icon = Icon;
