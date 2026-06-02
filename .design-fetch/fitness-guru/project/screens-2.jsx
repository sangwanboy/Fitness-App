// screens-2.jsx — Reminders, Profile, Workout detail, Calendar

// ─────────────────────────────────────────────────────────────
// REMINDERS
// ─────────────────────────────────────────────────────────────
function RemindersScreen({ T, t, tab, setTab }) {
  const [items, setItems] = React.useState(SEED_REMINDERS);
  const toggle = (i) => setItems(arr => arr.map((it, j) => j === i ? { ...it, done: !it.done } : it));

  const groups = {
    'Today':     items.filter(x => x.when === 'today'),
    'Tomorrow':  items.filter(x => x.when === 'tomorrow'),
    'Scheduled': items.filter(x => x.when === 'later'),
  };

  return (
    <ScreenShell T={T} t={t} tab={tab} setTab={setTab}
      navContent={
        <TopNav T={T} t={t}
          subtitle="3 due today"
          title="Reminders"
          trailing={
            <GlassPill dark={T.dark} intensity={t.glass} size={40}>
              {Icons.add(T.accent, 22)}
            </GlassPill>
          }
        />
      }>
      <div style={{ display: 'flex', flexDirection: 'column', gap: 18, paddingTop: 4 }}>
        {Object.entries(groups).map(([title, list]) => list.length > 0 && (
          <div key={title}>
            <div style={{
              fontSize: 13, fontWeight: 600, color: T.fgMuted,
              textTransform: 'uppercase', letterSpacing: 0.4,
              padding: '4px 16px 8px',
            }}>{title}</div>
            <Card dark={T.dark} padding={0} radius={20}>
              {list.map((it, i) => {
                const idx = items.indexOf(it);
                return (
                  <ReminderRow key={i} item={it} T={T} onToggle={() => toggle(idx)} isLast={i === list.length-1}/>
                );
              })}
            </Card>
          </div>
        ))}

        {/* Categories nav */}
        <div>
          <div style={{
            fontSize: 13, fontWeight: 600, color: T.fgMuted,
            textTransform: 'uppercase', letterSpacing: 0.4,
            padding: '4px 16px 8px',
          }}>Categories</div>
          <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 10 }}>
            <CatTile icon={Icons.bolt} count={5} label="Workouts" color={T.accent} T={T}/>
            <CatTile icon={Icons.drop} count={4} label="Hydration" color={T.cyan} T={T}/>
            <CatTile icon={Icons.pill} count={2} label="Supplements" color={T.orange} T={T}/>
            <CatTile icon={Icons.moon} count={1} label="Sleep" color={T.purple} T={T}/>
          </div>
        </div>
      </div>
    </ScreenShell>
  );
}

function ReminderRow({ item, T, onToggle, isLast }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', minHeight: 56,
      padding: '10px 14px 10px 16px', position: 'relative',
    }}>
      <div onClick={onToggle} style={{
        width: 24, height: 24, borderRadius: 999, flexShrink: 0,
        border: `2px solid ${item.done ? T.accent : T.fgFaint}`,
        background: item.done ? T.accent : 'transparent',
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        marginRight: 12, cursor: 'pointer',
      }}>
        {item.done && Icons.check('#fff', 14)}
      </div>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{
          fontSize: 15, fontWeight: 500, letterSpacing: -0.3,
          color: item.done ? T.fgMuted : T.fg,
          textDecoration: item.done ? 'line-through' : 'none',
          textDecorationColor: T.fgFaint,
        }}>{item.title}</div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 6, marginTop: 2 }}>
          <span style={{ display: 'flex' }}>{item.icon(item.color, 12)}</span>
          <span style={{ fontSize: 12, color: T.fgMuted, fontWeight: 500 }}>{item.time}</span>
          {item.tag && (
            <span style={{
              fontSize: 10, fontWeight: 700, padding: '2px 7px', borderRadius: 999,
              background: `${item.color}22`, color: item.color, letterSpacing: 0.3,
            }}>{item.tag}</span>
          )}
        </div>
      </div>
      {Icons.chev(T.fgFaint, 14)}
      {!isLast && (
        <div style={{ position: 'absolute', bottom: 0, left: 52, right: 0, height: 0.5, background: T.hairline }} />
      )}
    </div>
  );
}

