// watch.jsx — Fitness Guru · watchOS 26
//
// Apple Watch Series 10 (42 + 46mm) and Ultra 2 (49mm).
// Native watchOS UI patterns — no card chrome, edge-to-edge content,
// color-coded numerals, list rows like the Workout app.

// ─────────────────────────────────────────────────────────────
// Tweak store
// ─────────────────────────────────────────────────────────────
const W_TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "accent": "#30D158",
  "userName": "Alex"
}/*EDITMODE-END*/;
const wStore = {
  state: { ...W_TWEAK_DEFAULTS },
  listeners: new Set(),
  subscribe(fn) { this.listeners.add(fn); return () => this.listeners.delete(fn); },
  getSnapshot() { return this.state; },
  set(k, v) {
    const edits = (typeof k === 'object' && k !== null) ? k : { [k]: v };
    this.state = { ...this.state, ...edits };
    try { window.parent.postMessage({ type: '__edit_mode_set_keys', edits }, '*'); } catch {}
    this.listeners.forEach(fn => fn());
  },
};
function useW() {
  React.useSyncExternalStore((cb) => wStore.subscribe(cb), () => wStore.state);
  return [wStore.state, wStore.set.bind(wStore)];
}
const hexA = (c, a) => c + Math.round(a*255).toString(16).padStart(2,'0');

// SF-style numeric stack
const num = {
  fontFamily: 'ui-rounded, "SF Pro Rounded", -apple-system, "SF Compact Rounded", system-ui, sans-serif',
  fontFeatureSettings: '"tnum" 1, "ss01" 1',
  fontVariantNumeric: 'tabular-nums',
};
const ROUND = 'ui-rounded, "SF Pro Rounded", -apple-system, system-ui, sans-serif';

