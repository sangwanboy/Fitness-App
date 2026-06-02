// glass.jsx — Liquid Glass primitives, theme tokens, tab bar, top nav bar
// iOS 26 style: layered backdrop-blur + specular highlight + 0.5pt hairline border.

// ─────────────────────────────────────────────────────────────
// Theme helpers
// ─────────────────────────────────────────────────────────────
function getTheme(t) {
  const dark = t.theme === 'dark';
  return {
    dark,
    // Surfaces
    bg: dark ? '#000' : '#F2F2F7',
    bgElev: dark ? '#1C1C1E' : '#FFFFFF',
    bgElev2: dark ? '#2C2C2E' : '#F2F2F7',
    cardBg: dark ? 'rgba(28,28,30,0.72)' : 'rgba(255,255,255,0.84)',
    // Text
    fg: dark ? '#FFFFFF' : '#000000',
    fgMuted: dark ? 'rgba(235,235,245,0.6)' : 'rgba(60,60,67,0.6)',
    fgFaint: dark ? 'rgba(235,235,245,0.3)' : 'rgba(60,60,67,0.3)',
    // Lines
    hairline: dark ? 'rgba(84,84,88,0.65)' : 'rgba(60,60,67,0.12)',
    // Accent
    accent: t.accent,
    onAccent: '#FFFFFF',
    // Glass
    glass: dark ? 'rgba(40,40,44,0.55)' : 'rgba(255,255,255,0.55)',
    glassHi: dark ? 'rgba(60,60,66,0.7)' : 'rgba(255,255,255,0.78)',
    glassBorder: dark ? 'rgba(255,255,255,0.12)' : 'rgba(255,255,255,0.55)',
    glassBorderDark: dark ? 'rgba(0,0,0,0.35)' : 'rgba(0,0,0,0.08)',
    // Standard system semantics
    red: '#FF453A',
    orange: '#FF9F0A',
    yellow: '#FFD60A',
    green: '#30D158',
    mint: '#63E6E2',
    cyan: '#64D2FF',
    blue: '#0A84FF',
    purple: '#BF5AF2',
    pink: '#FF375F',
  };
}

// Liquid Glass intensity → blur+saturation
function glassMaterial(intensity, dark) {
  const cfg = {
    subtle:   { blur: 18, sat: 140, alphaL: 0.62, alphaD: 0.48 },
    moderate: { blur: 32, sat: 180, alphaL: 0.55, alphaD: 0.55 },
    maximal:  { blur: 48, sat: 220, alphaL: 0.42, alphaD: 0.6  },
  }[intensity] || { blur: 32, sat: 180, alphaL: 0.55, alphaD: 0.55 };
  return {
    backdropFilter: `blur(${cfg.blur}px) saturate(${cfg.sat}%)`,
    WebkitBackdropFilter: `blur(${cfg.blur}px) saturate(${cfg.sat}%)`,
    background: dark
      ? `rgba(38,38,42,${cfg.alphaD})`
      : `rgba(255,255,255,${cfg.alphaL})`,
  };
}

