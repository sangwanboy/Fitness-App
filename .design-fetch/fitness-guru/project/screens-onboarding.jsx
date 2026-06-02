// screens-onboarding.jsx — 5-page onboarding flow for Fitness Guru iOS

function OnboardingScreen({ T, t, onComplete }) {
  const [page, setPage] = React.useState(0);
  const [goals, setGoals] = React.useState(['endurance', 'strength']);
  const [perms, setPerms] = React.useState({ health: true, calendar: true, reminders: true, notifications: true });

  const pages = [
    { key: 'welcome',   render: () => <PageWelcome   T={T} t={t}/> },
    { key: 'connect',   render: () => <PageConnect   T={T} t={t} perms={perms} setPerms={setPerms}/> },
    { key: 'goals',     render: () => <PageGoals     T={T} t={t} goals={goals} setGoals={setGoals}/> },
    { key: 'coach',     render: () => <PageCoach     T={T} t={t}/> },
    { key: 'notify',    render: () => <PageNotify    T={T} t={t} perms={perms} setPerms={setPerms}/> },
  ];
  const isLast = page === pages.length - 1;
  const next = () => isLast ? onComplete() : setPage(p => p + 1);
  const back = () => setPage(p => Math.max(0, p - 1));

  const ctaLabel = ['Get started', 'Connect & continue', 'Continue', 'Allow & continue', 'Finish'][page];

  return (
    <div style={{
      width: '100%', height: '100%', position: 'relative',
      ...bgForTweaks(T, { ...t, bgStyle: 'photo' }),
      color: T.fg, overflow: 'hidden',
    }}>
      <StatusBar dark={T.dark}/>

      {/* Top: page dots + skip */}
      <div style={{
        position: 'absolute', top: 56, left: 0, right: 0, zIndex: 5,
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '0 20px',
      }}>
        {page > 0 ? (
          <GlassPill dark={T.dark} intensity={t.glass} size={36} onClick={back}>
            {Icons.back(T.fg, 18)}
          </GlassPill>
        ) : <div style={{ width: 36, height: 36 }}/>}

        <div style={{ display: 'flex', gap: 6, alignItems: 'center' }}>
          {pages.map((_, i) => (
            <div key={i} style={{
              width: i === page ? 22 : 6, height: 6, borderRadius: 999,
              background: i === page ? T.accent : (T.dark ? 'rgba(255,255,255,0.22)' : 'rgba(0,0,0,0.18)'),
              transition: 'width 220ms',
            }}/>
          ))}
        </div>

        {!isLast ? (
          <div onClick={onComplete} style={{
            fontSize: 14, fontWeight: 600, color: T.fgMuted, cursor: 'pointer',
            padding: '8px 4px', letterSpacing: -0.2,
          }}>Skip</div>
        ) : <div style={{ width: 36, height: 36 }}/>}
      </div>

      {/* Page content */}
      <div style={{
        position: 'absolute', top: 100, left: 0, right: 0, bottom: 140,
        display: 'flex', flexDirection: 'column',
        overflow: 'hidden',
      }}>
        {pages[page].render()}
      </div>

      {/* Bottom CTA */}
      <div style={{
        position: 'absolute', left: 20, right: 20, bottom: 38, zIndex: 10,
        display: 'flex', flexDirection: 'column', gap: 10,
      }}>
        <button onClick={next} style={{
          height: 56, borderRadius: 16, border: 'none', cursor: 'pointer',
          background: T.accent, color: '#fff',
          fontSize: 17, fontWeight: 700, letterSpacing: -0.3,
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
          fontFamily: 'inherit',
          boxShadow: `0 10px 28px ${hex(T.accent, 0.42)}, inset 0 1px 0 rgba(255,255,255,0.25)`,
        }}>{ctaLabel}</button>
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// Pages
// ─────────────────────────────────────────────────────────────

function PageWelcome({ T, t }) {
  return (
    <div style={{
      flex: 1, display: 'flex', flexDirection: 'column', alignItems: 'center',
      justifyContent: 'center', padding: '0 28px', gap: 28,
    }}>
      {/* Hero mark */}
      <div style={{ position: 'relative' }}>
        <GlassSurface dark={T.dark} intensity="maximal" radius={40}
          style={{ width: 132, height: 132 }}>
          <div style={{
            width: '100%', height: '100%',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            <div style={{
              width: 86, height: 86, borderRadius: 24,
              background: `linear-gradient(135deg, ${T.accent} 0%, ${hex(T.accent, 0.9)} 55%, ${T.purple} 100%)`,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
              position: 'relative', overflow: 'hidden',
              boxShadow: `0 16px 40px ${hex(T.accent, 0.5)},
                          inset 0 1px 0 rgba(255,255,255,0.32),
                          inset 0 -8px 24px rgba(0,0,0,0.18)`,
            }}>
              <div style={{
                position: 'absolute', top: -8, left: -8, width: 48, height: 48,
                borderRadius: '50%',
                background: 'radial-gradient(circle, rgba(255,255,255,0.4), transparent 70%)',
              }}/>
              <svg width="50" height="50" viewBox="0 0 44 44" fill="none" style={{ position: 'relative' }}>
                <circle cx="22" cy="22" r="18" stroke="#fff" strokeWidth="4" strokeLinecap="round"
                  strokeDasharray={`${2*Math.PI*18*0.78} 200`} transform="rotate(-90 22 22)"/>
                <circle cx="22" cy="22" r="12.5" stroke="#fff" strokeOpacity="0.78" strokeWidth="4" strokeLinecap="round"
                  strokeDasharray={`${2*Math.PI*12.5*0.62} 200`} transform="rotate(-90 22 22)"/>
                <circle cx="22" cy="22" r="7" stroke="#fff" strokeOpacity="0.58" strokeWidth="4" strokeLinecap="round"
                  strokeDasharray={`${2*Math.PI*7*0.92} 200`} transform="rotate(-90 22 22)"/>
              </svg>
            </div>
          </div>
        </GlassSurface>
      </div>

      <div style={{ textAlign: 'center' }}>
        <div style={{
          fontSize: 34, fontWeight: 800, color: T.fg, letterSpacing: -1.2, lineHeight: 1.08,
          textWrap: 'balance',
        }}>
          Welcome to<br/>Fitness Guru
        </div>
        <div style={{
          fontSize: 16, fontWeight: 500, color: T.fgMuted, marginTop: 14, lineHeight: 1.42,
          maxWidth: 300, textWrap: 'pretty',
        }}>
          Your AI training partner. Built for iOS 26 — connected to your health, calendar, and goals.
        </div>
      </div>
    </div>
  );
}

function PageConnect({ T, t, perms, setPerms }) {
  const items = [
    { key: 'health',    icon: Icons.heart,  color: T.red,    title: 'Apple Health',    detail: 'Steps, heart rate, sleep, workouts' },
    { key: 'watch',     icon: Icons.watch,  color: T.fg,     title: 'Apple Watch',     detail: 'Live HR + recovery tracking',     readonly: true },
    { key: 'calendar',  icon: Icons.cal,    color: T.blue,   title: 'Calendar',        detail: 'Plan workouts around your day' },
    { key: 'reminders', icon: Icons.bell,   color: T.orange, title: 'Reminders',       detail: 'Hydrate, recover, train on time' },
  ];
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '0 20px' }}>
      <div style={{
        fontSize: 30, fontWeight: 800, color: T.fg, letterSpacing: -1, lineHeight: 1.1,
        textWrap: 'balance',
      }}>Connect your health</div>
      <div style={{
        fontSize: 15, fontWeight: 500, color: T.fgMuted, marginTop: 8, lineHeight: 1.4,
        textWrap: 'pretty',
      }}>
        We read these to personalize your plan. You can change any of this later in Profile.
      </div>
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', gap: 10, marginTop: 20, overflow: 'auto' }}>
        {items.map(it => (
          <Card key={it.key} dark={T.dark} padding={14}>
            <div style={{ display: 'flex', alignItems: 'center', gap: 12 }}>
              <div style={{
                width: 40, height: 40, borderRadius: 12, background: `${it.color}26`, flexShrink: 0,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}>{it.icon(it.color, 20)}</div>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 15, fontWeight: 700, color: T.fg, letterSpacing: -0.3 }}>{it.title}</div>
                <div style={{ fontSize: 12, fontWeight: 500, color: T.fgMuted, marginTop: 1 }}>{it.detail}</div>
              </div>
              {it.readonly ? (
                <div style={{ fontSize: 11, fontWeight: 700, color: T.green, letterSpacing: 0.4 }}>VIA HEALTH</div>
              ) : (
                <Toggle T={T} value={perms[it.key]} onChange={(v) => setPerms({ ...perms, [it.key]: v })}/>
              )}
            </div>
          </Card>
        ))}
      </div>
    </div>
  );
}