// ─────────────────────────────────────────────────────────────
// Frame
// ─────────────────────────────────────────────────────────────
function WatchFrame({ kind = 'series', size = 'large', children }) {
  const dims = {
    series_sm: { w: 374, h: 446, r: 70, bezel: 8,  crown: 70 },
    series_lg: { w: 416, h: 496, r: 76, bezel: 9,  crown: 80 },
    ultra:     { w: 410, h: 502, r: 56, bezel: 16, crown: 92 },
  };
  const cfg = kind === 'ultra' ? dims.ultra : (size === 'large' ? dims.series_lg : dims.series_sm);
  const isUltra = kind === 'ultra';
  const caseFill = isUltra
    ? 'linear-gradient(155deg, #3a3631 0%, #534b41 18%, #8a7d6c 35%, #3a3631 55%, #6e6557 72%, #2c2823 100%)'
    : 'linear-gradient(155deg, #1d1d1f 0%, #3a3a3c 22%, #6e6e72 40%, #2a2a2c 60%, #4a4a4c 78%, #1a1a1c 100%)';

  return (
    <div style={{
      width: cfg.w + cfg.bezel * 2 + 24,
      height: cfg.h + cfg.bezel * 2 + 16,
      position: 'relative',
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      fontFamily: ROUND, WebkitFontSmoothing: 'antialiased',
      padding: 8, boxSizing: 'border-box',
    }}>
      <div style={{
        position: 'relative',
        width: cfg.w + cfg.bezel * 2, height: cfg.h + cfg.bezel * 2,
        borderRadius: cfg.r + cfg.bezel,
        background: caseFill,
        boxShadow: '0 30px 80px rgba(0,0,0,0.55), 0 1px 0 rgba(255,255,255,0.2) inset, 0 -1px 0 rgba(0,0,0,0.6) inset, 0 0 0 1px rgba(0,0,0,0.4)',
        padding: cfg.bezel, boxSizing: 'content-box',
      }}>
        {/* Display */}
        <div style={{
          width: cfg.w, height: cfg.h, borderRadius: cfg.r,
          background: '#000', overflow: 'hidden', position: 'relative', color: '#fff',
          boxShadow: 'inset 0 0 0 1px rgba(0,0,0,0.9), inset 0 4px 12px rgba(0,0,0,0.5)',
        }}>
          {children}
        </div>
        {/* Digital crown */}
        <div style={{
          position: 'absolute', right: -10, top: cfg.h * 0.30,
          width: 12, height: cfg.crown, borderRadius: 3,
          background: isUltra
            ? 'linear-gradient(90deg, #1f1c18 0%, #6e6557 35%, #a89a83 50%, #6e6557 65%, #1f1c18 100%)'
            : 'linear-gradient(90deg, #1a1a1c 0%, #4a4a4c 35%, #8a8a8c 50%, #4a4a4c 65%, #1a1a1c 100%)',
          boxShadow: '0 2px 6px rgba(0,0,0,0.5), inset 0 0.5px 0 rgba(255,255,255,0.25)',
        }}>
          <div style={{
            position: 'absolute', left: 0, right: 0, top: '10%', bottom: '10%',
            background: 'repeating-linear-gradient(180deg, transparent 0 3px, rgba(0,0,0,0.45) 3px 4px)',
            borderRadius: 3,
          }}/>
        </div>
        {/* Side button */}
        <div style={{
          position: 'absolute', right: -6, top: cfg.h * 0.30 + cfg.crown + 26,
          width: 9, height: 58, borderRadius: 3,
          background: 'linear-gradient(90deg, #1a1a1c 0%, #3a3a3c 50%, #1a1a1c 100%)',
          boxShadow: '0 1px 3px rgba(0,0,0,0.45)',
        }}/>
        {/* Action button (Ultra) */}
        {isUltra && (
          <div style={{
            position: 'absolute', left: -9, top: cfg.h * 0.42,
            width: 11, height: 72, borderRadius: 3,
            background: 'linear-gradient(90deg, #a83d12 0%, #ff7a2a 50%, #c44d18 100%)',
            boxShadow: '0 1px 3px rgba(0,0,0,0.4), inset 0 1px 0 rgba(255,255,255,0.2)',
          }}/>
        )}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Native primitives
// ─────────────────────────────────────────────────────────────

// Stat tower row — used in Workout, Complete (no chrome, just two text columns)
function StatTower({ color, value, label, unit }) {
  return (
    <div style={{ display: 'flex', flexDirection: 'column', lineHeight: 1, marginBottom: 4 }}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 4 }}>
        <span style={{
          fontSize: 38, fontWeight: 700, color, letterSpacing: -1.8, ...num,
        }}>{value}</span>
        {unit && (
          <span style={{ fontSize: 12, fontWeight: 600, color, letterSpacing: -0.2 }}>{unit}</span>
        )}
      </div>
      <div style={{
        fontSize: 11, fontWeight: 600, color: 'rgba(255,255,255,0.55)',
        letterSpacing: -0.1, marginTop: 2,
      }}>{label}</div>
    </div>
  );
}

// Page dots vertical (watchOS standard)
function PageDots({ count = 4, active = 0 }) {
  return (
    <div style={{
      position: 'absolute', right: 4, top: '50%', transform: 'translateY(-50%)',
      display: 'flex', flexDirection: 'column', gap: 5,
      pointerEvents: 'none', zIndex: 5,
    }}>
      {[...Array(count)].map((_, i) => (
        <div key={i} style={{
          width: 4, height: 4, borderRadius: 999,
          background: i === active ? '#fff' : 'rgba(255,255,255,0.28)',
        }}/>
      ))}
    </div>
  );
}

// Status header (like Apple Workout app top): centered time only, no fluff
function StatusHeader({ time = '10:09', tint }) {
  return (
    <div style={{
      position: 'absolute', top: 0, left: 0, right: 0,
      display: 'flex', justifyContent: 'center', padding: '6px 0',
      pointerEvents: 'none', zIndex: 4,
    }}>
      <span style={{
        fontSize: 14, fontWeight: 700, color: tint || '#fff', letterSpacing: -0.2, ...num,
      }}>{time}</span>
    </div>
  );
}

// Back chevron (watchOS) — green/accent at top-left
function BackChev({ accent, label = 'Back' }) {
  return (
    <div style={{
      position: 'absolute', top: 6, left: 8, display: 'flex', alignItems: 'center', gap: 2,
      fontSize: 13, fontWeight: 600, color: accent, zIndex: 5,
    }}>
      <svg width="10" height="14" viewBox="0 0 12 20" fill="none">
        <path d="M10 2L2 10l8 8" stroke={accent} strokeWidth="2.4" strokeLinecap="round" strokeLinejoin="round"/>
      </svg>
      <span>{label}</span>
    </div>
  );
}