function CatTile({ icon, count, label, color, T }) {
  return (
    <Card dark={T.dark} padding={14}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
        <div style={{
          width: 36, height: 36, borderRadius: 10,
          background: `${color}22`,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>{icon(color, 18)}</div>
        <div>
          <div style={{ fontSize: 22, fontWeight: 700, color: T.fg, letterSpacing: -0.6, lineHeight: 1 }}>{count}</div>
        </div>
      </div>
      <div style={{ fontSize: 13, fontWeight: 600, color: T.fg, letterSpacing: -0.2, marginTop: 8 }}>{label}</div>
    </Card>
  );
}

const SEED_REMINDERS = [
  { title: 'Drink water', time: '11:00 AM',  when: 'today',    icon: Icons.drop, color: '#64D2FF', tag: 'HYDRATION', done: true },
  { title: 'Magnesium glycinate', time: '8:00 PM', when: 'today', icon: Icons.pill, color: '#FF9F0A', tag: 'SUPPLEMENT', done: false },
  { title: 'Zone 2 run · 45 min', time: '6:30 PM', when: 'today', icon: Icons.bolt, color: '#30D158', tag: 'WORKOUT', done: false },
  { title: 'Upper body strength', time: '7:00 AM', when: 'tomorrow', icon: Icons.bolt, color: '#30D158', tag: 'WORKOUT', done: false },
  { title: 'Wind down', time: '10:00 PM', when: 'tomorrow', icon: Icons.moon, color: '#BF5AF2', tag: 'SLEEP', done: false },
  { title: 'Long run · 90 min', time: 'Sat 8:00 AM', when: 'later', icon: Icons.bolt, color: '#30D158', tag: 'WORKOUT', done: false },
  { title: 'Refill Vitamin D', time: 'Fri', when: 'later', icon: Icons.pill, color: '#FF9F0A', tag: 'SUPPLEMENT', done: false },
];

// ─────────────────────────────────────────────────────────────
// PROFILE
// ─────────────────────────────────────────────────────────────
function ProfileScreen({ T, t, tab, setTab, onLogout }) {
  return (
    <ScreenShell T={T} t={t} tab={tab} setTab={setTab}
      navContent={
        <TopNav T={T} t={t}
          subtitle="Account & integrations"
          title="Profile"
          trailing={
            <GlassPill dark={T.dark} intensity={t.glass} size={40}>
              {Icons.more(T.fg)}
            </GlassPill>
          }
        />
      }>
      {/* Avatar header */}
      <div style={{
        display: 'flex', flexDirection: 'column', alignItems: 'center',
        gap: 12, padding: '8px 0 20px',
      }}>
        <div style={{
          width: 96, height: 96, borderRadius: 999,
          background: `linear-gradient(135deg, ${T.accent} 0%, ${T.purple} 100%)`,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
          color: '#fff', fontWeight: 700, fontSize: 36, letterSpacing: -1.2,
          boxShadow: `0 12px 32px ${hex(T.accent, 0.35)}`,
        }}>{t.userName.split(' ').map(w => w[0]).join('').slice(0,2).toUpperCase()}</div>
        <div style={{ textAlign: 'center' }}>
          <div style={{ fontSize: 22, fontWeight: 700, color: T.fg, letterSpacing: -0.6 }}>{t.userName}</div>
          <div style={{ fontSize: 13, fontWeight: 500, color: T.fgMuted }}>Joined Mar 2025 · 184 day streak</div>
        </div>
        <div style={{ display: 'flex', gap: 8, marginTop: 4 }}>
          {Icons.apple(T.fgMuted, 14)}
          <span style={{ fontSize: 12, fontWeight: 600, color: T.fgMuted }}>Signed in with Apple</span>
        </div>
      </div>

      {/* Stat row */}
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 10, marginBottom: 18 }}>
        <StatTile T={T} v="184" label="Day streak" c={T.orange}/>
        <StatTile T={T} v="62" label="Resting HR" c={T.red}/>
        <StatTile T={T} v="74" label="Recovery" c={T.green}/>
      </div>

      {/* Lists */}
      <ListGroup T={T} header="Connected">
        <ListRow T={T} icon={Icons.heart} color={T.red} title="Apple Health" detail="On · 14 sources" />
        <ListRow T={T} icon={Icons.watch} color={T.fg} title="Apple Watch Ultra" detail="Connected" />
        <ListRow T={T} icon={Icons.cal} color={T.blue} title="Calendar" detail="iCloud · Work" />
        <ListRow T={T} icon={Icons.bell} color={T.orange} title="Reminders" detail="On" last />
      </ListGroup>

      <ListGroup T={T} header="AI Coach">
        <ListRow T={T} icon={Icons.sparkle} color={T.accent} title="Coach personality" detail="Direct" />
        <ListRow T={T} icon={Icons.shield} color={T.green} title="Data permissions" detail="Health, Calendar" />
        <ListRow T={T} icon={Icons.ring} color={T.purple} title="Training goals" detail="Endurance + strength" last />
      </ListGroup>

      <ListGroup T={T} header="Account">
        <ListRow T={T} icon={Icons.person} color={T.blue} title="Personal details" />
        <ListRow T={T} icon={Icons.bell} color={T.orange} title="Notifications" />
        <ListRow T={T} icon={Icons.shield} color={T.green} title="Privacy" />
        <ListRow T={T} title="Sign out" titleColor={T.red} chevron={false} onClick={onLogout} last />
      </ListGroup>

      <div style={{
        textAlign: 'center', fontSize: 12, color: T.fgFaint, fontWeight: 500,
        padding: '20px 0 8px',
      }}>Fitness Guru · 1.0 · build 248</div>
    </ScreenShell>
  );
}