function Toggle({ T, value, onChange }) {
  return (
    <div onClick={() => onChange(!value)} style={{
      width: 50, height: 30, borderRadius: 999, cursor: 'pointer',
      background: value ? T.green : (T.dark ? '#3a3a3c' : '#e5e5ea'),
      position: 'relative', flexShrink: 0,
      transition: 'background 180ms',
    }}>
      <div style={{
        position: 'absolute', top: 2, left: value ? 22 : 2,
        width: 26, height: 26, borderRadius: 999, background: '#fff',
        boxShadow: '0 2px 4px rgba(0,0,0,0.15)',
        transition: 'left 180ms',
      }}/>
    </div>
  );
}

function PageGoals({ T, t, goals, setGoals }) {
  const allGoals = [
    { id: 'endurance', label: 'Build endurance',  emoji: Icons.recovery,  color: T.green },
    { id: 'strength',  label: 'Get stronger',     emoji: Icons.bolt,      color: T.red },
    { id: 'weight',    label: 'Lose weight',      emoji: Icons.flame,     color: T.orange },
    { id: 'sleep',     label: 'Sleep better',     emoji: Icons.moon,      color: T.purple },
    { id: 'active',    label: 'Stay active',      emoji: Icons.walk,      color: T.cyan },
    { id: 'recover',   label: 'Recover faster',   emoji: Icons.heart,     color: T.pink },
  ];
  const toggle = (id) => setGoals(goals.includes(id) ? goals.filter(g => g !== id) : [...goals, id]);
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '0 20px' }}>
      <div style={{
        fontSize: 30, fontWeight: 800, color: T.fg, letterSpacing: -1, lineHeight: 1.1,
        textWrap: 'balance',
      }}>What are you training for?</div>
      <div style={{
        fontSize: 15, fontWeight: 500, color: T.fgMuted, marginTop: 8, lineHeight: 1.4,
      }}>Pick a few. Your coach will balance them.</div>
      <div style={{
        flex: 1, display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10, marginTop: 20,
        alignContent: 'start',
      }}>
        {allGoals.map(g => {
          const on = goals.includes(g.id);
          return (
            <div key={g.id} onClick={() => toggle(g.id)} style={{
              borderRadius: 18, padding: 14, cursor: 'pointer',
              background: on
                ? (T.dark ? `linear-gradient(135deg, ${hex(T.accent,0.28)} 0%, ${hex(T.accent,0.08)} 100%)` : `linear-gradient(135deg, ${hex(T.accent,0.18)} 0%, ${hex(T.accent,0.04)} 100%)`)
                : (T.dark ? '#1C1C1E' : '#fff'),
              border: on ? `1.5px solid ${T.accent}` : `1.5px solid transparent`,
              minHeight: 100,
              display: 'flex', flexDirection: 'column', justifyContent: 'space-between',
              transition: 'border 160ms, background 160ms',
            }}>
              <div style={{
                width: 36, height: 36, borderRadius: 10, background: `${g.color}26`,
                display: 'flex', alignItems: 'center', justifyContent: 'center',
              }}>{g.emoji(g.color, 18)}</div>
              <div style={{
                fontSize: 14, fontWeight: 700, color: T.fg, letterSpacing: -0.3, lineHeight: 1.15,
                textWrap: 'balance', marginTop: 8,
              }}>{g.label}</div>
            </div>
          );
        })}
      </div>
    </div>
  );
}