// ─────────────────────────────────────────────────────────────
// GlassSurface — the universal Liquid Glass building block.
// Stack: backdrop blur layer + specular highlight layer + content layer.
// ─────────────────────────────────────────────────────────────
function GlassSurface({
  children, dark = false, radius = 24, intensity = 'moderate',
  style = {}, tint = null, padding = 0, onClick, role,
}) {
  const mat = glassMaterial(intensity, dark);
  return (
    <div role={role} onClick={onClick} style={{
      position: 'relative', borderRadius: radius, overflow: 'hidden',
      padding, cursor: onClick ? 'pointer' : undefined,
      isolation: 'isolate',
      ...style,
    }}>
      {/* L1: blur + tint */}
      <div style={{
        position: 'absolute', inset: 0, borderRadius: radius,
        ...mat,
      }} />
      {/* L2: tweakable global tint (driven by CSS vars set on the device root) */}
      <div style={{
        position: 'absolute', inset: 0, borderRadius: radius,
        background: 'var(--glass-tint, transparent)',
        opacity: 'var(--glass-tint-alpha, 0)',
        mixBlendMode: dark ? 'screen' : 'multiply',
        pointerEvents: 'none',
      }} />
      {/* L2b: optional per-instance accent tint */}
      {tint && (
        <div style={{
          position: 'absolute', inset: 0, borderRadius: radius,
          background: tint, mixBlendMode: dark ? 'screen' : 'multiply', opacity: 0.18,
        }} />
      )}
      {/* L3: specular highlight + hairline */}
      <div style={{
        position: 'absolute', inset: 0, borderRadius: radius,
        boxShadow: dark
          ? 'inset 0 0.5px 0 0 rgba(255,255,255,0.18), inset 0 -0.5px 0 0 rgba(0,0,0,0.4)'
          : 'inset 0 0.5px 0 0 rgba(255,255,255,0.85), inset 0 -0.5px 0 0 rgba(0,0,0,0.06)',
        border: dark
          ? '0.5px solid rgba(255,255,255,0.14)'
          : '0.5px solid rgba(255,255,255,0.55)',
        pointerEvents: 'none',
      }} />
      {/* L4: subtle top-left highlight gradient for refraction feel */}
      <div style={{
        position: 'absolute', inset: 0, borderRadius: radius,
        background: dark
          ? 'linear-gradient(135deg, rgba(255,255,255,0.10) 0%, rgba(255,255,255,0) 35%, rgba(255,255,255,0) 65%, rgba(255,255,255,0.04) 100%)'
          : 'linear-gradient(135deg, rgba(255,255,255,0.55) 0%, rgba(255,255,255,0) 40%, rgba(255,255,255,0) 60%, rgba(255,255,255,0.3) 100%)',
        pointerEvents: 'none', mixBlendMode: 'overlay',
      }} />
      <div style={{ position: 'relative', zIndex: 1, width: '100%', height: '100%' }}>{children}</div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Solid card (non-glass) — used for content cards on Home
// ─────────────────────────────────────────────────────────────
function Card({ children, dark, radius = 22, style = {}, padding = 16, onClick }) {
  return (
    <div onClick={onClick} style={{
      background: dark ? '#1C1C1E' : '#FFFFFF',
      borderRadius: radius,
      padding,
      cursor: onClick ? 'pointer' : undefined,
      boxShadow: dark
        ? '0 1px 0 rgba(255,255,255,0.04) inset, 0 8px 24px rgba(0,0,0,0.4)'
        : '0 0.5px 0 rgba(255,255,255,0.6) inset, 0 2px 8px rgba(0,0,0,0.04)',
      ...style,
    }}>{children}</div>
  );
}

// ─────────────────────────────────────────────────────────────
// Glass pill button — used in nav bars
// ─────────────────────────────────────────────────────────────
function GlassPill({ children, dark, intensity = 'moderate', size = 44, onClick, style = {} }) {
  return (
    <GlassSurface dark={dark} intensity={intensity} radius={9999}
      onClick={onClick}
      style={{ height: size, minWidth: size, ...style }}>
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        height: '100%', width: '100%', padding: '0 8px', boxSizing: 'border-box',
      }}>
        {children}
      </div>
    </GlassSurface>
  );
}