// Rings
function WRings({ size = 96, stroke = 9, vals = [0.78, 0.62, 0.95], colors }) {
  const c = colors || ['#FA114F', '#9FE830', '#00D4FF'];
  const r1 = size/2 - stroke*0.55;
  const r2 = r1 - stroke - 3;
  const r3 = r2 - stroke - 3;
  const ring = (r, v, col) => {
    const C = 2*Math.PI*r;
    return (
      <g transform={`rotate(-90 ${size/2} ${size/2})`}>
        <circle cx={size/2} cy={size/2} r={r} fill="none" stroke={col} strokeOpacity="0.14" strokeWidth={stroke}/>
        <circle cx={size/2} cy={size/2} r={r} fill="none" stroke={col} strokeWidth={stroke}
          strokeDasharray={`${C*Math.min(v,1)} ${C}`} strokeLinecap="round"/>
      </g>
    );
  };
  return <svg width={size} height={size}>{ring(r1, vals[0], c[0])}{ring(r2, vals[1], c[1])}{ring(r3, vals[2], c[2])}</svg>;
}

// ─────────────────────────────────────────────────────────────
// SCREEN 1 — Watch face (Modular Ultra-style)
// ─────────────────────────────────────────────────────────────
function WatchFace({ accent, kind }) {
  const isUltra = kind === 'ultra';
  return (
    <div style={{
      width: '100%', height: '100%', position: 'relative', background: '#000',
      padding: isUltra ? '18px 16px' : '14px 12px',
      boxSizing: 'border-box',
      display: 'flex', flexDirection: 'column',
    }}>
      {/* Top corner data */}
      <div style={{
        display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start',
      }}>
        <div style={{ display: 'flex', flexDirection: 'column', lineHeight: 1.1 }}>
          <span style={{ fontSize: 12, fontWeight: 700, color: accent, letterSpacing: 0.4, ...num }}>TUE 14</span>
          <span style={{ fontSize: 11, fontWeight: 600, color: 'rgba(255,255,255,0.55)', letterSpacing: 0.5, marginTop: 1 }}>OCTOBER</span>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', alignItems: 'flex-end', lineHeight: 1.1 }}>
          <span style={{ fontSize: 14, fontWeight: 700, color: '#FA114F', letterSpacing: -0.3, ...num }}>72</span>
          <span style={{ fontSize: 10, fontWeight: 700, color: 'rgba(255,255,255,0.55)', letterSpacing: 0.7, marginTop: 1 }}>BPM</span>
        </div>
      </div>

      {/* Time, centered */}
      <div style={{
        flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'center', alignItems: 'flex-start',
      }}>
        <div style={{
          fontSize: isUltra ? 108 : 94, fontWeight: 700, color: accent,
          letterSpacing: -6, lineHeight: 0.85, ...num,
        }}>
          10<span style={{ opacity: 0.5 }}>:</span>09
        </div>
      </div>

      {/* Bottom: rings + 3 lines of contextual data (Modular face) */}
      <div style={{ display: 'flex', alignItems: 'flex-end', gap: 12 }}>
        <WRings size={isUltra ? 64 : 56} stroke={isUltra ? 7 : 6}/>
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 1, paddingBottom: 2 }}>
          <FaceLine color={accent} title="ZONE 2 RUN" detail="6:30 PM · 45 min"/>
          <div style={{ height: 0.5, background: 'rgba(255,255,255,0.12)', margin: '3px 0' }}/>
          <FaceLine color="#FFD60A" title="RECOVERY 74" detail="Push intensity"/>
        </div>
      </div>
    </div>
  );
}

