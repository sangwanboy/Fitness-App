// app.jsx — shared store, device frame, FitnessApp, design canvas layout

const TWEAK_DEFAULTS = /*EDITMODE-BEGIN*/{
  "theme": "dark",
  "accent": "#30D158",
  "glass": "moderate",
  "glassTint": "#30D158",
  "glassTintStrength": 0,
  "bgStyle": "gradient",
  "density": "regular",
  "userName": "Alex Rivera",
  "homeCards": ["coach", "activity", "upcoming", "steps", "heart", "sleep", "calories", "recovery", "hydration", "workouts"],
  "loggedIn": true,
  "onboarded": true,
  "deviceFocus": "all"
}/*EDITMODE-END*/;

// ─────────────────────────────────────────────────────────────
// Shared tweak store — broadcasts to all canvas instances
// ─────────────────────────────────────────────────────────────
const tweakStore = {
  state: { ...TWEAK_DEFAULTS },
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
function useT() {
  React.useSyncExternalStore(
    (cb) => tweakStore.subscribe(cb),
    () => tweakStore.state
  );
  return [tweakStore.state, tweakStore.set.bind(tweakStore)];
}

// ─────────────────────────────────────────────────────────────
// Device frame — dynamic island + home indicator + clipping
// ─────────────────────────────────────────────────────────────
function DeviceFrame({ width, height, dark, glassTint, glassTintStrength, children, label }) {
  const tintAlpha = Math.max(0, Math.min(1, (glassTintStrength || 0) / 100));
  return (
    <div style={{
      width, height, borderRadius: 52, position: 'relative', overflow: 'hidden',
      background: dark ? '#000' : '#F2F2F7',
      '--glass-tint': glassTint || 'transparent',
      '--glass-tint-alpha': tintAlpha,
      boxShadow: dark
        ? '0 30px 80px rgba(0,0,0,0.55), 0 0 0 8px #0c0c0e, 0 0 0 9px #2a2a2c'
        : '0 30px 80px rgba(0,0,0,0.18), 0 0 0 8px #1a1a1c, 0 0 0 9px #2c2c2e',
      fontFamily: '-apple-system, "SF Pro", system-ui, sans-serif',
      WebkitFontSmoothing: 'antialiased',
    }}>
      {/* dynamic island */}
      <div style={{
        position: 'absolute', top: 11, left: '50%', transform: 'translateX(-50%)',
        width: 124, height: 36, borderRadius: 22, background: '#000', zIndex: 100,
        pointerEvents: 'none',
      }} />
      {/* content */}
      {children}
      {/* home indicator */}
      <div style={{
        position: 'absolute', bottom: 8, left: 0, right: 0, zIndex: 60,
        display: 'flex', justifyContent: 'center', alignItems: 'flex-end', pointerEvents: 'none',
      }}>
        <div style={{
          width: 134, height: 5, borderRadius: 100,
          background: dark ? 'rgba(255,255,255,0.55)' : 'rgba(0,0,0,0.3)',
        }} />
      </div>
    </div>
  );
}

// ─────────────────────────────────────────────────────────────
// FitnessApp — orchestrates routing across screens
// ─────────────────────────────────────────────────────────────
function FitnessApp({ width, height, initialScreen = 'home' }) {
  const [t, setT] = useT();
  const T = getTheme(t);
  const [tab, setTab] = React.useState(() => (
    ['home','chat','reminders','profile'].includes(initialScreen) ? initialScreen : 'home'
  ));
  const [modal, setModal] = React.useState(initialScreen === 'workout' ? 'workout' : initialScreen === 'calendar' ? 'calendar' : null);

  const openWorkout = () => setModal('workout');
  const openCalendar = () => setModal('calendar');
  const closeModal = () => setModal(null);

  const [completedOnboarding, setCompletedOnboarding] = React.useState(false);
  const showOnboarding = !completedOnboarding && (initialScreen === 'onboarding' || !t.onboarded);
  const showLogin = !showOnboarding && (!t.loggedIn || initialScreen === 'login');

  return (
    <DeviceFrame width={width} height={height} dark={T.dark}
      glassTint={t.glassTint} glassTintStrength={t.glassTintStrength}>
      {showOnboarding ? (
        <OnboardingScreen T={T} t={t} onComplete={() => {
          setCompletedOnboarding(true);
          if (!t.onboarded) setT({ onboarded: true });
        }}/>
      ) : showLogin ? (
        <LoginScreen T={T} t={t} onLogin={() => setT('loggedIn', true)}/>
      ) : modal === 'workout' ? (
        <WorkoutScreen T={T} t={t} onBack={closeModal} tab={tab} setTab={(x) => { setTab(x); closeModal(); }}/>
      ) : modal === 'calendar' ? (
        <CalendarScreen T={T} t={t} tab={tab} setTab={(x) => { setTab(x); closeModal(); }} onOpenWorkout={openWorkout}/>
      ) : tab === 'home' ? (
        <HomeWithCalendar T={T} t={t} tab={tab} setTab={setTab} onOpenWorkout={openWorkout} onOpenCalendar={openCalendar}/>
      ) : tab === 'chat' ? (
        <ChatScreen T={T} t={t} tab={tab} setTab={setTab}/>
      ) : tab === 'reminders' ? (
        <RemindersScreen T={T} t={t} tab={tab} setTab={setTab}/>
      ) : (
        <ProfileScreen T={T} t={t} tab={tab} setTab={setTab} onLogout={() => setT('loggedIn', false)}/>
      )}
    </DeviceFrame>
  );
}

// Wrap HomeScreen to add a "Calendar" affordance via the search pill area
function HomeWithCalendar({ T, t, tab, setTab, onOpenWorkout, onOpenCalendar }) {
  // Patch HomeScreen with a calendar shortcut button in nav trailing
  return <HomeScreen T={T} t={t} tab={tab} setTab={setTab} onOpenWorkout={onOpenWorkout} onOpenCalendar={onOpenCalendar}/>;
}

// ─────────────────────────────────────────────────────────────
// Tweaks panel (uses shared store)
// ─────────────────────────────────────────────────────────────
function Panel() {
  const [t] = useT();
  const setTweak = (k, v) => tweakStore.set(k, v);
  const allCards = ['coach','activity','upcoming','steps','heart','sleep','calories','recovery','hydration','workouts'];
  const cardLabels = {
    coach: 'AI coach summary', activity: 'Activity rings', upcoming: 'Up next workout',
    steps: 'Steps', heart: 'Heart rate', sleep: 'Sleep', calories: 'Calories',
    recovery: 'Recovery / HRV', hydration: 'Hydration', workouts: 'This week',
  };
  const toggleCard = (id) => {
    const current = t.homeCards.includes(id);
    const next = current ? t.homeCards.filter(c => c !== id) : [...t.homeCards, id];
    setTweak('homeCards', next);
  };

  return (
    <TweaksPanel title="Fitness Guru">
      <TweakSection label="Appearance" />
      <TweakRadio label="Mode" value={t.theme}
        options={[{value:'light',label:'Light'},{value:'dark',label:'Dark'}]}
        onChange={(v) => setTweak('theme', v)} />
      <TweakColor label="Accent" value={t.accent}
        options={['#30D158','#0A84FF','#FF2D55','#FF9F0A','#BF5AF2','#63E6E2','#FFD60A']}
        onChange={(v) => setTweak('accent', v)} />
      <TweakSelect label="Background" value={t.bgStyle}
        options={[{value:'solid',label:'Solid'},{value:'gradient',label:'Gradient wash'},{value:'photo',label:'Photo backdrop'}]}
        onChange={(v) => setTweak('bgStyle', v)} />
      <TweakSelect label="Liquid Glass" value={t.glass}
        options={[{value:'subtle',label:'Subtle'},{value:'moderate',label:'Moderate (default)'},{value:'maximal',label:'Maximal'}]}
        onChange={(v) => setTweak('glass', v)} />
      <TweakColor label="Glass tint" value={t.glassTint}
        options={['#30D158','#0A84FF','#BF5AF2','#FF9F0A','#FF375F','#63E6E2','#FFD60A','#FFFFFF']}
        onChange={(v) => setTweak('glassTint', v)} />
      <TweakSlider label="Tint strength" value={t.glassTintStrength} min={0} max={100} step={5} unit="%"
        onChange={(v) => setTweak('glassTintStrength', v)} />
      <TweakRadio label="Density" value={t.density}
        options={['compact','regular','comfy']}
        onChange={(v) => setTweak('density', v)} />

      <TweakSection label="User" />
      <TweakText label="Name" value={t.userName}
        onChange={(v) => setTweak('userName', v)} />
      <TweakToggle label="Onboarded" value={t.onboarded}
        onChange={(v) => setTweak('onboarded', v)} />
      <TweakToggle label="Signed in" value={t.loggedIn}
        onChange={(v) => setTweak('loggedIn', v)} />

      <TweakSection label="Home cards" />
      <div style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
        {allCards.map(id => (
          <label key={id} style={{
            display: 'flex', alignItems: 'center', gap: 8, padding: '4px 0',
            fontSize: 12, cursor: 'pointer', userSelect: 'none',
          }}>
            <input type="checkbox" checked={t.homeCards.includes(id)} onChange={() => toggleCard(id)}
              style={{ accentColor: t.accent, width: 14, height: 14 }} />
            <span style={{ color: 'rgba(41,38,27,0.85)', fontWeight: 500 }}>{cardLabels[id]}</span>
          </label>
        ))}
      </div>
    </TweaksPanel>
  );
}

// ─────────────────────────────────────────────────────────────
// Root — design canvas with 3 devices + screens showcase
// ─────────────────────────────────────────────────────────────
function Root() {
  return (
    <>
      <DesignCanvas>
        <DCSection id="devices" title="Fitness Guru · iOS 26" subtitle="iPhone 17 · 17 Pro · 17 Pro Max — clickable prototype with shared state.">
          <DCArtboard id="iphone-17" label="iPhone 17" width={390} height={844}>
            <FitnessApp width={390} height={844} initialScreen="home" />
          </DCArtboard>
          <DCArtboard id="iphone-17-pro" label="iPhone 17 Pro" width={402} height={874}>
            <FitnessApp width={402} height={874} initialScreen="chat" />
          </DCArtboard>
          <DCArtboard id="iphone-17-pro-max" label="iPhone 17 Pro Max" width={440} height={956}>
            <FitnessApp width={440} height={956} initialScreen="reminders" />
          </DCArtboard>
        </DCSection>

        <DCSection id="screens" title="All screens" subtitle="Onboarding · Login · Home · Chat · Reminders · Profile · Workout · Calendar">
          <DCArtboard id="s-onboarding" label="Onboarding" width={402} height={874}>
            <FitnessApp width={402} height={874} initialScreen="onboarding" />
          </DCArtboard>
          <DCArtboard id="s-login" label="Login" width={402} height={874}>
            <FitnessApp width={402} height={874} initialScreen="login" />
          </DCArtboard>
          <DCArtboard id="s-home" label="Home · dashboard" width={402} height={874}>
            <FitnessApp width={402} height={874} initialScreen="home" />
          </DCArtboard>
          <DCArtboard id="s-chat" label="Coach · LLM chat" width={402} height={874}>
            <FitnessApp width={402} height={874} initialScreen="chat" />
          </DCArtboard>
          <DCArtboard id="s-reminders" label="Reminders" width={402} height={874}>
            <FitnessApp width={402} height={874} initialScreen="reminders" />
          </DCArtboard>
          <DCArtboard id="s-profile" label="Profile" width={402} height={874}>
            <FitnessApp width={402} height={874} initialScreen="profile" />
          </DCArtboard>
          <DCArtboard id="s-workout" label="Workout detail" width={402} height={874}>
            <FitnessApp width={402} height={874} initialScreen="workout" />
          </DCArtboard>
          <DCArtboard id="s-calendar" label="Calendar" width={402} height={874}>
            <FitnessApp width={402} height={874} initialScreen="calendar" />
          </DCArtboard>
        </DCSection>
      </DesignCanvas>
      <Panel />
    </>
  );
}

ReactDOM.createRoot(document.getElementById('root')).render(<Root />);