function StatTile({ T, v, label, c }) {
  return (
    <Card dark={T.dark} padding={12}>
      <div style={{ fontSize: 22, fontWeight: 700, color: c, letterSpacing: -0.7, lineHeight: 1 }}>{v}</div>
      <div style={{ fontSize: 11, fontWeight: 600, color: T.fgMuted, marginTop: 6, letterSpacing: -0.2 }}>{label}</div>
    </Card>
  );
}

function ListGroup({ T, header, children }) {
  return (
    <div style={{ marginBottom: 18 }}>
      {header && <div style={{
        fontSize: 13, fontWeight: 600, color: T.fgMuted,
        textTransform: 'uppercase', letterSpacing: 0.4,
        padding: '0 16px 8px',
      }}>{header}</div>}
      <Card dark={T.dark} padding={0} radius={20}>{children}</Card>
    </div>
  );
}

function ListRow({ T, icon, color, title, titleColor, detail, last, chevron = true, onClick }) {
  return (
    <div onClick={onClick} style={{
      display: 'flex', alignItems: 'center', minHeight: 48,
      padding: '8px 14px 8px 14px', position: 'relative',
      cursor: onClick ? 'pointer' : undefined,
    }}>
      {icon && (
        <div style={{
          width: 30, height: 30, borderRadius: 8,
          background: `${color}26`, marginRight: 12, flexShrink: 0,
          display: 'flex', alignItems: 'center', justifyContent: 'center',
        }}>{icon(color, 16)}</div>
      )}
      <div style={{ flex: 1, fontSize: 15, fontWeight: 500, color: titleColor || T.fg, letterSpacing: -0.3 }}>{title}</div>
      {detail && <div style={{ fontSize: 14, color: T.fgMuted, marginRight: 6, fontWeight: 500 }}>{detail}</div>}
      {chevron && Icons.chev(T.fgFaint, 14)}
      {!last && (
        <div style={{ position: 'absolute', bottom: 0, left: icon ? 56 : 14, right: 0, height: 0.5, background: T.hairline }} />
      )}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// WORKOUT DETAIL (presented from Home/Calendar — back button to home)
// ─────────────────────────────────────────────────────────────
function WorkoutScreen({ T, t, onBack, tab, setTab }) {
  return (
    <ScreenShell T={T} t={t} tab={tab} setTab={setTab} contentPad={false}
      navContent={null}>
      {/* Hero */}
      <div style={{
        position: 'relative', height: 320, width: '100%',
        background: `linear-gradient(180deg, ${T.accent}AA 0%, ${T.accent}55 50%, ${T.bg} 100%),
                     radial-gradient(ellipse at 30% 30%, ${T.purple}55, transparent 60%),
                     linear-gradient(135deg, ${T.accent} 0%, ${T.purple} 100%)`,
        overflow: 'hidden',
      }}>
        {/* nav pills */}
        <div style={{
          position: 'absolute', top: 56, left: 16, right: 16, zIndex: 5,
          display: 'flex', justifyContent: 'space-between',
        }}>
          <GlassPill dark intensity={t.glass} size={40} onClick={onBack}>
            {Icons.back('#fff', 22)}
          </GlassPill>
          <div style={{ display: 'flex', gap: 8 }}>
            <GlassPill dark intensity={t.glass} size={40}>{Icons.more('#fff')}</GlassPill>
          </div>
        </div>
        {/* Title overlay */}
        <div style={{
          position: 'absolute', bottom: 50, left: 20, right: 20,
          color: '#fff',
        }}>
          <div style={{ fontSize: 13, fontWeight: 700, letterSpacing: 0.6, textTransform: 'uppercase', opacity: 0.85 }}>
            Today · 6:30 PM
          </div>
          <div style={{ fontSize: 34, fontWeight: 700, letterSpacing: -1, lineHeight: 1.05, marginTop: 2, textWrap: 'balance' }}>
            Zone 2 run
          </div>
          <div style={{ fontSize: 15, fontWeight: 500, opacity: 0.92, marginTop: 4 }}>
            Easy effort · Riverside loop · 5.2 mi planned
          </div>
        </div>
      </div>

      {/* Content */}
      <div style={{ padding: '16px 16px 0', display: 'flex', flexDirection: 'column', gap: 14, marginTop: -10 }}>
        {/* Stats row */}
        <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3, 1fr)', gap: 10 }}>
          <WStat T={T} v="45" unit="MIN" label="Duration" c={T.accent}/>
          <WStat T={T} v="135" unit="BPM" label="Target HR" c={T.red}/>
          <WStat T={T} v="420" unit="CAL" label="Est. burn" c={T.orange}/>
        </div>

        {/* Why this workout */}
        <Card dark={T.dark} padding={14}>
          <CardHead icon={Icons.sparkle(T.accent, 16)} title="Why coach picked this" color={T.accent} dark={T.dark}/>
          <div style={{ fontSize: 14, lineHeight: 1.42, color: T.fg, fontWeight: 500, letterSpacing: -0.2, textWrap: 'pretty' }}>
            Recovery (74) supports an aerobic session, but you ran tempo Sunday. A zone 2 effort builds your base without taxing the same systems.
          </div>
        </Card>

        {/* Plan */}
        <ListGroup T={T} header="Session plan">
          <PlanRow T={T} label="Warm-up" detail="5 min · easy" color={T.green}/>
          <PlanRow T={T} label="Steady state" detail="35 min · 130-140 bpm" color={T.accent}/>
          <PlanRow T={T} label="Cool-down" detail="5 min · walk" color={T.cyan} last/>
        </ListGroup>

        {/* History */}
        <Card dark={T.dark} padding={14}>
          <CardHead icon={Icons.recovery(T.purple, 16)} title="Last 4 zone 2 runs" color={T.purple} dark={T.dark} right={
            <span style={{ fontSize: 12, fontWeight: 600, color: T.fgMuted }}>avg pace 9:42</span>
          }/>
          <div style={{ marginLeft: -4, marginRight: -4 }}>
            <Bars values={[35, 42, 40, 45]} labels={['Sep 28','Oct 5','Oct 9','Today']} color={T.purple} width={280} height={60} highlight={3} dark={T.dark}/>
          </div>
        </Card>

        <div style={{ height: 80 }}/>
      </div>

      {/* Floating start button */}
      <div style={{
        position: 'absolute', left: 14, right: 14, bottom: 96, zIndex: 28,
        display: 'flex', gap: 10,
      }}>
        <GlassSurface dark={T.dark} intensity={t.glass} radius={26}
          style={{ width: 56, height: 56 }}>
          <div style={{
            width: '100%', height: '100%',
            display: 'flex', alignItems: 'center', justifyContent: 'center',
          }}>
            {Icons.cal(T.fg, 22)}
          </div>
        </GlassSurface>
        <button style={{
          flex: 1, height: 56, borderRadius: 26, border: 'none', cursor: 'pointer',
          background: T.accent, color: '#fff', fontSize: 17, fontWeight: 700, letterSpacing: -0.3,
          fontFamily: 'inherit',
          boxShadow: `0 8px 28px ${hex(T.accent, 0.4)}`,
          display: 'flex', alignItems: 'center', justifyContent: 'center', gap: 8,
        }}>
          {Icons.bolt('#fff', 22)}
          Start workout
        </button>
      </div>
    </ScreenShell>
  );
}

function WStat({ T, v, unit, label, c }) {
  return (
    <Card dark={T.dark} padding={12}>
      <div style={{ display: 'flex', alignItems: 'baseline', gap: 3 }}>
        <span style={{ fontSize: 22, fontWeight: 700, color: c, letterSpacing: -0.7, lineHeight: 1 }}>{v}</span>
        <span style={{ fontSize: 11, fontWeight: 700, color: T.fgMuted, letterSpacing: 0.3 }}>{unit}</span>
      </div>
      <div style={{ fontSize: 11, fontWeight: 600, color: T.fgMuted, marginTop: 4, letterSpacing: -0.2 }}>{label}</div>
    </Card>
  );
}

function PlanRow({ T, label, detail, color, last }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', minHeight: 52, padding: '10px 14px',
      position: 'relative',
    }}>
      <div style={{
        width: 32, height: 32, borderRadius: 999, flexShrink: 0, marginRight: 12,
        background: `${color}26`, display: 'flex', alignItems: 'center', justifyContent: 'center',
      }}>
        <div style={{ width: 10, height: 10, borderRadius: 999, background: color }} />
      </div>
      <div style={{ flex: 1 }}>
        <div style={{ fontSize: 15, fontWeight: 600, color: T.fg, letterSpacing: -0.3 }}>{label}</div>
        <div style={{ fontSize: 12, fontWeight: 500, color: T.fgMuted, marginTop: 1 }}>{detail}</div>
      </div>
      {!last && <div style={{ position: 'absolute', bottom: 0, left: 58, right: 0, height: 0.5, background: T.hairline }} />}
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// CALENDAR
// ─────────────────────────────────────────────────────────────
function CalendarScreen({ T, t, tab, setTab, onOpenWorkout }) {
  const [view, setView] = React.useState('week'); // week | month
  const [selected, setSelected] = React.useState(14);

  const ViewToggle = (
    <GlassSurface dark={T.dark} intensity={t.glass} radius={9999}
      style={{ display: 'inline-flex', padding: 3, height: 40 }}>
      <div style={{ display: 'flex', height: '100%', alignItems: 'center' }}>
        {['Week', 'Month'].map(v => {
          const on = view.toLowerCase() === v.toLowerCase();
          return (
            <div key={v} onClick={() => setView(v.toLowerCase())} style={{
              padding: '0 14px', height: 34, borderRadius: 9999, cursor: 'pointer',
              display: 'flex', alignItems: 'center',
              background: on ? T.accent : 'transparent',
              fontSize: 13, fontWeight: 600, color: on ? '#fff' : T.fg, letterSpacing: -0.2,
              boxShadow: on ? `0 1px 4px ${hex(T.accent, 0.3)}` : 'none',
              transition: 'background 180ms, color 180ms',
            }}>{v}</div>
          );
        })}
      </div>
    </GlassSurface>
  );

  // Custom top nav: title and controls in the SAME row
  const CalendarNav = (
    <div style={{
      position: 'absolute', top: 0, left: 0, right: 0, zIndex: 5,
      paddingTop: 56,
    }}>
      <div style={{
        fontSize: 13, fontWeight: 600, color: T.fgMuted,
        textTransform: 'uppercase', letterSpacing: 0.5,
        padding: '8px 20px 2px',
      }}>October 2025</div>
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'space-between',
        padding: '0 16px 0 20px', gap: 10, minHeight: 48,
      }}>
        <div style={{
          fontSize: 32, fontWeight: 700, color: T.fg, letterSpacing: -0.8, lineHeight: 1.1, flexShrink: 0,
        }}>Calendar</div>
        <div style={{ display: 'flex', alignItems: 'center', gap: 8, flexShrink: 0 }}>
          {ViewToggle}
          <GlassPill dark={T.dark} intensity={t.glass} size={40}>
            {Icons.add(T.accent, 22)}
          </GlassPill>
        </div>
      </div>
    </div>
  );

  return (
    <ScreenShell T={T} t={t} tab={tab} setTab={setTab}
      navContent={CalendarNav}>
      {/* Week strip or month grid */}
      <div style={{ paddingTop: 4 }}>
        {view === 'week'
          ? <WeekStrip T={T} selected={selected} setSelected={setSelected}/>
          : <MonthGrid T={T} selected={selected} setSelected={setSelected}/>
        }
      </div>

      {/* Day plan */}
      <div style={{
        fontSize: 13, fontWeight: 600, color: T.fgMuted,
        textTransform: 'uppercase', letterSpacing: 0.4,
        padding: '20px 16px 8px',
      }}>Tuesday, Oct {selected}</div>
      <Card dark={T.dark} padding={0} radius={20}>
        <DayEvent T={T} time="7:00 AM" name="Mobility · 10 min" color={T.cyan} icon={Icons.recovery} done/>
        <DayEvent T={T} time="11:00 AM" name="Team standup" color={T.fgMuted} icon={Icons.cal} muted/>
        <DayEvent T={T} time="6:30 PM" name="Zone 2 run · 45 min" color={T.accent} icon={Icons.bolt} onClick={onOpenWorkout}/>
        <DayEvent T={T} time="10:00 PM" name="Wind down" color={T.purple} icon={Icons.moon} last/>
      </Card>

      <div style={{
        fontSize: 13, fontWeight: 600, color: T.fgMuted,
        textTransform: 'uppercase', letterSpacing: 0.4,
        padding: '20px 16px 8px',
      }}>This week's plan</div>
      <Card dark={T.dark} padding={14}>
        <CardHead icon={Icons.sparkle(T.accent, 16)} title="AI-built · Endurance block" color={T.accent} dark={T.dark} right={
          <span style={{ fontSize: 12, fontWeight: 600, color: T.fgMuted }}>5 of 7 sessions</span>
        }/>
        <div style={{ marginLeft: -4, marginRight: -4, marginTop: 4 }}>
          <Bars values={[40, 10, 45, 30, 0, 90, 25]} labels={['M','T','W','T','F','S','S']}
            color={T.accent} width={280} height={56} highlight={1} dark={T.dark}/>
        </div>
      </Card>
    </ScreenShell>
  );
}

