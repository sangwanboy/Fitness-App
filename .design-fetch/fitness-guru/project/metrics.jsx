// metrics.jsx — Home dashboard cards + charts (rings, lines, bars)

// ─────────────────────────────────────────────────────────────
// Activity rings (Move / Exercise / Stand)
// ─────────────────────────────────────────────────────────────
function Rings({ size = 110, stroke = 11, vals = [0.78, 0.62, 0.95], colors }) {
  const c = colors || ['#FF375F', '#9FE830', '#00D4FF'];
  const r1 = size/2 - stroke*0.5;
  const r2 = r1 - stroke - 3;
  const r3 = r2 - stroke - 3;
  const ring = (r, v, col) => {
    const C = 2*Math.PI*r;
    return (
      <g transform={`rotate(-90 ${size/2} ${size/2})`}>
        <circle cx={size/2} cy={size/2} r={r} fill="none" stroke={col} strokeOpacity="0.18" strokeWidth={stroke}/>
        <circle cx={size/2} cy={size/2} r={r} fill="none" stroke={col} strokeWidth={stroke}
          strokeDasharray={`${C*Math.min(v,1)} ${C}`} strokeLinecap="round"/>
      </g>
    );
  };
  return <svg width={size} height={size}>{ring(r1, vals[0], c[0])}{ring(r2, vals[1], c[1])}{ring(r3, vals[2], c[2])}</svg>;
}

// ─────────────────────────────────────────────────────────────
// Donut chart with center text (used for sleep score, recovery)
// ─────────────────────────────────────────────────────────────
function Donut({ size = 92, stroke = 9, value = 0.82, color = '#BF5AF2', track }) {
  const r = size/2 - stroke/2;
  const C = 2*Math.PI*r;
  return (
    <svg width={size} height={size}>
      <g transform={`rotate(-90 ${size/2} ${size/2})`}>
        <circle cx={size/2} cy={size/2} r={r} fill="none" stroke={track || color} strokeOpacity="0.18" strokeWidth={stroke}/>
        <circle cx={size/2} cy={size/2} r={r} fill="none" stroke={color} strokeWidth={stroke}
          strokeDasharray={`${C*Math.min(value,1)} ${C}`} strokeLinecap="round"/>
      </g>
    </svg>
  );
}

// ─────────────────────────────────────────────────────────────
// Sparkline / line chart — pass values 0..1 normalised
// ─────────────────────────────────────────────────────────────
function Spark({ values, width = 220, height = 60, color = '#FF453A', fill = true, dots = false }) {
  const max = Math.max(...values), min = Math.min(...values);
  const range = max - min || 1;
  const pts = values.map((v, i) => {
    const x = (i / (values.length - 1)) * width;
    const y = height - ((v - min) / range) * (height - 10) - 5;
    return [x, y];
  });
  const d = pts.map((p, i) => `${i ? 'L' : 'M'}${p[0].toFixed(1)} ${p[1].toFixed(1)}`).join(' ');
  const fillD = `${d} L${width} ${height} L0 ${height} Z`;
  return (
    <svg width={width} height={height} style={{ display: 'block' }}>
      {fill && (
        <defs>
          <linearGradient id={`spark-${color.slice(1)}`} x1="0" y1="0" x2="0" y2="1">
            <stop offset="0%" stopColor={color} stopOpacity="0.32"/>
            <stop offset="100%" stopColor={color} stopOpacity="0"/>
          </linearGradient>
        </defs>
      )}
      {fill && <path d={fillD} fill={`url(#spark-${color.slice(1)})`}/>}
      <path d={d} fill="none" stroke={color} strokeWidth="2" strokeLinecap="round" strokeLinejoin="round"/>
      {dots && pts.map((p, i) => i === pts.length-1 && (
        <circle key={i} cx={p[0]} cy={p[1]} r="3.5" fill={color} stroke="#fff" strokeWidth="1.5"/>
      ))}
    </svg>
  );
}