function FaceLine({ color, title, detail }) {
  return (
    <div style={{ display: 'flex', alignItems: 'baseline', gap: 6, minWidth: 0 }}>
      <span style={{
        fontSize: 11, fontWeight: 700, color, letterSpacing: 0.3, whiteSpace: 'nowrap',
      }}>{title}</span>
      <span style={{
        fontSize: 10, fontWeight: 500, color: 'rgba(255,255,255,0.55)', overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap',
      }}>{detail}</span>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// SCREEN 2 — Activity (rings + 3 stacked color-coded lines)
// ─────────────────────────────────────────────────────────────
function WatchHome({ accent }) {
  return (
    <div style={{
      width: '100%', height: '100%', position: 'relative', background: '#000',
      paddingTop: 26, boxSizing: 'border-box',
      display: 'flex', flexDirection: 'column',
    }}>
      <StatusHeader/>

      {/* Big rings */}
      <div style={{ display: 'flex', justifyContent: 'center', padding: '4px 0 6px' }}>
        <WRings size={150} stroke={12}/>
      </div>

      {/* Three color-coded stacked lines — no chrome */}
      <div style={{ padding: '0 16px', display: 'flex', flexDirection: 'column', gap: 4 }}>
        <ActivityLine color="#FA114F" label="MOVE" v="486" u="/600 CAL"/>
        <ActivityLine color="#9FE830" label="EXERCISE" v="19" u="/30 MIN"/>
        <ActivityLine color="#00D4FF" label="STAND" v="11" u="/12 HR"/>
      </div>

      <PageDots count={4} active={0}/>
    </div>
  );
}

function ActivityLine({ color, label, v, u }) {
  return (
    <div>
      <div style={{ fontSize: 11, fontWeight: 700, color, letterSpacing: 0.5 }}>{label}</div>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 3, ...num }}>
        <span style={{ fontSize: 24, fontWeight: 700, color, letterSpacing: -0.8, lineHeight: 1 }}>{v}</span>
        <span style={{ fontSize: 11, fontWeight: 600, color: 'rgba(255,255,255,0.55)', letterSpacing: 0.2 }}>{u}</span>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// SCREEN 3 — Workouts list (native Workout app)
// ─────────────────────────────────────────────────────────────
function WatchWorkouts({ accent }) {
  const list = [
    { name: 'Outdoor Run',   meta: '5.2 mi · last Sun',    icon: 'run',      color: accent },
    { name: 'Indoor Cycle',  meta: '40 min · last Tue',    icon: 'cycle',    color: '#FF9F0A' },
    { name: 'Strength',      meta: 'Upper · last Mon',     icon: 'strength', color: '#FA114F' },
    { name: 'HIIT',          meta: '20 min · last Sat',    icon: 'bolt',     color: '#BF5AF2' },
    { name: 'Yoga',          meta: 'Mobility',             icon: 'yoga',     color: '#64D2FF' },
  ];
  const ico = (k, c) => {
    if (k === 'run') return <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2.2" strokeLinecap="round" strokeLinejoin="round"><circle cx="13" cy="4" r="2" fill={c}/><path d="M14 22l-2-7-2 3-3 1M14 15l-2-3 3-4 3 3 3 1"/></svg>;
    if (k === 'cycle') return <svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke={c} strokeWidth="2.2" strokeLinecap="round"><circle cx="6" cy="17" r="3.5"/><circle cx="18" cy="17" r="3.5"/><path d="M6 17l5-9h6l3 9M11 8l4 0"/></svg>;
    if (k === 'strength') return <svg width="22" height="22" viewBox="0 0 24 24" fill={c}><rect x="2" y="9" width="3" height="6" rx="1"/><rect x="19" y="9" width="3" height="6" rx="1"/><rect x="6" y="10.5" width="12" height="3" rx="1"/></svg>;
    if (k === 'bolt') return <svg width="22" height="22" viewBox="0 0 24 24" fill={c}><path d="M13 2L4 14h6l-1 8 9-12h-6l1-8z"/></svg>;
    return <svg width="22" height="22" viewBox="0 0 24 24" fill={c}><circle cx="12" cy="5" r="2"/><path d="M12 8c-3 0-5 2-5 5v9h10v-9c0-3-2-5-5-5z"/></svg>;
  };
  return (
    <div style={{
      width: '100%', height: '100%', position: 'relative', background: '#000',
      paddingTop: 24, boxSizing: 'border-box', overflow: 'hidden',
    }}>
      <StatusHeader/>
      <div style={{
        height: 'calc(100% - 24px)', overflow: 'auto',
        padding: '4px 10px 10px',
      }}>
        {list.map((w, i) => (
          <div key={i} style={{
            display: 'flex', alignItems: 'center', gap: 12,
            padding: '12px 6px',
            borderBottom: i < list.length - 1 ? '0.5px solid rgba(255,255,255,0.08)' : 'none',
          }}>
            <div style={{
              width: 42, height: 42, borderRadius: 999, flexShrink: 0,
              background: w.color, opacity: 0.92,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              boxShadow: `0 4px 14px ${hexA(w.color, 0.45)}`,
            }}>{ico(w.icon, '#000')}</div>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 16, fontWeight: 700, color: '#fff', letterSpacing: -0.3 }}>{w.name}</div>
              <div style={{ fontSize: 12, fontWeight: 500, color: 'rgba(255,255,255,0.55)', marginTop: 1 }}>{w.meta}</div>
            </div>
          </div>
        ))}
        {/* Add workout row */}
        <div style={{
          display: 'flex', alignItems: 'center', gap: 12, padding: '12px 6px',
        }}>
          <div style={{
            width: 42, height: 42, borderRadius: 999, flexShrink: 0,
            background: 'rgba(255,255,255,0.1)',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <svg width="20" height="20" viewBox="0 0 24 24" fill="none">
              <path d="M12 5v14M5 12h14" stroke="#fff" strokeWidth="2.4" strokeLinecap="round"/>
            </svg>
          </div>
          <div style={{ fontSize: 16, fontWeight: 600, color: '#fff', letterSpacing: -0.3 }}>Add workout</div>
        </div>
      </div>
      <PageDots count={4} active={1}/>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// SCREEN 4 — Active workout (native Workout-app metrics page)
// ─────────────────────────────────────────────────────────────
function WatchActive({ accent, kind }) {
  const isUltra = kind === 'ultra';
  // 4 color-coded metric towers stacked vertically, edge-to-edge on black.
  // Top: elapsed time (yellow). Next: distance + pace (green). Next: HR (red). Next: cal (orange).
  return (
    <div style={{
      width: '100%', height: '100%', position: 'relative', background: '#000',
      padding: '22px 16px 10px',
      boxSizing: 'border-box',
      display: 'flex', flexDirection: 'column',
    }}>
      {/* Tiny activity dot + workout type top right */}
      <div style={{
        position: 'absolute', top: 6, right: 12, display: 'flex', alignItems: 'center', gap: 4, zIndex: 4,
      }}>
        <div style={{ width: 6, height: 6, borderRadius: 999, background: '#FA114F', boxShadow: '0 0 8px #FA114F' }}/>
        <span style={{ fontSize: 11, fontWeight: 700, color: accent, letterSpacing: 0.4 }}>RUN</span>
      </div>

      <StatTower color="#FFD60A" value="14:32" label="Elapsed"/>
      <StatTower color="#9FE830" value="2.04" unit="MI" label="Distance"/>
      <StatTower color="#FA114F" value="142" unit="BPM" label="Heart rate"/>
      <StatTower color="#FF9F0A" value="186" unit="CAL" label="Active energy"/>

      <PageDots count={4} active={1}/>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// SCREEN 5 — Coach (Messages-style chat)
// ─────────────────────────────────────────────────────────────
function WatchCoach({ accent, userName }) {
  return (
    <div style={{
      width: '100%', height: '100%', position: 'relative', background: '#000',
      paddingTop: 24, boxSizing: 'border-box',
      display: 'flex', flexDirection: 'column',
    }}>
      <BackChev accent={accent} label="Done"/>
      <StatusHeader/>

      <div style={{ flex: 1, padding: '0 14px', display: 'flex', flexDirection: 'column', gap: 8, marginTop: 6, overflow: 'hidden' }}>
        {/* AI bubble */}
        <div style={{ display: 'flex', alignItems: 'center', gap: 5, marginTop: 4 }}>
          <div style={{
            width: 18, height: 18, borderRadius: 999,
            background: `linear-gradient(135deg, ${accent} 0%, #BF5AF2 100%)`,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <svg width="10" height="10" viewBox="0 0 24 24" fill="#fff">
              <path d="M12 2l1.8 5.2L19 9l-5.2 1.8L12 16l-1.8-5.2L5 9l5.2-1.8L12 2z"/>
            </svg>
          </div>
          <span style={{ fontSize: 11, fontWeight: 600, color: 'rgba(255,255,255,0.55)', letterSpacing: 0.2 }}>Coach</span>
        </div>
        <div style={{
          alignSelf: 'flex-start', maxWidth: '92%',
          padding: '10px 14px', borderRadius: 18, borderTopLeftRadius: 5,
          background: 'rgba(255,255,255,0.1)',
          fontSize: 14, fontWeight: 500, color: '#fff', lineHeight: 1.35, letterSpacing: -0.2,
        }}>
          Recovery's at 74. Push intensity today — your HRV is up 12%.
        </div>
        <div style={{
          alignSelf: 'flex-end', maxWidth: '88%',
          padding: '8px 14px', borderRadius: 18, borderTopRightRadius: 5,
          background: accent, color: '#000',
          fontSize: 13, fontWeight: 600, lineHeight: 1.32, letterSpacing: -0.1,
        }}>
          Plan day
        </div>
      </div>

      {/* Action bar — full-width tap targets */}
      <div style={{
        padding: '6px 10px 8px', display: 'flex', gap: 6, borderTop: '0.5px solid rgba(255,255,255,0.08)',
      }}>
        <ActionBtn color={accent} label="Reply"/>
        <ActionBtn color="rgba(255,255,255,0.1)" textColor="#fff" label="..."/>
      </div>
    </div>
  );
}

function ActionBtn({ color, textColor, label }) {
  return (
    <div style={{
      flex: 1, height: 36, borderRadius: 18, background: color,
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      fontSize: 13, fontWeight: 700, color: textColor || '#000', letterSpacing: -0.1,
    }}>{label}</div>
  );
}

// ─────────────────────────────────────────────────────────────
// SCREEN 6 — Workout complete (Activity-app summary list)
// ─────────────────────────────────────────────────────────────
function WatchComplete({ accent }) {
  return (
    <div style={{
      width: '100%', height: '100%', position: 'relative', background: '#000',
      paddingTop: 22, boxSizing: 'border-box',
      display: 'flex', flexDirection: 'column',
    }}>
      <StatusHeader/>

      {/* Hero: rings */}
      <div style={{ textAlign: 'center', padding: '4px 0 6px' }}>
        <div style={{ fontSize: 16, fontWeight: 700, color: '#fff', letterSpacing: -0.3 }}>Workout Saved</div>
        <div style={{ fontSize: 11, fontWeight: 700, color: accent, marginTop: 2, letterSpacing: 0.4 }}>OUTDOOR RUN</div>
      </div>

      {/* Stat list — full width, no chrome, divided */}
      <div style={{ flex: 1, padding: '6px 14px 0', display: 'flex', flexDirection: 'column', overflow: 'auto' }}>
        <SumRow color="#FFD60A" label="Total Time" value="38:42"/>
        <SumRow color="#9FE830" label="Distance" value="5.21" unit="MI"/>
        <SumRow color="#FF9F0A" label="Active Energy" value="486" unit="CAL"/>
        <SumRow color="#FA114F" label="Avg. Heart Rate" value="142" unit="BPM"/>
        <SumRow color={accent} label="Avg. Pace" value="7:25" unit="/MI"/>
      </div>

      {/* Done button */}
      <div style={{ padding: '6px 10px 8px' }}>
        <div style={{
          height: 38, borderRadius: 19, background: accent, color: '#000',
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          fontSize: 14, fontWeight: 700, letterSpacing: -0.2,
        }}>Done</div>
      </div>
    </div>
  );
}

function SumRow({ color, label, value, unit }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'baseline', justifyContent: 'space-between',
      padding: '8px 0', borderBottom: '0.5px solid rgba(255,255,255,0.08)',
    }}>
      <div style={{ fontSize: 12, fontWeight: 600, color: 'rgba(255,255,255,0.62)', letterSpacing: -0.1 }}>{label}</div>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 3 }}>
        <span style={{ fontSize: 17, fontWeight: 700, color, letterSpacing: -0.4, ...num }}>{value}</span>
        {unit && <span style={{ fontSize: 10, fontWeight: 700, color: 'rgba(255,255,255,0.55)', letterSpacing: 0.3 }}>{unit}</span>}
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// SCREEN 7 — Smart Stack (full-bleed widgets)
// ─────────────────────────────────────────────────────────────
function SmartStack({ accent }) {
  return (
    <div style={{
      width: '100%', height: '100%', position: 'relative', background: '#000',
      paddingTop: 24, boxSizing: 'border-box',
      display: 'flex', flexDirection: 'column', padding: '24px 8px 14px',
    }}>
      <StatusHeader/>
      <div style={{
        flex: 1, display: 'flex', flexDirection: 'column', gap: 6, overflow: 'hidden',
      }}>
        {/* Activity widget */}
        <Widget bg="#0a1f12" accent="#9FE830">
          <div style={{ display: 'flex', alignItems: 'center', gap: 10, padding: '10px 12px' }}>
            <WRings size={48} stroke={5}/>
            <div style={{ flex: 1, minWidth: 0 }}>
              <div style={{ fontSize: 11, fontWeight: 700, color: '#9FE830', letterSpacing: 0.5 }}>ACTIVITY</div>
              <div style={{ fontSize: 14, fontWeight: 700, color: '#fff', letterSpacing: -0.3, marginTop: 1 }}>
                486 / 600 CAL
              </div>
              <div style={{ fontSize: 11, fontWeight: 500, color: 'rgba(255,255,255,0.6)' }}>
                81% of goal · push it
              </div>
            </div>
          </div>
        </Widget>

        {/* Next workout widget */}
        <Widget bg={hexA(accent, 0.18)} accent={accent}>
          <div style={{ padding: '10px 12px', display: 'flex', alignItems: 'center', gap: 10 }}>
            <div style={{
              width: 44, height: 44, borderRadius: 12, flexShrink: 0,
              background: accent,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              boxShadow: `0 4px 14px ${hexA(accent, 0.55)}`,
            }}>
              <svg width="22" height="22" viewBox="0 0 24 24" fill="#000">
                <path d="M13 2L4 14h6l-1 8 9-12h-6l1-8z"/>
              </svg>
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 11, fontWeight: 700, color: accent, letterSpacing: 0.5 }}>UP NEXT</div>
              <div style={{ fontSize: 14, fontWeight: 700, color: '#fff', letterSpacing: -0.3, marginTop: 1 }}>
                Zone 2 run
              </div>
              <div style={{ fontSize: 11, fontWeight: 500, color: 'rgba(255,255,255,0.65)' }}>
                6:30 PM · 45 min
              </div>
            </div>
          </div>
        </Widget>

        {/* Hydration widget */}
        <Widget bg="#0a1820" accent="#64D2FF">
          <div style={{ padding: '10px 12px', display: 'flex', alignItems: 'center', gap: 10 }}>
            <div style={{
              width: 44, height: 44, borderRadius: 12, flexShrink: 0,
              background: 'rgba(100,210,255,0.2)',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>
              <svg width="22" height="22" viewBox="0 0 24 24" fill="#64D2FF">
                <path d="M12 2C8 8 5 11.5 5 15a7 7 0 1014 0c0-3.5-3-7-7-13z"/>
              </svg>
            </div>
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 11, fontWeight: 700, color: '#64D2FF', letterSpacing: 0.5 }}>HYDRATION</div>
              <div style={{ fontSize: 14, fontWeight: 700, color: '#fff', letterSpacing: -0.3, marginTop: 1 }}>
                1.4 L
              </div>
              <div style={{ fontSize: 11, fontWeight: 500, color: 'rgba(255,255,255,0.6)' }}>
                700 ml behind today
              </div>
            </div>
          </div>
        </Widget>
      </div>
    </div>
  );
}

function Widget({ bg, accent, children }) {
  return (
    <div style={{
      borderRadius: 22, background: bg,
      border: `0.5px solid ${hexA(accent, 0.25)}`,
      overflow: 'hidden',
    }}>{children}</div>
  );
}

// ─────────────────────────────────────────────────────────────
// Tweaks panel
// ─────────────────────────────────────────────────────────────
function WatchPanel() {
  const [t] = useW();
  const set = (k, v) => wStore.set(k, v);
  return (
    <TweaksPanel title="Watch app">
      <TweakSection label="Accent" />
      <TweakColor label="Accent" value={t.accent}
        options={['#30D158','#0A84FF','#FF2D55','#FF9F0A','#BF5AF2','#63E6E2','#FFD60A','#FA114F']}
        onChange={(v) => set('accent', v)} />
      <TweakSection label="User" />
      <TweakText label="Name" value={t.userName} onChange={(v) => set('userName', v)} />
    </TweaksPanel>
  );
}

// ─────────────────────────────────────────────────────────────
// Root canvas
// ─────────────────────────────────────────────────────────────
function WatchRoot() {
  const [t] = useW();

  const F = ({ kind = 'series', size = 'large', children }) => (
    <WatchFrame kind={kind} size={size}>{children}</WatchFrame>
  );

  const dimsFor = (kind, size) => {
    if (kind === 'ultra')  return { w: 466, h: 550 };
    if (size === 'small')  return { w: 414, h: 478 };
    return { w: 458, h: 528 };
  };
  const ult = dimsFor('ultra');
  const s46 = dimsFor('series','large');
  const s42 = dimsFor('series','small');

  return (
    <>
      <DesignCanvas>
        <DCSection id="hero" title="Fitness Guru · watchOS 26" subtitle="Series 10 (42 + 46mm) and Ultra 2 (49mm) — native watchOS UI.">
          <DCArtboard id="ultra-face" label="Ultra 2 · Watch face" width={ult.w} height={ult.h}>
            <F kind="ultra"><WatchFace accent={t.accent} kind="ultra"/></F>
          </DCArtboard>
          <DCArtboard id="s10-home" label="Series 10 46mm · Activity" width={s46.w} height={s46.h}>
            <F><WatchHome accent={t.accent}/></F>
          </DCArtboard>
          <DCArtboard id="ultra-active" label="Ultra 2 · Active workout" width={ult.w} height={ult.h}>
            <F kind="ultra"><WatchActive accent={t.accent} kind="ultra"/></F>
          </DCArtboard>
        </DCSection>

        <DCSection id="screens" title="All screens" subtitle="Watch face · Activity · Workouts · Active · Coach · Complete · Smart Stack">
          <DCArtboard id="s-face" label="Watch face" width={s46.w} height={s46.h}>
            <F><WatchFace accent={t.accent} kind="series"/></F>
          </DCArtboard>
          <DCArtboard id="s-home" label="Activity" width={s46.w} height={s46.h}>
            <F><WatchHome accent={t.accent}/></F>
          </DCArtboard>
          <DCArtboard id="s-workouts" label="Workouts" width={s46.w} height={s46.h}>
            <F><WatchWorkouts accent={t.accent}/></F>
          </DCArtboard>
          <DCArtboard id="s-active" label="Active workout" width={s46.w} height={s46.h}>
            <F><WatchActive accent={t.accent}/></F>
          </DCArtboard>
          <DCArtboard id="s-coach" label="Coach" width={s46.w} height={s46.h}>
            <F><WatchCoach accent={t.accent} userName={t.userName}/></F>
          </DCArtboard>
          <DCArtboard id="s-complete" label="Workout complete" width={s46.w} height={s46.h}>
            <F><WatchComplete accent={t.accent}/></F>
          </DCArtboard>
          <DCArtboard id="s-stack" label="Smart Stack" width={s46.w} height={s46.h}>
            <F><SmartStack accent={t.accent}/></F>
          </DCArtboard>
        </DCSection>

        <DCSection id="sizes" title="Size comparison" subtitle="42mm · 46mm · Ultra 49mm">
          <DCArtboard id="z-42" label="Series 10 · 42mm" width={s42.w} height={s42.h}>
            <F size="small"><WatchHome accent={t.accent}/></F>
          </DCArtboard>
          <DCArtboard id="z-46" label="Series 10 · 46mm" width={s46.w} height={s46.h}>
            <F><WatchHome accent={t.accent}/></F>
          </DCArtboard>
          <DCArtboard id="z-ultra" label="Ultra 2 · 49mm" width={ult.w} height={ult.h}>
            <F kind="ultra"><WatchHome accent={t.accent}/></F>
          </DCArtboard>
        </DCSection>
      </DesignCanvas>
      <WatchPanel/>
    </>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<WatchRoot />);