function WeekStrip({ T, selected, setSelected }) {
  const days = [
    { d: 13, l: 'Mon', dots: ['#30D158','#BF5AF2'] },
    { d: 14, l: 'Tue', dots: ['#30D158','#64D2FF','#BF5AF2'] },
    { d: 15, l: 'Wed', dots: ['#30D158'] },
    { d: 16, l: 'Thu', dots: ['#30D158','#FF9F0A'] },
    { d: 17, l: 'Fri', dots: [] },
    { d: 18, l: 'Sat', dots: ['#30D158','#30D158','#30D158'] },
    { d: 19, l: 'Sun', dots: ['#BF5AF2'] },
  ];
  return (
    <div style={{ display: 'flex', justifyContent: 'space-between', gap: 6, padding: '0 4px' }}>
      {days.map(day => {
        const on = day.d === selected;
        return (
          <div key={day.d} onClick={() => setSelected(day.d)} style={{
            flex: 1, height: 76, borderRadius: 14, cursor: 'pointer',
            background: on ? T.accent : (T.dark ? 'rgba(255,255,255,0.06)' : 'rgba(255,255,255,0.55)'),
            border: on ? 'none' : `0.5px solid ${T.hairline}`,
            display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'space-between',
            padding: '10px 0 8px',
            color: on ? '#fff' : T.fg,
          }}>
            <div>
              <div style={{ fontSize: 11, fontWeight: 700, opacity: 0.8, letterSpacing: 0.3, textTransform: 'uppercase', textAlign: 'center' }}>{day.l}</div>
              <div style={{ fontSize: 20, fontWeight: 700, letterSpacing: -0.6, textAlign: 'center', lineHeight: 1.1 }}>{day.d}</div>
            </div>
            <div style={{ display: 'flex', gap: 3 }}>
              {day.dots.slice(0,3).map((c, i) => (
                <div key={i} style={{
                  width: 5, height: 5, borderRadius: 999,
                  background: on ? '#fff' : c,
                }}/>
              ))}
            </div>
          </div>
        );
      })}
    </div>
  );
}