// ─────────────────────────────────────────────────────────────
// Bar chart (weekly steps, workouts)
// ─────────────────────────────────────────────────────────────
function Bars({ values, labels, width = 220, height = 70, color = '#30D158', highlight = -1, dark }) {
  const max = Math.max(...values);
  const bw = width / values.length;
  const inner = bw * 0.55;
  const pad = (bw - inner) / 2;
  return (
    <div>
      <svg width={width} height={height} style={{ display: 'block' }}>
        {values.map((v, i) => {
          const h = (v / max) * (height - 14);
          const isHl = i === highlight || (highlight === -1 && i === values.length - 1);
          return (
            <rect key={i} x={i*bw + pad} y={height - h - 2} width={inner} height={Math.max(h, 4)} rx={inner/2}
              fill={isHl ? color : (dark ? 'rgba(255,255,255,0.22)' : 'rgba(60,60,67,0.18)')}/>
          );
        })}
      </svg>
      {labels && (
        <div style={{ display: 'flex', marginTop: 4 }}>
          {labels.map((l, i) => (
            <div key={i} style={{
              flex: 1, textAlign: 'center', fontSize: 10, fontWeight: 600,
              color: dark ? 'rgba(235,235,245,0.5)' : 'rgba(60,60,67,0.5)',
              letterSpacing: 0.2,
            }}>{l}</div>
          ))}
        </div>
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Card header (used inside metric cards)
// ─────────────────────────────────────────────────────────────
function CardHead({ icon, title, color, dark, right }) {
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginBottom: 8 }}>
      <span style={{ display: 'flex', color }}>{icon}</span>
      <span style={{
        fontSize: 13, fontWeight: 600, color, letterSpacing: -0.2,
        textTransform: 'none',
      }}>{title}</span>
      <div style={{ flex: 1 }} />
      {right}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Metric — value + unit + caption, in big numerals
// ─────────────────────────────────────────────────────────────
function BigNum({ value, unit, caption, dark, color }) {
  return (
    <div>
      <div style={{
        fontSize: 30, fontWeight: 700, letterSpacing: -1.2,
        color: dark ? '#fff' : '#000',
        fontFeatureSettings: '"tnum" 1',
        lineHeight: 1, display: 'flex', alignItems: 'baseline', gap: 4,
      }}>
        <span style={{ color: color || (dark ? '#fff' : '#000') }}>{value}</span>
        {unit && <span style={{ fontSize: 14, fontWeight: 600, color: dark ? 'rgba(235,235,245,0.6)' : 'rgba(60,60,67,0.6)' }}>{unit}</span>}
      </div>
      {caption && <div style={{
        fontSize: 12, fontWeight: 500, marginTop: 4,
        color: dark ? 'rgba(235,235,245,0.55)' : 'rgba(60,60,67,0.55)',
      }}>{caption}</div>}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Individual metric cards
// ─────────────────────────────────────────────────────────────
function ActivityCard({ T, density, onClick }) {
  const pad = density === 'compact' ? 14 : density === 'comfy' ? 20 : 16;
  return (
    <Card dark={T.dark} padding={pad} onClick={onClick} style={{ gridColumn: 'span 2' }}>
      <CardHead icon={Icons.flame(T.red, 16)} title="Activity" color={T.red} dark={T.dark}/>
      <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
        <Rings size={86} stroke={9}/>
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 6 }}>
          <RingRow label="Move" value="486" unit="/ 600 CAL" color={T.red} dark={T.dark}/>
          <RingRow label="Exercise" value="19" unit="/ 30 MIN" color="#9FE830" dark={T.dark}/>
          <RingRow label="Stand" value="11" unit="/ 12 HR" color="#00D4FF" dark={T.dark}/>
        </div>
      </div>
    </Card>
  );
}
function RingRow({ label, value, unit, color, dark }) {
  return (
    <div>
      <div style={{ fontSize: 11, fontWeight: 600, color, letterSpacing: 0.3, textTransform: 'uppercase' }}>{label}</div>
      <div style={{ fontSize: 15, fontWeight: 600, color: dark ? '#fff' : '#000', letterSpacing: -0.3 }}>
        <span style={{ color }}>{value}</span>
        <span style={{ color: dark ? 'rgba(235,235,245,0.5)' : 'rgba(60,60,67,0.5)', fontSize: 11, marginLeft: 4, fontWeight: 600 }}>{unit}</span>
      </div>
    </div>
  );
}

function StepsCard({ T, density, onClick }) {
  const pad = density === 'compact' ? 12 : density === 'comfy' ? 18 : 14;
  return (
    <Card dark={T.dark} padding={pad} onClick={onClick}>
      <CardHead icon={Icons.walk(T.orange, 16)} title="Steps" color={T.orange} dark={T.dark}/>
      <BigNum value="8,247" caption="3.4 mi · 92% of goal" dark={T.dark}/>
      <div style={{ marginTop: 10, marginLeft: -4, marginRight: -4 }}>
        <Bars values={[5200, 8800, 6500, 9200, 7100, 11200, 8247]} labels={['M','T','W','T','F','S','S']}
          color={T.orange} width={140} height={42} dark={T.dark}/>
      </div>
    </Card>
  );
}

function HeartCard({ T, density, onClick }) {
  const pad = density === 'compact' ? 12 : density === 'comfy' ? 18 : 14;
  return (
    <Card dark={T.dark} padding={pad} onClick={onClick}>
      <CardHead icon={Icons.heart(T.red, 16)} title="Heart" color={T.red} dark={T.dark}/>
      <BigNum value="72" unit="BPM" caption="Resting · steady" dark={T.dark} color={T.red}/>
      <div style={{ marginTop: 10, marginLeft: -4, marginRight: -4 }}>
        <Spark values={[68,71,74,69,72,76,72,70,72]} color={T.red} width={140} height={42}/>
      </div>
    </Card>
  );
}

function SleepCard({ T, density, onClick }) {
  const pad = density === 'compact' ? 12 : density === 'comfy' ? 18 : 14;
  return (
    <Card dark={T.dark} padding={pad} onClick={onClick}>
      <CardHead icon={Icons.moon(T.purple, 16)} title="Sleep" color={T.purple} dark={T.dark}/>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
        <div style={{ position: 'relative', width: 64, height: 64 }}>
          <Donut size={64} stroke={7} value={0.86} color={T.purple}/>
          <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center', flexDirection: 'column' }}>
            <div style={{ fontSize: 18, fontWeight: 700, color: T.dark ? '#fff' : '#000', letterSpacing: -0.5 }}>86</div>
          </div>
        </div>
        <div>
          <div style={{ fontSize: 15, fontWeight: 600, color: T.dark ? '#fff' : '#000' }}>7h 42m</div>
          <div style={{ fontSize: 11, color: T.dark ? 'rgba(235,235,245,0.5)' : 'rgba(60,60,67,0.55)', fontWeight: 500 }}>
            REM 1h 36m
          </div>
          <div style={{ fontSize: 11, color: T.dark ? 'rgba(235,235,245,0.5)' : 'rgba(60,60,67,0.55)', fontWeight: 500 }}>
            Deep 1h 14m
          </div>
        </div>
      </div>
    </Card>
  );
}

function CaloriesCard({ T, density, onClick }) {
  const pad = density === 'compact' ? 12 : density === 'comfy' ? 18 : 14;
  return (
    <Card dark={T.dark} padding={pad} onClick={onClick}>
      <CardHead icon={Icons.bolt(T.orange, 16)} title="Calories" color={T.orange} dark={T.dark}/>
      <div style={{ display: 'flex', gap: 14, alignItems: 'flex-end' }}>
        <div>
          <div style={{ fontSize: 10, fontWeight: 600, color: T.dark ? 'rgba(235,235,245,0.5)' : 'rgba(60,60,67,0.5)', letterSpacing: 0.4, textTransform: 'uppercase' }}>In</div>
          <div style={{ fontSize: 22, fontWeight: 700, color: T.dark ? '#fff' : '#000', letterSpacing: -0.8 }}>1,820</div>
        </div>
        <div style={{ width: 1, height: 28, background: T.hairline }} />
        <div>
          <div style={{ fontSize: 10, fontWeight: 600, color: T.orange, letterSpacing: 0.4, textTransform: 'uppercase' }}>Out</div>
          <div style={{ fontSize: 22, fontWeight: 700, color: T.dark ? '#fff' : '#000', letterSpacing: -0.8 }}>2,340</div>
        </div>
      </div>
      <div style={{
        marginTop: 10, height: 6, borderRadius: 3,
        background: T.dark ? 'rgba(255,255,255,0.08)' : 'rgba(60,60,67,0.1)',
        overflow: 'hidden', position: 'relative',
      }}>
        <div style={{ position: 'absolute', left: 0, top: 0, bottom: 0, width: '78%', background: T.orange, borderRadius: 3 }} />
      </div>
      <div style={{ fontSize: 11, color: T.dark ? 'rgba(235,235,245,0.55)' : 'rgba(60,60,67,0.55)', marginTop: 6, fontWeight: 500 }}>
        −520 deficit
      </div>
    </Card>
  );
}

function RecoveryCard({ T, density, onClick }) {
  const pad = density === 'compact' ? 12 : density === 'comfy' ? 18 : 14;
  return (
    <Card dark={T.dark} padding={pad} onClick={onClick}>
      <CardHead icon={Icons.recovery(T.green, 16)} title="Recovery" color={T.green} dark={T.dark}/>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
        <div style={{ position: 'relative', width: 64, height: 64 }}>
          <Donut size={64} stroke={7} value={0.74} color={T.green}/>
          <div style={{ position: 'absolute', inset: 0, display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
            <div style={{ fontSize: 18, fontWeight: 700, color: T.dark ? '#fff' : '#000', letterSpacing: -0.5 }}>74</div>
          </div>
        </div>
        <div>
          <div style={{ fontSize: 11, fontWeight: 600, color: T.green, letterSpacing: 0.4, textTransform: 'uppercase' }}>HRV 52ms</div>
          <div style={{ fontSize: 13, color: T.dark ? '#fff' : '#000', fontWeight: 600, marginTop: 2 }}>Ready to train</div>
          <div style={{ fontSize: 11, color: T.dark ? 'rgba(235,235,245,0.55)' : 'rgba(60,60,67,0.55)', fontWeight: 500 }}>+6 from yesterday</div>
        </div>
      </div>
    </Card>
  );
}

function HydrationCard({ T, density, onClick }) {
  const pad = density === 'compact' ? 12 : density === 'comfy' ? 18 : 14;
  const cups = 5, total = 8;
  return (
    <Card dark={T.dark} padding={pad} onClick={onClick}>
      <CardHead icon={Icons.drop(T.cyan, 16)} title="Hydration" color={T.cyan} dark={T.dark}/>
      <BigNum value="1.4" unit="L" caption={`${cups} of ${total} glasses`} dark={T.dark} color={T.cyan}/>
      <div style={{ display: 'flex', gap: 4, marginTop: 10 }}>
        {[...Array(total)].map((_, i) => (
          <div key={i} style={{
            flex: 1, height: 22, borderRadius: 4,
            background: i < cups ? T.cyan : (T.dark ? 'rgba(255,255,255,0.08)' : 'rgba(60,60,67,0.08)'),
            opacity: i < cups ? (0.4 + (i / cups) * 0.6) : 1,
          }} />
        ))}
      </div>
    </Card>
  );
}

function WorkoutsCard({ T, density, onClick }) {
  const pad = density === 'compact' ? 14 : density === 'comfy' ? 20 : 16;
  return (
    <Card dark={T.dark} padding={pad} onClick={onClick} style={{ gridColumn: 'span 2' }}>
      <CardHead icon={Icons.bolt(T.accent, 16)} title="This Week" color={T.accent} dark={T.dark} right={
        <span style={{ fontSize: 12, fontWeight: 600, color: T.accent }}>4 workouts</span>
      } />
      <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
        <BigNum value="3h 24m" caption="142 min · 2,180 cal" dark={T.dark}/>
        <div style={{ flex: 1, marginLeft: 'auto' }}>
          <Bars values={[28, 0, 42, 35, 0, 52, 30]} labels={['M','T','W','T','F','S','S']}
            color={T.accent} width={170} height={50} highlight={5} dark={T.dark}/>
        </div>
      </div>
    </Card>
  );
}

function CoachCard({ T, density, userName, onClick }) {
  const pad = density === 'compact' ? 14 : density === 'comfy' ? 20 : 16;
  return (
    <Card dark={T.dark} padding={pad} onClick={onClick} style={{
      gridColumn: 'span 2',
      background: T.dark
        ? `linear-gradient(135deg, ${T.accent}28 0%, rgba(28,28,30,0.96) 60%)`
        : `linear-gradient(135deg, ${T.accent}26 0%, #fff 65%)`,
    }}>
      <CardHead icon={Icons.sparkle(T.accent, 16)} title="Today's coach summary" color={T.accent} dark={T.dark} />
      <div style={{
        fontSize: 15, lineHeight: 1.42, fontWeight: 500, color: T.dark ? '#fff' : '#000',
        letterSpacing: -0.3, textWrap: 'pretty',
      }}>
        Recovery is strong (74) and sleep was solid. Push intensity today — your HRV trend supports a hard zone-4 session. Hydrate early: you're behind by ~700 ml from yesterday.
      </div>
      <div style={{ display: 'flex', gap: 8, marginTop: 12, flexWrap: 'wrap' }}>
        <CoachChip T={T}>Plan today</CoachChip>
        <CoachChip T={T}>Why?</CoachChip>
        <CoachChip T={T}>Adjust goals</CoachChip>
      </div>
    </Card>
  );
}
function CoachChip({ T, children }) {
  return (
    <div style={{
      height: 30, padding: '0 12px', borderRadius: 999,
      display: 'inline-flex', alignItems: 'center', whiteSpace: 'nowrap',
      fontSize: 13, fontWeight: 600, color: T.accent, letterSpacing: -0.2,
      background: T.dark ? `${T.accent}26` : `${T.accent}1E`,
      border: `0.5px solid ${T.accent}40`,
    }}>{children}</div>
  );
}

function UpcomingCard({ T, density, onClick }) {
  const pad = density === 'compact' ? 12 : density === 'comfy' ? 18 : 14;
  return (
    <Card dark={T.dark} padding={pad} onClick={onClick} style={{ gridColumn: 'span 2' }}>
      <CardHead icon={Icons.cal(T.blue, 16)} title="Up next" color={T.blue} dark={T.dark} />
      <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
        <div style={{
          width: 56, height: 56, borderRadius: 14, flexShrink: 0,
          background: T.dark ? `${T.blue}26` : `${T.blue}1E`,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          flexDirection: 'column',
        }}>
          <div style={{ fontSize: 10, fontWeight: 700, color: T.blue, letterSpacing: 0.5 }}>TUE</div>
          <div style={{ fontSize: 20, fontWeight: 700, color: T.blue, letterSpacing: -0.5, lineHeight: 1 }}>14</div>
        </div>
        <div style={{ flex: 1 }}>
          <div style={{ fontSize: 15, fontWeight: 600, color: T.dark ? '#fff' : '#000', letterSpacing: -0.3 }}>
            Zone 2 run · 45 min
          </div>
          <div style={{ fontSize: 12, color: T.dark ? 'rgba(235,235,245,0.55)' : 'rgba(60,60,67,0.55)', fontWeight: 500, marginTop: 1 }}>
            6:30 PM · Riverside loop · Easy effort
          </div>
        </div>
        {Icons.chev(T.fgFaint, 14)}
      </div>
    </Card>
  );
}

// Map id → component for toggling via Tweaks
const HOME_CARDS = {
  coach:     CoachCard,
  activity:  ActivityCard,
  steps:     StepsCard,
  heart:     HeartCard,
  sleep:     SleepCard,
  calories:  CaloriesCard,
  recovery:  RecoveryCard,
  hydration: HydrationCard,
  workouts:  WorkoutsCard,
  upcoming:  UpcomingCard,
};

Object.assign(window, {
  Rings, Donut, Spark, Bars, CardHead, BigNum, HOME_CARDS,
  ActivityCard, StepsCard, HeartCard, SleepCard, CaloriesCard,
  RecoveryCard, HydrationCard, WorkoutsCard, CoachCard, UpcomingCard,
});