function PageCoach({ T, t }) {
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '0 20px' }}>
      <div style={{
        fontSize: 30, fontWeight: 800, color: T.fg, letterSpacing: -1, lineHeight: 1.1,
      }}>Meet your AI coach</div>
      <div style={{
        fontSize: 15, fontWeight: 500, color: T.fgMuted, marginTop: 8, lineHeight: 1.4,
        textWrap: 'pretty',
      }}>
        Reads your health to plan around your body — not a generic template.
      </div>

      {/* Coach message preview */}
      <div style={{ flex: 1, display: 'flex', flexDirection: 'column', justifyContent: 'center', gap: 12, paddingBottom: 20 }}>
        <Card dark={T.dark} padding={16} radius={20} style={{
          background: T.dark
            ? `linear-gradient(135deg, ${hex(T.accent,0.18)} 0%, rgba(28,28,30,0.95) 70%)`
            : `linear-gradient(135deg, ${hex(T.accent,0.14)} 0%, #fff 70%)`,
        }}>
          <div style={{ display: 'flex', alignItems: 'center', gap: 8, marginBottom: 10 }}>
            <div style={{
              width: 28, height: 28, borderRadius: 999,
              background: `linear-gradient(135deg, ${T.accent} 0%, ${T.purple} 100%)`,
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>{Icons.sparkle('#fff', 14)}</div>
            <span style={{ fontSize: 12, fontWeight: 700, color: T.accent, letterSpacing: 0.5 }}>COACH</span>
          </div>
          <div style={{
            fontSize: 15, lineHeight: 1.4, color: T.fg, fontWeight: 500, letterSpacing: -0.2,
            textWrap: 'pretty',
          }}>
            Your HRV is up 12% this week — push intensity today. I'll keep tomorrow's run easy so you bank the gains.
          </div>
        </Card>

        {/* Privacy reassurance */}
        <Card dark={T.dark} padding={14} radius={16}>
          <div style={{ display: 'flex', gap: 10 }}>
            {Icons.shield(T.green, 20)}
            <div style={{ flex: 1 }}>
              <div style={{ fontSize: 13, fontWeight: 700, color: T.fg, letterSpacing: -0.2 }}>Your data stays private</div>
              <div style={{ fontSize: 12, fontWeight: 500, color: T.fgMuted, marginTop: 2, lineHeight: 1.35 }}>
                Used only to personalize your plan. Photos for form-check are never stored.
              </div>
            </div>
          </div>
        </Card>
      </div>
    </div>
  );
}