function MonthGrid({ T, selected, setSelected }) {
  const start = 28; // last Sept; offset
  const cells = [];
  for (let i = 0; i < 35; i++) {
    const date = i - 2; // first row partially Sep 28-30
    cells.push(date);
  }
  return (
    <div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7,1fr)', gap: 4, padding: '0 4px 6px' }}>
        {['S','M','T','W','T','F','S'].map((d, i) => (
          <div key={i} style={{ textAlign: 'center', fontSize: 10, fontWeight: 700, color: T.fgMuted, letterSpacing: 0.4 }}>{d}</div>
        ))}
      </div>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(7,1fr)', gap: 4, padding: '0 4px' }}>
        {cells.map((c, i) => {
          if (c < 1 || c > 31) return <div key={i} style={{ height: 44 }}/>;
          const on = c === selected;
          const today = c === 14;
          const hasEvent = [3,5,7,8,10,12,13,14,16,18,19,21,23,25,28].includes(c);
          const colors = c === 18 ? ['#30D158','#30D158','#FF9F0A'] : c === 14 ? ['#30D158','#64D2FF','#BF5AF2'] : c === 8 ? ['#30D158','#BF5AF2'] : ['#30D158'];
          return (
            <div key={i} onClick={() => setSelected(c)} style={{
              height: 44, borderRadius: 10, cursor: 'pointer',
              background: on ? T.accent : 'transparent',
              border: today && !on ? `1.5px solid ${T.accent}` : '0.5px solid transparent',
              display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center',
              color: on ? '#fff' : T.fg,
            }}>
              <div style={{ fontSize: 14, fontWeight: today || on ? 700 : 500, letterSpacing: -0.2 }}>{c}</div>
              {hasEvent && (
                <div style={{ display: 'flex', gap: 2, marginTop: 2 }}>
                  {colors.slice(0,3).map((cc, j) => (
                    <div key={j} style={{ width: 3, height: 3, borderRadius: 999, background: on ? '#fff' : cc }}/>
                  ))}
                </div>
              )}
            </div>
          );
        })}
      </div>
    </div>
  );
}

