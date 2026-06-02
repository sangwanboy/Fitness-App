// screens.jsx — All 7 screens (Login, Home, Chat, Reminders, Profile, Workout, Calendar)

// ─────────────────────────────────────────────────────────────
// Backgrounds — solid / gradient / photo (CSS-painted)
// ─────────────────────────────────────────────────────────────
function bgForTweaks(T, t) {
  const dark = T.dark;
  if (t.bgStyle === 'solid') return { background: T.bg };
  if (t.bgStyle === 'gradient') {
    return {
      background: dark
        ? `radial-gradient(ellipse 120% 80% at 50% -10%, ${T.accent}38 0%, transparent 55%),
           radial-gradient(ellipse 80% 60% at 120% 100%, ${hex(T.accent,0.22)} 0%, transparent 55%),
           #000`
        : `radial-gradient(ellipse 120% 80% at 50% -10%, ${T.accent}28 0%, transparent 55%),
           radial-gradient(ellipse 80% 60% at 120% 100%, ${hex(T.accent,0.18)} 0%, transparent 55%),
           #F2F2F7`,
    };
  }
  // photo (painted with SVG; abstract gym/motion vibe — no real photo dependency)
  return {
    background: dark
      ? `linear-gradient(180deg, rgba(0,0,0,0.5) 0%, rgba(0,0,0,0.85) 100%),
         radial-gradient(ellipse at 30% 20%, ${T.accent}55 0%, transparent 50%),
         radial-gradient(ellipse at 80% 80%, #BF5AF255 0%, transparent 55%),
         linear-gradient(135deg, #1a1a1a 0%, #2a1f2a 100%)`
      : `linear-gradient(180deg, rgba(242,242,247,0.4) 0%, rgba(242,242,247,0.85) 100%),
         radial-gradient(ellipse at 30% 20%, ${T.accent}66 0%, transparent 50%),
         radial-gradient(ellipse at 80% 80%, #FF9F0A55 0%, transparent 55%),
         linear-gradient(135deg, #F2F2F7 0%, #EFE4D8 100%)`,
  };
}
function hex(c, a) {
  // accept #RRGGBB and append alpha as 2-hex digits
  const ah = Math.round(a*255).toString(16).padStart(2,'0');
  return c + ah;
}