// ─────────────────────────────────────────────────────────────
// Status bar (clone — keeps icons consistent w/ tweak themes)
// ─────────────────────────────────────────────────────────────
function StatusBar({ dark = false, time = '9:41' }) {
  const c = dark ? '#fff' : '#000';
  return (
    <div style={{
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      padding: '14px 28px 4px 32px', boxSizing: 'border-box',
      position: 'relative', zIndex: 20, width: '100%', pointerEvents: 'none',
    }}>
      <span style={{
        fontFamily: '-apple-system, "SF Pro", system-ui', fontWeight: 600,
        fontSize: 17, lineHeight: '22px', color: c, letterSpacing: -0.3,
      }}>{time}</span>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
        <svg width="18" height="11" viewBox="0 0 19 12">
          <rect x="0" y="7.5" width="3" height="4.5" rx="0.7" fill={c}/>
          <rect x="4.8" y="5" width="3" height="7" rx="0.7" fill={c}/>
          <rect x="9.6" y="2.5" width="3" height="9.5" rx="0.7" fill={c}/>
          <rect x="14.4" y="0" width="3" height="12" rx="0.7" fill={c}/>
        </svg>
        <svg width="16" height="11" viewBox="0 0 17 12">
          <path d="M8.5 3.2C10.8 3.2 12.9 4.1 14.4 5.6L15.5 4.5C13.7 2.7 11.2 1.5 8.5 1.5C5.8 1.5 3.3 2.7 1.5 4.5L2.6 5.6C4.1 4.1 6.2 3.2 8.5 3.2Z" fill={c}/>
          <path d="M8.5 6.8C9.9 6.8 11.1 7.3 12 8.2L13.1 7.1C11.8 5.9 10.2 5.1 8.5 5.1C6.8 5.1 5.2 5.9 3.9 7.1L5 8.2C5.9 7.3 7.1 6.8 8.5 6.8Z" fill={c}/>
          <circle cx="8.5" cy="10.5" r="1.5" fill={c}/>
        </svg>
        <svg width="26" height="12" viewBox="0 0 27 13">
          <rect x="0.5" y="0.5" width="23" height="12" rx="3.5" stroke={c} strokeOpacity="0.35" fill="none"/>
          <rect x="2" y="2" width="20" height="9" rx="2" fill={c}/>
          <path d="M25 4.5V8.5C25.8 8.2 26.5 7.2 26.5 6.5C26.5 5.8 25.8 4.8 25 4.5Z" fill={c} fillOpacity="0.4"/>
        </svg>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// SF Symbol-ish icon set (drawn as inline SVG; multi-stroke)
// ─────────────────────────────────────────────────────────────
const Icons = {
  home: (c) => <svg width="24" height="24" viewBox="0 0 24 24" fill="none">
    <path d="M3 11.5L12 4l9 7.5V20a1 1 0 01-1 1h-5v-6h-6v6H4a1 1 0 01-1-1v-8.5z"
      stroke={c} strokeWidth="1.8" strokeLinejoin="round"/>
  </svg>,
  homeFill: (c) => <svg width="24" height="24" viewBox="0 0 24 24">
    <path d="M3 11.2L12 4l9 7.2V20a1 1 0 01-1 1h-4.5v-5.5a1 1 0 00-1-1h-5a1 1 0 00-1 1V21H4a1 1 0 01-1-1v-8.8z" fill={c}/>
  </svg>,
  chat: (c) => <svg width="24" height="24" viewBox="0 0 24 24" fill="none">
    <path d="M3 11c0-4.4 4-8 9-8s9 3.6 9 8-4 8-9 8c-1.1 0-2.2-.2-3.2-.5L4 21l1.3-4.2C4 15.4 3 13.3 3 11z" stroke={c} strokeWidth="1.8" strokeLinejoin="round"/>
    <circle cx="8" cy="11" r="1" fill={c}/><circle cx="12" cy="11" r="1" fill={c}/><circle cx="16" cy="11" r="1" fill={c}/>
  </svg>,
  chatFill: (c) => <svg width="24" height="24" viewBox="0 0 24 24">
    <path d="M3 11c0-4.4 4-8 9-8s9 3.6 9 8-4 8-9 8c-1.1 0-2.2-.2-3.2-.5L4 21l1.3-4.2C4 15.4 3 13.3 3 11z" fill={c}/>
    <circle cx="8" cy="11" r="1" fill="#fff"/><circle cx="12" cy="11" r="1" fill="#fff"/><circle cx="16" cy="11" r="1" fill="#fff"/>
  </svg>,
  bell: (c) => <svg width="24" height="24" viewBox="0 0 24 24" fill="none">
    <path d="M6 17V11a6 6 0 0112 0v6l1.5 2h-15L6 17z" stroke={c} strokeWidth="1.8" strokeLinejoin="round"/>
    <path d="M10 21a2 2 0 004 0" stroke={c} strokeWidth="1.8" strokeLinecap="round"/>
  </svg>,
  bellFill: (c) => <svg width="24" height="24" viewBox="0 0 24 24">
    <path d="M6 17V11a6 6 0 0112 0v6l1.5 2h-15L6 17zM10 21a2 2 0 004 0H10z" fill={c}/>
  </svg>,
  person: (c) => <svg width="24" height="24" viewBox="0 0 24 24" fill="none">
    <circle cx="12" cy="8" r="4" stroke={c} strokeWidth="1.8"/>
    <path d="M4 21c0-4.4 3.6-8 8-8s8 3.6 8 8" stroke={c} strokeWidth="1.8" strokeLinecap="round"/>
  </svg>,
  personFill: (c) => <svg width="24" height="24" viewBox="0 0 24 24">
    <circle cx="12" cy="8" r="4" fill={c}/>
    <path d="M4 21c0-4.4 3.6-8 8-8s8 3.6 8 8" stroke={c} strokeWidth="3" fill="none" strokeLinecap="round"/>
  </svg>,
  heart: (c, size = 18) => <svg width={size} height={size} viewBox="0 0 24 24" fill={c}>
    <path d="M12 21s-7-4.5-9.5-9C.5 8 3 4 7 4c2 0 3.5 1 5 3 1.5-2 3-3 5-3 4 0 6.5 4 4.5 8-2.5 4.5-9.5 9-9.5 9z"/>
  </svg>,
  bolt: (c, size = 18) => <svg width={size} height={size} viewBox="0 0 24 24" fill={c}>
    <path d="M13 2L4 14h6l-1 8 9-12h-6l1-8z"/>
  </svg>,
  moon: (c, size = 18) => <svg width={size} height={size} viewBox="0 0 24 24" fill={c}>
    <path d="M21 13A9 9 0 1111 3a7 7 0 0010 10z"/>
  </svg>,
  flame: (c, size = 18) => <svg width={size} height={size} viewBox="0 0 24 24" fill={c}>
    <path d="M12 2c1 4 5 5 5 10a5 5 0 11-10 0c0-2 1-3 1-5 0-1-1-2-1-2s5 0 5-3z"/>
  </svg>,
  drop: (c, size = 18) => <svg width={size} height={size} viewBox="0 0 24 24" fill={c}>
    <path d="M12 2C8 8 5 11.5 5 15a7 7 0 1014 0c0-3.5-3-7-7-13z"/>
  </svg>,
  walk: (c, size = 18) => <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <circle cx="13" cy="4" r="2"/><path d="M14 22l-2-7-2 3-3 1"/><path d="M14 15l-2-3 3-4 3 3 3 1"/>
  </svg>,
  recovery: (c, size = 18) => <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
    <path d="M21 12a9 9 0 11-3-6.7"/><path d="M21 4v5h-5"/>
  </svg>,
  sparkle: (c, size = 18) => <svg width={size} height={size} viewBox="0 0 24 24" fill={c}>
    <path d="M12 2l1.8 5.2L19 9l-5.2 1.8L12 16l-1.8-5.2L5 9l5.2-1.8L12 2zM19 14l.9 2.6L22 17.5l-2.1.9L19 21l-.9-2.6L16 17.5l2.1-.9L19 14z"/>
  </svg>,
  cal: (c, size = 18) => <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="1.8" strokeLinecap="round">
    <rect x="3" y="5" width="18" height="16" rx="3"/><path d="M3 10h18M8 3v4M16 3v4"/>
  </svg>,
  chev: (c, size = 14) => <svg width={size/2} height={size} viewBox="0 0 8 14" fill="none">
    <path d="M1 1l6 6-6 6" stroke={c} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
  </svg>,
  add: (c, size = 22) => <svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <path d="M12 5v14M5 12h14" stroke={c} strokeWidth="2.2" strokeLinecap="round"/>
  </svg>,
  send: (c, size = 22) => <svg width={size} height={size} viewBox="0 0 24 24" fill={c}>
    <path d="M3 11.5L21 3l-5 18-4-8-9-1.5z"/>
  </svg>,
  mic: (c, size = 22) => <svg width={size} height={size} viewBox="0 0 24 24" fill={c}>
    <rect x="9" y="3" width="6" height="12" rx="3"/>
    <path d="M5 11a7 7 0 0014 0M12 18v3" stroke={c} strokeWidth="2" fill="none" strokeLinecap="round"/>
  </svg>,
  back: (c, size = 22) => <svg width={size/1.4} height={size} viewBox="0 0 12 20" fill="none">
    <path d="M10 2L2 10l8 8" stroke={c} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round"/>
  </svg>,
  more: (c) => <svg width="20" height="6" viewBox="0 0 22 6">
    <circle cx="3" cy="3" r="2.5" fill={c}/>
    <circle cx="11" cy="3" r="2.5" fill={c}/>
    <circle cx="19" cy="3" r="2.5" fill={c}/>
  </svg>,
  check: (c, size = 18) => <svg width={size} height={size} viewBox="0 0 24 24" fill="none">
    <path d="M4 12l5 5L20 6" stroke={c} strokeWidth="2.6" strokeLinecap="round" strokeLinejoin="round"/>
  </svg>,
  ring: (c, size = 18) => <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2.5">
    <circle cx="12" cy="12" r="9"/>
  </svg>,
  pill: (c, size = 18) => <svg width={size} height={size} viewBox="0 0 24 24" fill={c}>
    <path d="M10 2a6 6 0 016 6v8a6 6 0 11-12 0V8a6 6 0 016-6zm0 2a4 4 0 00-4 4v4h8V8a4 4 0 00-4-4z"/>
  </svg>,
  apple: (c, size = 20) => <svg width={size} height={size} viewBox="0 0 24 24" fill={c}>
    <path d="M17.05 12.04c-.03-2.92 2.39-4.32 2.5-4.39-1.36-1.99-3.49-2.26-4.24-2.29-1.81-.18-3.53 1.07-4.44 1.07-.94 0-2.34-1.05-3.85-1.02-1.98.03-3.81 1.15-4.83 2.92-2.07 3.58-.53 8.86 1.47 11.77 1.01 1.42 2.2 3.01 3.74 2.95 1.51-.06 2.08-.97 3.91-.97 1.83 0 2.34.97 3.92.94 1.63-.03 2.65-1.43 3.64-2.85 1.16-1.62 1.63-3.21 1.65-3.3-.04-.02-3.16-1.21-3.19-4.83zM14.27 3.2c.81-1 1.36-2.36 1.21-3.73-1.18.05-2.62.79-3.45 1.77-.75.86-1.41 2.27-1.24 3.6 1.32.1 2.66-.66 3.48-1.64z"/>
  </svg>,
  google: (size = 20) => <svg width={size} height={size} viewBox="0 0 24 24">
    <path d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z" fill="#4285F4"/>
    <path d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.99.66-2.25 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z" fill="#34A853"/>
    <path d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z" fill="#FBBC05"/>
    <path d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z" fill="#EA4335"/>
  </svg>,
  face: (c) => <svg width="42" height="42" viewBox="0 0 42 42" fill="none">
    <rect x="2" y="2" width="38" height="38" rx="10" stroke={c} strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round" strokeDasharray="8 10"/>
    <circle cx="15" cy="17" r="1.5" fill={c}/><circle cx="27" cy="17" r="1.5" fill={c}/>
    <path d="M14 25c1.5 2 3.5 3 7 3s5.5-1 7-3" stroke={c} strokeWidth="2" strokeLinecap="round"/>
  </svg>,
  search: (c, size = 18) => <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2" strokeLinecap="round">
    <circle cx="11" cy="11" r="7"/><path d="M16 16l4 4"/>
  </svg>,
  watch: (c, size = 18) => <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="1.8">
    <rect x="6" y="6" width="12" height="12" rx="3"/><path d="M9 6V3h6v3M9 18v3h6v-3" strokeLinecap="round"/>
  </svg>,
  shield: (c, size = 18) => <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="1.8" strokeLinejoin="round">
    <path d="M12 3l8 3v6c0 5-3.5 8.5-8 9-4.5-.5-8-4-8-9V6l8-3z"/>
  </svg>,
};

window.GlassSurface = GlassSurface;
window.Card = Card;
window.GlassPill = GlassPill;
window.StatusBar = StatusBar;
window.Icons = Icons;
window.getTheme = getTheme;
window.glassMaterial = glassMaterial;