function PageNotify({ T, t, perms, setPerms }) {
  const items = [
    { key: 'workout',    label: 'Workout reminders',  detail: 'Your planned sessions, 30 min before' },
    { key: 'hydration',  label: 'Hydration nudges',   detail: 'When you fall behind' },
    { key: 'recovery',   label: 'Recovery alerts',    detail: 'When your body needs rest' },
    { key: 'milestone',  label: 'Milestones',         detail: 'Streaks, PRs, recovery records' },
  ];
  return (
    <div style={{ flex: 1, display: 'flex', flexDirection: 'column', padding: '0 20px' }}>
      <div style={{ marginBottom: 24, marginTop: 8, display: 'flex', justifyContent: 'center' }}>
        <div style={{ position: 'relative', width: 110, height: 110 }}>
          <GlassSurface dark={T.dark} intensity="maximal" radius={28}
            style={{ width: 110, height: 110 }}>
            <div style={{
              width: '100%', height: '100%',
              display: 'flex', alignItems: 'center', justifyContent: 'center',
            }}>
              {Icons.bellFill(T.accent)}
            </div>
          </GlassSurface>
          <div style={{
            position: 'absolute', top: -2, right: -2,
            width: 22, height: 22, borderRadius: 999,
            background: T.red, color: '#fff', fontSize: 12, fontWeight: 800,
            display: 'flex', alignItems: 'center', justifyContent: 'center',
            border: `2px solid ${T.bg}`,
            boxShadow: `0 4px 10px ${hex(T.red, 0.4)}`,
          }}>3</div>
        </div>
      </div>
      <div style={{
        fontSize: 30, fontWeight: 800, color: T.fg, letterSpacing: -1, lineHeight: 1.1,
        textAlign: 'center',
      }}>Stay on track</div>
      <div style={{
        fontSize: 15, fontWeight: 500, color: T.fgMuted, marginTop: 8, lineHeight: 1.4,
        textAlign: 'center', textWrap: 'pretty', padding: '0 8px',
      }}>Smart, never spammy. You can turn each off individually.</div>

      <div style={{ marginTop: 18, display: 'flex', flexDirection: 'column' }}>
        <Card dark={T.dark} padding={0} radius={18}>
          {items.map((it, i) => (
            <div key={it.key} style={{
              display: 'flex', alignItems: 'center', padding: '12px 14px',
              borderBottom: i < items.length - 1 ? `0.5px solid ${T.hairline}` : 'none',
            }}>
              <div style={{ flex: 1 }}>
                <div style={{ fontSize: 14, fontWeight: 600, color: T.fg, letterSpacing: -0.3 }}>{it.label}</div>
                <div style={{ fontSize: 11, fontWeight: 500, color: T.fgMuted, marginTop: 1 }}>{it.detail}</div>
              </div>
              <Toggle T={T} value={perms[it.key] ?? true} onChange={(v) => setPerms({ ...perms, [it.key]: v })}/>
            </div>
          ))}
        </Card>
      </div>
    </div>
  );
}

window.OnboardingScreen = OnboardingScreen;