function DayEvent({ T, time, name, color, icon, done, muted, last, onClick }) {
  return (
    <div onClick={onClick} style={{
      display: 'flex', alignItems: 'center', minHeight: 60, padding: '10px 14px',
      position: 'relative', cursor: onClick ? 'pointer' : undefined,
    }}>
      <div style={{
        width: 4, alignSelf: 'stretch', borderRadius: 2, background: color, opacity: muted ? 0.4 : 1,
        marginRight: 12,
      }}/>
      <div style={{ flex: 1, minWidth: 0 }}>
        <div style={{ fontSize: 12, fontWeight: 700, color: T.fgMuted, letterSpacing: 0.3, textTransform: 'uppercase' }}>{time}</div>
        <div style={{
          fontSize: 15, fontWeight: 600, color: muted ? T.fgMuted : T.fg, letterSpacing: -0.3,
          textDecoration: done ? 'line-through' : 'none', textDecorationColor: T.fgFaint, marginTop: 2,
        }}>{name}</div>
      </div>
      <div style={{
        width: 34, height: 34, borderRadius: 9, marginLeft: 8, flexShrink: 0,
        background: `${color}22`, display: 'flex', alignItems: 'center', justifyContent: 'center', opacity: muted ? 0.55 : 1,
      }}>{icon(color, 16)}</div>
      {!last && <div style={{ position: 'absolute', bottom: 0, left: 30, right: 0, height: 0.5, background: T.hairline }} />}
    </div>
  );
}

window.RemindersScreen = RemindersScreen;
window.ProfileScreen = ProfileScreen;
window.WorkoutScreen = WorkoutScreen;
window.CalendarScreen = CalendarScreen;