// ─────────────────────────────────────────────────────────────
// Shared screen shell — top + scroll + tab bar
// ─────────────────────────────────────────────────────────────
function ScreenShell({ T, t, navContent, children, hideTabBar = false, tab, setTab, contentPad = true }) {
  return (
    <div style={{
      width: '100%', height: '100%', position: 'relative',
      ...bgForTweaks(T, t),
      color: T.fg, overflow: 'hidden',
    }}>
      <StatusBar dark={T.dark}/>
      {navContent}
      <div style={{
        position: 'absolute',
        top: 0, left: 0, right: 0, bottom: 0,
        paddingTop: navContent ? 172 : 50,
        paddingBottom: hideTabBar ? 38 : 120,
        overflow: 'auto', overscrollBehavior: 'contain',
      }}>
        <div style={{ padding: contentPad ? '0 16px' : 0 }}>
          {children}
        </div>
      </div>
      {!hideTabBar && <TabBar T={T} t={t} tab={tab} setTab={setTab} />}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Top nav bar (large title + glass pills)
// ─────────────────────────────────────────────────────────────
function TopNav({ T, t, title, leading, trailing, subtitle }) {
  return (
    <div style={{
      position: 'absolute', top: 0, left: 0, right: 0, zIndex: 5,
      paddingTop: 56,
    }}>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', padding: '0 16px', height: 44 }}>
        <div>{leading}</div>
        <div>{trailing}</div>
      </div>
      <div style={{ padding: '8px 20px 0', display: 'flex', flexDirection: 'column' }}>
        {subtitle && <div style={{
          fontSize: 13, fontWeight: 600, color: T.fgMuted,
          textTransform: 'uppercase', letterSpacing: 0.5, marginBottom: 2,
        }}>{subtitle}</div>}
        <div style={{
          fontSize: 32, fontWeight: 700, color: T.fg, letterSpacing: -0.8, lineHeight: 1.1,
        }}>{title}</div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Bottom Tab Bar — Liquid Glass
// ─────────────────────────────────────────────────────────────
function TabBar({ T, t, tab, setTab }) {
  const tabs = [
    { id: 'home',      label: 'Home',      icon: Icons.home,   iconF: Icons.homeFill },
    { id: 'chat',      label: 'Coach',     icon: Icons.chat,   iconF: Icons.chatFill },
    { id: 'reminders', label: 'Reminders', icon: Icons.bell,   iconF: Icons.bellFill },
    { id: 'profile',   label: 'Profile',   icon: Icons.person, iconF: Icons.personFill },
  ];
  return (
    <div style={{
      position: 'absolute', left: 14, right: 14, bottom: 14, zIndex: 30,
      display: 'flex', alignItems: 'center', justifyContent: 'space-between',
      pointerEvents: 'auto',
    }}>
      <GlassSurface dark={T.dark} intensity={t.glass} radius={9999}
        style={{ flex: 1, height: 64, display: 'flex' }}>
        <div style={{ display: 'flex', height: '100%', alignItems: 'center', padding: '0 4px' }}>
          {tabs.map(tt => {
            const on = tab === tt.id;
            const c = on ? T.accent : T.fgMuted;
            return (
              <div key={tt.id} onClick={() => setTab(tt.id)} style={{
                flex: 1, height: 56, display: 'flex', flexDirection: 'column',
                alignItems: 'center', justifyContent: 'center', gap: 2,
                cursor: 'pointer', borderRadius: 9999,
                background: on ? (T.dark ? `${T.accent}22` : `${T.accent}1A`) : 'transparent',
                transition: 'background 180ms',
              }}>
                <span style={{ display: 'flex' }}>{on ? tt.iconF(c) : tt.icon(c)}</span>
                <div style={{ fontSize: 10, fontWeight: 600, color: c, letterSpacing: 0.1 }}>{tt.label}</div>
              </div>
            );
          })}
        </div>
      </GlassSurface>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// LOGIN
// ─────────────────────────────────────────────────────────────
function LoginScreen({ T, t, onLogin }) {
  return (
    <div style={{
      width: '100%', height: '100%', position: 'relative',
      ...bgForTweaks(T, { ...t, bgStyle: 'photo' }),
      color: T.fg, overflow: 'hidden',
    }}>
      <StatusBar dark={T.dark}/>
      {/* Hero mark */}
      <div style={{
        position: 'absolute', top: 0, left: 0, right: 0, bottom: 0,
        display: 'flex', flexDirection: 'column', padding: '90px 28px 28px',
      }}>
        <div style={{ flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center' }}>
          <div style={{ position: 'relative', marginBottom: 28 }}>
            <GlassSurface dark={T.dark} intensity="maximal" radius={36}
              style={{ width: 116, height: 116 }}>
              <div style={{
                width: '100%', height: '100%',
                display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}>
                <div style={{
                  width: 76, height: 76, borderRadius: 22,
                  background: `linear-gradient(135deg, ${T.accent} 0%, ${hex(T.accent, 0.9)} 55%, ${T.purple} 100%)`,
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  position: 'relative', overflow: 'hidden',
                  boxShadow: `0 12px 32px ${hex(T.accent, 0.45)},
                              inset 0 1px 0 rgba(255,255,255,0.3),
                              inset 0 -8px 24px rgba(0,0,0,0.18)`,
                }}>
                  {/* Specular highlight */}
                  <div style={{
                    position: 'absolute', top: -8, left: -8, width: 44, height: 44,
                    borderRadius: '50%',
                    background: 'radial-gradient(circle, rgba(255,255,255,0.4), transparent 70%)',
                  }}/>
                  {/* Activity-rings mark */}
                  <svg width="44" height="44" viewBox="0 0 44 44" fill="none" style={{ position: 'relative' }}>
                    <circle cx="22" cy="22" r="18" stroke="#fff" strokeWidth="3.5" strokeLinecap="round"
                      strokeDasharray={`${2*Math.PI*18*0.78} 200`} transform="rotate(-90 22 22)"/>
                    <circle cx="22" cy="22" r="12.5" stroke="#fff" strokeOpacity="0.78" strokeWidth="3.5" strokeLinecap="round"
                      strokeDasharray={`${2*Math.PI*12.5*0.62} 200`} transform="rotate(-90 22 22)"/>
                    <circle cx="22" cy="22" r="7" stroke="#fff" strokeOpacity="0.58" strokeWidth="3.5" strokeLinecap="round"
                      strokeDasharray={`${2*Math.PI*7*0.92} 200`} transform="rotate(-90 22 22)"/>
                  </svg>
                </div>
              </div>
            </GlassSurface>
          </div>
          <div style={{
            fontSize: 36, fontWeight: 700, letterSpacing: -1.2,
            color: T.fg, textAlign: 'center', marginBottom: 6,
          }}>Fitness Guru</div>
          <div style={{
            fontSize: 16, fontWeight: 500, color: T.fgMuted, textAlign: 'center',
            maxWidth: 280, lineHeight: 1.4, textWrap: 'balance',
          }}>
            Your AI training partner. Connected to your health, calendar, and goals.
          </div>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 10 }}>
          <button onClick={onLogin} style={{
            height: 56, borderRadius: 16, border: 'none', cursor: 'pointer',
            background: T.accent, color: '#fff',
            fontSize: 17, fontWeight: 700, letterSpacing: -0.3,
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
            fontFamily: 'inherit',
            boxShadow: `0 10px 28px ${hex(T.accent, 0.42)}, inset 0 1px 0 rgba(255,255,255,0.25)`,
          }}>
            {Icons.bolt('#fff', 22)}
            Get started — it's free
          </button>
          <div style={{
            display: 'flex', alignItems: 'center', gap: 10, padding: '2px 0',
            color: T.fgMuted, fontSize: 11, fontWeight: 600, letterSpacing: 1,
          }}>
            <div style={{ flex: 1, height: 0.5, background: T.hairline }} />
            <span>OR CONTINUE WITH</span>
            <div style={{ flex: 1, height: 0.5, background: T.hairline }} />
          </div>
          <button onClick={onLogin} style={{
            height: 54, borderRadius: 16, border: 'none', cursor: 'pointer',
            background: T.dark ? '#fff' : '#000', color: T.dark ? '#000' : '#fff',
            fontSize: 16, fontWeight: 600, letterSpacing: -0.3,
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
            fontFamily: 'inherit',
          }}>
            {Icons.apple(T.dark ? '#000' : '#fff', 20)}
            Continue with Apple
          </button>
          <button onClick={onLogin} style={{
            height: 54, borderRadius: 16, border: 'none', cursor: 'pointer',
            background: '#FFFFFF', color: '#1f1f1f',
            fontSize: 16, fontWeight: 600, letterSpacing: -0.3,
            display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 10,
            fontFamily: 'inherit',
            boxShadow: '0 1px 2px rgba(0,0,0,0.1)',
          }}>
            {Icons.google(20)}
            Continue with Google
          </button>
          <GlassSurface dark={T.dark} intensity={t.glass} radius={16}
            onClick={onLogin}
            style={{ height: 54 }}>
            <div style={{
              display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 10,
              width: '100%', height: '100%',
            }}>
              {Icons.face(T.fg)}
              <span style={{ fontSize: 15, fontWeight: 600, color: T.fg, letterSpacing: -0.3 }}>Face ID</span>
            </div>
          </GlassSurface>
          <div style={{
            fontSize: 12, textAlign: 'center', color: T.fgMuted, marginTop: 8, lineHeight: 1.4,
            padding: '0 12px',
          }}>
            By continuing you agree to our <span style={{ color: T.accent, fontWeight: 600 }}>Terms</span> and <span style={{ color: T.accent, fontWeight: 600 }}>Privacy Policy</span>. We never sell your health data.
          </div>
        </div>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// HOME
// ─────────────────────────────────────────────────────────────
function HomeScreen({ T, t, tab, setTab, onOpenWorkout }) {
  const visible = t.homeCards.filter(id => HOME_CARDS[id]);
  return (
    <ScreenShell T={T} t={t} tab={tab} setTab={setTab}
      navContent={
        <TopNav T={T} t={t}
          subtitle="Tuesday, Oct 14"
          title={`Hi, ${t.userName.split(' ')[0]}`}
          trailing={
            <div style={{ display: 'flex', gap: 8 }}>
              <GlassPill dark={T.dark} intensity={t.glass} size={40}>
                {Icons.search(T.fg, 18)}
              </GlassPill>
              <GlassPill dark={T.dark} intensity={t.glass} size={40} onClick={() => setTab('profile')}>
                <div style={{
                  width: 32, height: 32, borderRadius: 999,
                  background: `linear-gradient(135deg, ${T.accent} 0%, ${T.purple} 100%)`,
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  color: '#fff', fontWeight: 700, fontSize: 13, letterSpacing: -0.3,
                }}>{t.userName.split(' ').map(w => w[0]).join('').slice(0,2).toUpperCase()}</div>
              </GlassPill>
            </div>
          }
        />
      }>
      <div style={{
        display: 'grid', gridTemplateColumns: '1fr 1fr', gap: t.density === 'compact' ? 8 : 12,
        paddingTop: 8,
      }}>
        {visible.map(id => {
          const Cmp = HOME_CARDS[id];
          const props = { T, density: t.density, userName: t.userName, onClick: id === 'upcoming' || id === 'workouts' ? onOpenWorkout : undefined };
          return <React.Fragment key={id}><Cmp {...props}/></React.Fragment>;
        })}
      </div>
    </ScreenShell>
  );
}

// ─────────────────────────────────────────────────────────────
// CHAT
// ─────────────────────────────────────────────────────────────
function ChatScreen({ T, t, tab, setTab }) {
  const [messages, setMessages] = React.useState(SEED_MESSAGES);
  const [input, setInput] = React.useState('');
  const endRef = React.useRef(null);
  React.useEffect(() => { if (endRef.current) endRef.current.scrollTop = endRef.current.scrollHeight; }, [messages]);

  const send = (text) => {
    const trimmed = (text ?? input).trim();
    if (!trimmed) return;
    setMessages(m => [...m, { role: 'user', text: trimmed }]);
    setInput('');
    setTimeout(() => {
      setMessages(m => [...m, AI_REPLY_FOR(trimmed, T)]);
    }, 600);
  };

  return (
    <ScreenShell T={T} t={t} tab={tab} setTab={setTab}
      navContent={
        <TopNav T={T} t={t}
          subtitle="AI · Always learning your body"
          title="Coach"
          trailing={
            <GlassPill dark={T.dark} intensity={t.glass} size={40}>
              {Icons.more(T.fg)}
            </GlassPill>
          }
        />
      }>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 10, paddingTop: 4 }}>
        {messages.map((m, i) => <ChatBubble key={i} m={m} T={T} dark={T.dark} t={t}/>)}
      </div>
      {/* Composer + chips (floating, glass) */}
      <div style={{
        position: 'absolute', left: 14, right: 14, bottom: 86, zIndex: 25,
      }}>
        {/* Suggestion chips ABOVE composer */}
        <div style={{
          display: 'flex', gap: 8, marginBottom: 10, overflowX: 'auto', paddingBottom: 2,
        }}>
          {['How was my sleep?', 'Plan tomorrow', 'Why am I tired?', 'Suggest a workout'].map(q => (
            <div key={q} onClick={() => send(q)} style={{
              flexShrink: 0, height: 32, padding: '0 12px', borderRadius: 16,
              background: T.dark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.05)',
              border: `0.5px solid ${T.hairline}`,
              display: 'inline-flex', alignItems: 'center', cursor: 'pointer',
              fontSize: 13, fontWeight: 500, color: T.fg, letterSpacing: -0.2,
              whiteSpace: 'nowrap',
              backdropFilter: 'blur(20px)',
            }}>{q}</div>
          ))}
        </div>
        {/* Composer */}
        <GlassSurface dark={T.dark} intensity={t.glass} radius={26}>
          <div style={{
            display: 'flex', alignItems: 'center', padding: '6px 6px 6px 16px', gap: 8, height: '100%',
          }}>
            <div style={{
              width: 32, height: 32, display: 'flex', alignItems: 'center', justifyContent: 'center',
              borderRadius: 999, cursor: 'pointer', flexShrink: 0,
            }}>{Icons.mic(T.fgMuted, 20)}</div>
            <input
              value={input} onChange={e => setInput(e.target.value)}
              onKeyDown={e => e.key === 'Enter' && send()}
              placeholder="Ask about your health…"
              style={{
                flex: 1, background: 'transparent', border: 'none', outline: 'none',
                color: T.fg, fontSize: 15, fontFamily: 'inherit', letterSpacing: -0.2,
                padding: '10px 0', minWidth: 0,
              }}
            />
            <div onClick={() => send()} style={{
              width: 40, height: 40, borderRadius: 999, flexShrink: 0,
              background: input.trim() ? T.accent : (T.dark ? 'rgba(255,255,255,0.12)' : 'rgba(0,0,0,0.08)'),
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              cursor: input.trim() ? 'pointer' : 'default',
              transition: 'background 160ms',
              boxShadow: input.trim() ? `0 4px 12px ${hex(T.accent, 0.35)}` : 'none',
            }}>{Icons.send(input.trim() ? '#fff' : T.fgFaint, 18)}</div>
          </div>
        </GlassSurface>
      </div>
    </ScreenShell>
  );
}

function ChatBubble({ m, T, dark, t }) {
  if (m.role === 'user') {
    return (
      <div style={{ display: 'flex', justifyContent: 'flex-end' }}>
        <div style={{
          maxWidth: '78%', padding: '10px 14px', borderRadius: 20, borderTopRightRadius: 6,
          background: T.accent, color: '#fff', fontSize: 15, lineHeight: 1.35, letterSpacing: -0.2,
          fontWeight: 500,
        }}>{m.text}</div>
      </div>
    );
  }
  // AI: header + content (text or card)
  return (
    <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 6, paddingLeft: 4 }}>
        <div style={{
          width: 20, height: 20, borderRadius: 999,
          background: `linear-gradient(135deg, ${T.accent} 0%, ${T.purple} 100%)`,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>{Icons.sparkle('#fff', 12)}</div>
        <div style={{ fontSize: 11, fontWeight: 600, color: T.fgMuted, textTransform: 'uppercase', letterSpacing: 0.4 }}>Coach</div>
      </div>
      {m.text && (
        <div style={{
          maxWidth: '88%', padding: '10px 14px', borderRadius: 20, borderTopLeftRadius: 6,
          background: T.dark ? 'rgba(255,255,255,0.08)' : 'rgba(0,0,0,0.04)',
          color: T.fg, fontSize: 15, lineHeight: 1.4, letterSpacing: -0.2, fontWeight: 500,
          border: `0.5px solid ${T.hairline}`,
          textWrap: 'pretty',
        }}>{m.text}</div>
      )}
      {m.card && <RichCard card={m.card} T={T}/>}
      {m.chips && (
        <div style={{ display: 'flex', gap: 6, flexWrap: 'wrap', marginTop: 2 }}>
          {m.chips.map(c => (
            <div key={c} style={{
              height: 30, padding: '0 12px', borderRadius: 16, border: `0.5px solid ${T.accent}55`,
              display: 'inline-flex', alignItems: 'center', cursor: 'pointer', whiteSpace: 'nowrap',
              fontSize: 13, fontWeight: 600, color: T.accent, background: `${T.accent}12`,
            }}>{c}</div>
          ))}
        </div>
      )}
    </div>
  );
}

function RichCard({ card, T }) {
  // card types: { kind: 'sleep' | 'workout' | 'stat' | 'plan', ... }
  if (card.kind === 'sleep') {
    return (
      <Card dark={T.dark} padding={14} style={{ maxWidth: '92%' }}>
        <CardHead icon={Icons.moon(T.purple, 16)} title="Last night" color={T.purple} dark={T.dark}/>
        <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
          <Donut size={68} stroke={8} value={0.86} color={T.purple}/>
          <div>
            <BigNum value="7h 42m" caption="Score 86 · Best this week" dark={T.dark}/>
          </div>
        </div>
        <div style={{ marginTop: 10, marginLeft: -2, marginRight: -2 }}>
          <Spark values={[72,80,68,75,82,78,86]} color={T.purple} width={260} height={50}/>
        </div>
      </Card>
    );
  }
  if (card.kind === 'plan') {
    return (
      <Card dark={T.dark} padding={14} style={{ maxWidth: '92%' }}>
        <CardHead icon={Icons.cal(T.accent, 16)} title="Suggested plan · Tomorrow" color={T.accent} dark={T.dark}/>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 8, marginTop: 4 }}>
          {[
            { time: '7:00 AM', name: 'Zone 2 run · 35 min', cal: '290 cal' },
            { time: '12:30 PM', name: 'Mobility · 10 min', cal: '40 cal' },
            { time: '6:00 PM', name: 'Upper body strength', cal: '320 cal' },
          ].map((row, i) => (
            <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
              <div style={{
                width: 36, height: 36, borderRadius: 10, flexShrink: 0,
                background: T.dark ? `${T.accent}22` : `${T.accent}1A`,
                display: 'flex', alignItems: 'center', justifyContent: 'center', color: T.accent,
              }}>{Icons.bolt(T.accent, 16)}</div>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontSize: 13, fontWeight: 600, color: T.fg, letterSpacing: -0.2 }}>{row.name}</div>
                <div style={{ fontSize: 11, color: T.fgMuted, fontWeight: 500 }}>{row.time} · {row.cal}</div>
              </div>
            </div>
          ))}
        </div>
        <div style={{
          marginTop: 12, padding: '10px 14px', borderRadius: 12, background: T.accent, color: '#fff',
          fontSize: 14, fontWeight: 600, textAlign: 'center', cursor: 'pointer',
        }}>Add to calendar</div>
      </Card>
    );
  }
  if (card.kind === 'stat') {
    return (
      <Card dark={T.dark} padding={14} style={{ maxWidth: '92%' }}>
        <CardHead icon={Icons.heart(T.red, 16)} title="Resting HR · 30 days" color={T.red} dark={T.dark}/>
        <div style={{ display: 'flex', alignItems: 'baseline', gap: 6 }}>
          <BigNum value="62" unit="BPM" caption="Avg · trending down 4 bpm" dark={T.dark} color={T.red}/>
        </div>
        <div style={{ marginTop: 10, marginLeft: -2 }}>
          <Spark values={[68,67,69,66,68,65,66,64,65,63,64,62,63,61,62,60,62]} color={T.red} width={260} height={56} dots/>
        </div>
      </Card>
    );
  }
  return null;
}

const SEED_MESSAGES = [
  { role: 'ai', text: 'Morning. Recovery is at 74 — solid base. I noticed your resting HR dipped to a 30-day low. Want to push intensity today, or stay zone 2?' },
  { role: 'ai', card: { kind: 'stat' } },
  { role: 'user', text: 'How was my sleep?' },
  { role: 'ai', text: 'Best in 8 days — REM was up 22 min versus average. The 10 PM screen wind-down is paying off.' },
  { role: 'ai', card: { kind: 'sleep' } },
  { role: 'user', text: 'Plan tomorrow for me' },
  { role: 'ai', text: 'Here\u2019s a balanced day — kept volume moderate since you\u2019re building up. I\u2019ll add these to your calendar if you tap below.', card: { kind: 'plan' }, chips: ['Looks good', 'Make it harder', 'Swap run for ride'] },
];

function AI_REPLY_FOR(q, T) {
  const lower = q.toLowerCase();
  if (lower.includes('sleep')) return { role: 'ai', text: 'Last night was strong — 7h 42m with a sleep score of 86. Deep was a little light (1h 14m). Try cooling the room a degree tonight.', card: { kind: 'sleep' } };
  if (lower.includes('plan') || lower.includes('workout')) return { role: 'ai', text: 'Pulled in your calendar — here\u2019s a plan that fits around your 11 AM call.', card: { kind: 'plan' }, chips: ['Looks good', 'Easier please'] };
  if (lower.includes('tired') || lower.includes('why')) return { role: 'ai', text: 'Sleep was good but HRV dropped 14% versus your 7-day baseline. You also logged caffeine after 4 PM yesterday. Recommend an easy day.' };
  return { role: 'ai', text: 'Got it. I\u2019ll fold that into the plan — give me a moment to crunch your last 30 days.' };
}

window.LoginScreen = LoginScreen;
window.HomeScreen = HomeScreen;
window.ChatScreen = ChatScreen;
window.TopNav = TopNav;
window.TabBar = TabBar;
window.bgForTweaks = bgForTweaks;
window.hex = hex;
window.ScreenShell = ScreenShell;
