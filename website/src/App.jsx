import { useEffect, useState } from 'react';
import {
  motion,
  useReducedMotion,
  useScroll,
  useTransform,
} from 'framer-motion';

/* ---------------------------------- shared ---------------------------------- */

const fadeUp = {
  hidden: { opacity: 0, y: 24 },
  show: (i = 0) => ({
    opacity: 1,
    y: 0,
    transition: { duration: 0.55, delay: i * 0.08, ease: [0.21, 0.65, 0.36, 1] },
  }),
};

function Section({ id, className = '', children }) {
  return (
    <section id={id} className={`px-5 sm:px-8 ${className}`}>
      <div className="mx-auto w-full max-w-6xl">{children}</div>
    </section>
  );
}

function Eyebrow({ children }) {
  return (
    <p className="mb-3 text-xs font-semibold uppercase tracking-[0.18em] text-brand-600">
      {children}
    </p>
  );
}

/* ----------------------------------- hero ----------------------------------- */

function GradientBlobs() {
  const reduce = useReducedMotion();
  const blob =
    'absolute rounded-full blur-3xl opacity-40 will-change-transform pointer-events-none';
  return (
    <div aria-hidden className="absolute inset-0 overflow-hidden">
      <motion.div
        className={`${blob} -top-32 -left-24 h-96 w-96 bg-brand-300`}
        animate={reduce ? {} : { x: [0, 40, 0], y: [0, 24, 0] }}
        transition={{ duration: 18, repeat: Infinity, ease: 'easeInOut' }}
      />
      <motion.div
        className={`${blob} top-24 -right-32 h-[28rem] w-[28rem] bg-sky-200`}
        animate={reduce ? {} : { x: [0, -32, 0], y: [0, 36, 0] }}
        transition={{ duration: 22, repeat: Infinity, ease: 'easeInOut' }}
      />
      <motion.div
        className={`${blob} -bottom-40 left-1/3 h-96 w-96 bg-brand-100`}
        animate={reduce ? {} : { x: [0, 28, 0], y: [0, -28, 0] }}
        transition={{ duration: 26, repeat: Infinity, ease: 'easeInOut' }}
      />
    </div>
  );
}

function Hero() {
  const reduce = useReducedMotion();
  const letters = 'Ayulekha'.split('');
  return (
    <header className="relative isolate overflow-hidden bg-gradient-to-b from-brand-50 via-white to-white">
      <GradientBlobs />
      <Section className="relative pt-24 pb-20 sm:pt-32 sm:pb-28">
        <div className="mx-auto max-w-3xl text-center">
          <motion.p
            initial={{ opacity: 0 }}
            animate={{ opacity: 1 }}
            transition={{ delay: 0.1, duration: 0.6 }}
            className="mb-5 inline-flex items-center gap-2 rounded-full border border-brand-200 bg-white/70 px-4 py-1.5 text-xs font-medium text-brand-700 backdrop-blur"
          >
            <span className="h-1.5 w-1.5 rounded-full bg-brand-500" />
            ABHA-linked · Built for India&rsquo;s clinics
          </motion.p>

          <h1
            aria-label="Ayulekha"
            className="text-5xl font-extrabold tracking-tight text-ink-900 sm:text-7xl"
          >
            {letters.map((ch, i) => (
              <motion.span
                key={i}
                className="inline-block"
                initial={reduce ? false : { opacity: 0, y: 28 }}
                animate={{ opacity: 1, y: 0 }}
                transition={{ delay: 0.15 + i * 0.055, duration: 0.5, ease: 'easeOut' }}
              >
                {ch}
              </motion.span>
            ))}
          </h1>

          <motion.p
            variants={fadeUp}
            initial="hidden"
            animate="show"
            custom={6}
            className="mt-6 text-lg leading-relaxed text-ink-500 sm:text-xl"
          >
            Your health history.{' '}
            <span className="font-semibold text-brand-600">With you, always.</span>
            <br className="hidden sm:block" /> Diagnoses, prescriptions, and lab
            reports that travel with the patient — shared with any doctor only by
            consent.
          </motion.p>

          <motion.div
            variants={fadeUp}
            initial="hidden"
            animate="show"
            custom={8}
            className="mt-9 flex flex-col items-center justify-center gap-3 sm:flex-row"
          >
            <motion.a
              href="#cta"
              whileHover={{ scale: 1.04 }}
              whileTap={{ scale: 0.97 }}
              className="w-full rounded-xl bg-brand-600 px-8 py-3.5 text-center text-base font-semibold text-white shadow-lg shadow-brand-600/25 sm:w-auto"
            >
              Try Ayulekha Free
            </motion.a>
            <a
              href="#how"
              className="w-full rounded-xl border border-slate-200 bg-white px-8 py-3.5 text-center text-base font-semibold text-ink-700 hover:border-brand-300 sm:w-auto"
            >
              See how it works
            </a>
          </motion.div>

        </div>
      </Section>
    </header>
  );
}

/* --------------------------------- problem ---------------------------------- */

function Problem() {
  const pains = [
    {
      who: 'Patients',
      pain: 'Re-tell their history at every new doctor. Carry paper reports and old X-rays to every appointment — and still forget which medicine was prescribed, at what dose.',
      icon: '🧾',
    },
    {
      who: 'Doctors',
      pain: 'No way to see what other providers already found. No follow-up tracking, no view of who’s waiting outside — time lost on every new patient.',
      icon: '🩺',
    },
    {
      who: 'Diagnostic labs',
      pain: 'Referrals arrive on slips of paper; results go back the same way. Reports get lost, delayed, or never reach the ordering doctor at all.',
      icon: '🔬',
    },
  ];
  return (
    <Section className="py-20 sm:py-24">
      <motion.div
        initial="hidden"
        whileInView="show"
        viewport={{ once: true, amount: 0.3 }}
        className="mx-auto max-w-2xl text-center"
      >
        <motion.div variants={fadeUp}>
          <Eyebrow>The problem</Eyebrow>
          <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">
            Indian healthcare runs on paper —{' '}
            <span className="text-brand-600">and paper gets lost.</span>
          </h2>
        </motion.div>
      </motion.div>
      <div className="mt-12 grid gap-5 sm:grid-cols-3">
        {pains.map((p, i) => (
          <motion.div
            key={p.who}
            variants={fadeUp}
            custom={i}
            initial="hidden"
            whileInView="show"
            viewport={{ once: true, amount: 0.3 }}
            className="rounded-2xl border border-slate-100 bg-slate-50/60 p-6"
          >
            <div className="text-2xl">{p.icon}</div>
            <h3 className="mt-3 font-semibold text-ink-900">{p.who}</h3>
            <p className="mt-2 text-sm leading-relaxed text-ink-500">{p.pain}</p>
          </motion.div>
        ))}
      </div>
    </Section>
  );
}

/* --------------------------------- features --------------------------------- */

const FEATURES = [
  {
    icon: (
      <IconWrap>
        <path d="M12 3l7 4v5c0 4.4-3 8.4-7 9-4-.6-7-4.6-7-9V7l7-4z" />
        <path d="M9 12l2 2 4-4" />
      </IconWrap>
    ),
    title: 'Patient-owned, consent-first',
    body: 'Records belong to the patient, linked to their ABHA ID. A doctor sees them only after the patient shares a code or approves a request — and access can be revoked with one tap.',
  },
  {
    icon: (
      <IconWrap>
        <path d="M4 6h16M4 12h16M4 18h10" />
        <circle cx="19" cy="18" r="2.4" />
      </IconWrap>
    ),
    title: 'One-touch AI summary',
    body: 'Years of visits condensed into one plain paragraph before the patient sits down — built only from structured records, never a diagnosis, always labelled and verifiable.',
  },
  {
    icon: (
      <IconWrap>
        <path d="M9 3h6v4H9zM7 7h10v14H7z" />
        <path d="M10 12h4M10 16h4" />
      </IconWrap>
    ),
    title: 'Digital diagnostics, end to end',
    body: 'Order a test in-app; the lab scans the patient’s order code and uploads results straight into the record. No paper reports, no lost films, no courier delays.',
  },
  {
    icon: (
      <IconWrap>
        <circle cx="12" cy="12" r="9" />
        <path d="M12 7v5l3 3" />
      </IconWrap>
    ),
    title: 'Live queue & token tracker',
    body: 'Patients see their token position in real time; front desk checks people in with a tap. Doctors call the next patient without shouting down a corridor.',
  },
  {
    icon: (
      <IconWrap>
        <path d="M8 3v4M16 3v4M4 9h16M5 5h14v15H5z" />
        <path d="M9 14l2 2 4-4" />
      </IconWrap>
    ),
    title: 'Follow-ups that actually happen',
    body: 'Every visit can carry a follow-up date. Ayulekha tracks who’s due, who’s overdue, and sends the reminder — recovering revenue lost to no-shows.',
  },
  {
    icon: (
      <IconWrap>
        <path d="M12 4v10M12 4l-3 3M12 4l3 3" transform="rotate(180 12 9)" />
        <rect x="5" y="14" width="14" height="6" rx="2" />
      </IconWrap>
    ),
    title: 'Prescriptions in seconds',
    body: 'Voice input parsed into structured doses, drug autocomplete, reusable templates — reviewed by the doctor before saving, every time.',
  },
];

function IconWrap({ children }) {
  return (
    <svg
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      strokeWidth="1.8"
      strokeLinecap="round"
      strokeLinejoin="round"
      className="h-6 w-6"
    >
      {children}
    </svg>
  );
}

function Features() {
  return (
    <Section id="how" className="bg-gradient-to-b from-white to-brand-50/50 py-20 sm:py-24">
      <motion.div
        initial="hidden"
        whileInView="show"
        viewport={{ once: true, amount: 0.3 }}
        className="mx-auto max-w-2xl text-center"
      >
        <motion.div variants={fadeUp}>
          <Eyebrow>What Ayulekha does</Eyebrow>
          <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">
            One record. Three sides of care, connected.
          </h2>
          <p className="mt-4 text-ink-500">
            Patients, doctors, and diagnostic labs on a single platform — each seeing
            exactly what they&rsquo;re permitted to, nothing more.
          </p>
        </motion.div>
      </motion.div>

      <div className="mt-14 grid gap-5 sm:grid-cols-2 lg:grid-cols-3">
        {FEATURES.map((f, i) => (
          <motion.div
            key={f.title}
            variants={fadeUp}
            custom={i % 3}
            initial="hidden"
            whileInView="show"
            viewport={{ once: true, amount: 0.25 }}
            whileHover={{ y: -4 }}
            className="rounded-2xl border border-slate-100 bg-white p-6 shadow-sm shadow-slate-100"
          >
            <motion.div
              initial={{ scale: 0.6, opacity: 0 }}
              whileInView={{ scale: 1, opacity: 1 }}
              viewport={{ once: true }}
              transition={{ type: 'spring', stiffness: 260, damping: 18, delay: 0.15 }}
              className="inline-flex rounded-xl bg-brand-50 p-3 text-brand-600"
            >
              {f.icon}
            </motion.div>
            <h3 className="mt-4 font-semibold text-ink-900">{f.title}</h3>
            <p className="mt-2 text-sm leading-relaxed text-ink-500">{f.body}</p>
          </motion.div>
        ))}
      </div>
    </Section>
  );
}

/* ------------------------------- chat mockup --------------------------------- */

const TIMELINE = [
  {
    icon: '🔔',
    tag: 'Access request',
    text: 'Dr. Priya (Sunrise Clinic) has requested access to your health record.',
    action: 'Approve · Deny',
  },
  {
    icon: '✅',
    tag: 'Access granted by you',
    text: 'Dr. Priya can now view your history. Revoke anytime from "Doctors with access".',
    accent: true,
  },
  {
    icon: '✨',
    tag: 'AI summary — verify against full record',
    text: '4 visits over 14 months for recurring migraine. On Propranolol 40mg since March. Follow-up advised, completed.',
  },
  {
    icon: '🧪',
    tag: 'Test ordered',
    text: 'CBC panel. Show code T-4F2K at any partner lab — no paper referral needed.',
  },
  {
    icon: '📄',
    tag: 'Report ready',
    text: 'City Diagnostics uploaded your report. View it in your Tests tab.',
    action: 'Open report',
  },
];

function ChatDemo() {
  const [visible, setVisible] = useState(0);
  const [started, setStarted] = useState(false);
  const reduce = useReducedMotion();

  useEffect(() => {
    if (!started) return;
    if (reduce) {
      setVisible(TIMELINE.length);
      return;
    }
    if (visible >= TIMELINE.length) return;
    const t = setTimeout(() => setVisible((v) => v + 1), visible === 0 ? 300 : 1400);
    return () => clearTimeout(t);
  }, [started, visible, reduce]);

  return (
    <Section className="py-20 sm:py-24">
      <div className="grid items-center gap-12 lg:grid-cols-2">
        <motion.div
          variants={fadeUp}
          initial="hidden"
          whileInView="show"
          viewport={{ once: true, amount: 0.4 }}
        >
          <Eyebrow>See it in action</Eyebrow>
          <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">
            From &ldquo;who are you?&rdquo; to fully informed —{' '}
            <span className="text-brand-600">in one visit.</span>
          </h2>
          <p className="mt-4 leading-relaxed text-ink-500">
            A new patient walks in. The doctor requests access, the patient approves on
            their phone, and the AI summary appears — years of history in a paragraph.
            Tests ordered in-app come back as digital reports, straight into the same
            record.
          </p>
          <ul className="mt-6 space-y-2 text-sm text-ink-700">
            {['Patient approves or revokes access anytime', 'Every view is logged — patients see who looked', 'Labs see only the ordered test, never the full history'].map(
              (t) => (
                <li key={t} className="flex items-start gap-2">
                  <span className="mt-0.5 text-brand-500">✓</span> {t}
                </li>
              ),
            )}
          </ul>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, y: 30 }}
          whileInView={{ opacity: 1, y: 0 }}
          viewport={{ once: true, amount: 0.35 }}
          onViewportEnter={() => setStarted(true)}
          transition={{ duration: 0.6 }}
          className="mx-auto w-full max-w-sm"
        >
          <div className="rounded-[2rem] border border-slate-200 bg-slate-50 p-3 shadow-xl shadow-slate-200/60">
            <div className="rounded-[1.6rem] bg-white px-3 pb-4 pt-3">
              <div className="mb-3 flex items-center justify-between rounded-xl bg-brand-50 px-3 py-2">
                <div className="flex items-center gap-2">
                  <div className="flex h-8 w-8 items-center justify-center rounded-full bg-brand-600 text-xs font-bold text-white">
                    A
                  </div>
                  <div>
                    <p className="text-sm font-semibold leading-tight">Ayulekha</p>
                    <p className="text-[11px] text-ink-500">Your record · activity</p>
                  </div>
                </div>
                <span className="rounded-full bg-white px-2 py-0.5 text-[10px] font-semibold text-brand-700">
                  🔒 Consent-gated
                </span>
              </div>
              <div className="flex min-h-[340px] flex-col justify-end gap-2">
                {TIMELINE.slice(0, visible).map((m, i) => (
                  <motion.div
                    key={i}
                    initial={reduce ? false : { opacity: 0, y: 12, scale: 0.97 }}
                    animate={{ opacity: 1, y: 0, scale: 1 }}
                    transition={{ duration: 0.35, ease: 'easeOut' }}
                    className={`flex items-start gap-2.5 rounded-xl border px-3 py-2.5 text-[13px] leading-snug shadow-sm ${
                      m.accent
                        ? 'border-brand-200 bg-brand-50'
                        : 'border-slate-100 bg-white'
                    }`}
                  >
                    <span className="mt-0.5 text-base">{m.icon}</span>
                    <div className="min-w-0">
                      <p className="mb-0.5 text-[10px] font-semibold uppercase tracking-wide text-brand-600">
                        {m.tag}
                      </p>
                      <p className="text-ink-900">{m.text}</p>
                      {m.action && (
                        <p className="mt-1 text-[11px] font-semibold text-brand-600">
                          {m.action}
                        </p>
                      )}
                    </div>
                  </motion.div>
                ))}
                {started && visible < TIMELINE.length && (
                  <motion.div
                    className="flex items-center gap-1 self-start rounded-xl border border-slate-100 bg-white px-4 py-3 shadow-sm"
                    initial={{ opacity: 0 }}
                    animate={{ opacity: 1 }}
                  >
                    {[0, 1, 2].map((d) => (
                      <motion.span
                        key={d}
                        className="h-1.5 w-1.5 rounded-full bg-slate-400"
                        animate={reduce ? {} : { y: [0, -3, 0] }}
                        transition={{ duration: 0.6, repeat: Infinity, delay: d * 0.15 }}
                      />
                    ))}
                  </motion.div>
                )}
              </div>
            </div>
          </div>
        </motion.div>
      </div>
    </Section>
  );
}

/* ------------------------------- testimonials -------------------------------- */

function Testimonials() {
  const quotes = [
    {
      quote:
        'A new patient’s full history in one paragraph before they sit down. That used to take ten minutes of questions.',
      name: 'Dr. A—',
      role: 'General physician, solo clinic (pilot)',
    },
    {
      quote:
        'I stopped carrying a plastic bag of old reports to every appointment. Everything is just… there.',
      name: 'R—',
      role: 'Patient, sees 3 specialists',
    },
    {
      quote:
        'Orders come with a code, reports go back digitally. No more couriering envelopes to five different clinics.',
      name: 'P—',
      role: 'Manager, standalone diagnostic lab (pilot)',
    },
  ];
  return (
    <Section className="bg-ink-900 py-20 text-white sm:py-24">
      <motion.div
        variants={fadeUp}
        initial="hidden"
        whileInView="show"
        viewport={{ once: true, amount: 0.3 }}
        className="mx-auto max-w-2xl text-center"
      >
        <p className="mb-3 text-xs font-semibold uppercase tracking-[0.18em] text-brand-300">
          Early voices
        </p>
        <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">
          Built with clinics, not just for them.
        </h2>
        <p className="mt-3 text-sm text-slate-400">
          Pilot feedback — named testimonials coming as we onboard our first clinics.
        </p>
      </motion.div>
      <div className="mt-12 grid gap-5 sm:grid-cols-3">
        {quotes.map((q, i) => (
          <motion.figure
            key={i}
            variants={fadeUp}
            custom={i}
            initial="hidden"
            whileInView="show"
            viewport={{ once: true, amount: 0.3 }}
            className="rounded-2xl bg-white/5 p-6 ring-1 ring-white/10"
          >
            <blockquote className="text-sm leading-relaxed text-slate-200">
              &ldquo;{q.quote}&rdquo;
            </blockquote>
            <figcaption className="mt-4 text-xs text-slate-400">
              <span className="font-semibold text-white">{q.name}</span> · {q.role}
            </figcaption>
          </motion.figure>
        ))}
      </div>
    </Section>
  );
}

/* --------------------------------- pricing ----------------------------------- */

function Pricing() {
  const tiers = [
    {
      name: 'Free',
      price: '₹0',
      cadence: 'forever',
      blurb: 'Everything a clinic needs to go paperless.',
      features: [
        'Patient records & visit history',
        'Appointment booking',
        'Prescriptions & visit notes',
        'Digital test ordering',
        'Consent-based record sharing',
      ],
      cta: 'Start free',
      highlight: false,
    },
    {
      name: 'Ayulekha Pro',
      price: 'Launch pricing',
      cadence: 'per clinic — announced soon',
      blurb: 'The efficiency toolkit that pays for itself.',
      features: [
        'One-touch AI patient summary',
        'Live queue & token tracker',
        'Follow-up tracking & reminders',
        'Automated no-show reminders',
        'Voice prescriptions & templates',
      ],
      cta: 'Join the waitlist',
      highlight: true,
    },
  ];
  return (
    <Section id="pricing" className="py-20 sm:py-24">
      <motion.div
        variants={fadeUp}
        initial="hidden"
        whileInView="show"
        viewport={{ once: true, amount: 0.3 }}
        className="mx-auto max-w-2xl text-center"
      >
        <Eyebrow>Pricing</Eyebrow>
        <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">
          One simple plan. No per-module maze.
        </h2>
        <p className="mt-4 text-ink-500">
          Patients and diagnostic labs never pay. Clinics get everything essential free,
          and one flat Pro plan for the tools that save doctor-hours.
        </p>
      </motion.div>
      <div className="mx-auto mt-12 grid max-w-3xl gap-6 sm:grid-cols-2">
        {tiers.map((t, i) => (
          <motion.div
            key={t.name}
            variants={fadeUp}
            custom={i}
            initial="hidden"
            whileInView="show"
            viewport={{ once: true, amount: 0.3 }}
            className={`relative rounded-2xl p-7 ${
              t.highlight
                ? 'bg-gradient-to-b from-brand-600 to-brand-700 text-white shadow-xl shadow-brand-600/25'
                : 'border border-slate-200 bg-white'
            }`}
          >
            {t.highlight && (
              <span className="absolute -top-3 right-6 rounded-full bg-ink-900 px-3 py-1 text-[11px] font-semibold text-white">
                For growing clinics
              </span>
            )}
            <h3 className="text-lg font-semibold">{t.name}</h3>
            <p className={`mt-1 text-sm ${t.highlight ? 'text-brand-100' : 'text-ink-500'}`}>
              {t.blurb}
            </p>
            <p className="mt-5 text-3xl font-extrabold tracking-tight">{t.price}</p>
            <p className={`text-xs ${t.highlight ? 'text-brand-100' : 'text-ink-500'}`}>
              {t.cadence}
            </p>
            <ul className="mt-6 space-y-2.5 text-sm">
              {t.features.map((f) => (
                <li key={f} className="flex items-start gap-2">
                  <span className={t.highlight ? 'text-brand-200' : 'text-brand-500'}>✓</span>
                  {f}
                </li>
              ))}
            </ul>
            <motion.a
              href="#cta"
              whileHover={{ scale: 1.03 }}
              whileTap={{ scale: 0.97 }}
              className={`mt-7 block rounded-xl px-5 py-3 text-center text-sm font-semibold ${
                t.highlight
                  ? 'bg-white text-brand-700'
                  : 'bg-brand-600 text-white shadow-md shadow-brand-600/20'
              }`}
            >
              {t.cta}
            </motion.a>
          </motion.div>
        ))}
      </div>
    </Section>
  );
}

/* ----------------------------------- cta ------------------------------------- */

function Cta() {
  return (
    <Section id="cta" className="pb-20 sm:pb-24">
      <motion.div
        initial={{ opacity: 0, scale: 0.97 }}
        whileInView={{ opacity: 1, scale: 1 }}
        viewport={{ once: true, amount: 0.5 }}
        transition={{ duration: 0.6 }}
        className="relative overflow-hidden rounded-3xl bg-gradient-to-br from-brand-600 via-brand-700 to-ink-900 px-6 py-16 text-center text-white sm:px-16"
      >
        <div
          aria-hidden
          className="absolute -top-24 left-1/2 h-64 w-[36rem] -translate-x-1/2 rounded-full bg-brand-400/30 blur-3xl"
        />
        <h2 className="relative text-3xl font-bold tracking-tight sm:text-4xl">
          Give your patients a record that follows them.
        </h2>
        <p className="relative mx-auto mt-4 max-w-xl text-brand-100">
          Set up your clinic in minutes — hospital name, mobile number, done. Your first
          doctor profile is live before the next patient walks in.
        </p>
        <motion.a
          href="mailto:founder@ayulekha.in?subject=Ayulekha%20early%20access"
          whileHover={{ scale: 1.05 }}
          whileTap={{ scale: 0.96 }}
          className="relative mt-8 inline-block rounded-xl bg-white px-9 py-4 text-base font-bold text-brand-700 shadow-2xl"
        >
          Try Ayulekha Free
        </motion.a>
        <p className="relative mt-4 text-xs text-brand-200">
          Early access · founder@ayulekha.in
        </p>
      </motion.div>
    </Section>
  );
}

/* ---------------------------------- footer ----------------------------------- */

function Footer() {
  return (
    <footer className="border-t border-slate-100 px-5 py-10 sm:px-8">
      <div className="mx-auto flex max-w-6xl flex-col items-center justify-between gap-4 sm:flex-row">
        <div>
          <p className="text-lg font-extrabold tracking-tight text-ink-900">
            Ayu<span className="text-brand-600">lekha</span>
          </p>
          <p className="mt-1 text-xs text-ink-500">
            Your health history. With you, always.
          </p>
        </div>
        <p className="text-xs text-ink-500">
          © {new Date().getFullYear()} Ayulekha · ayulekha.in ·{' '}
          <a href="mailto:founder@ayulekha.in" className="text-brand-600 hover:underline">
            founder@ayulekha.in
          </a>
        </p>
      </div>
    </footer>
  );
}

/* ----------------------------------- nav ------------------------------------- */

function Nav() {
  const { scrollY } = useScroll();
  const bg = useTransform(scrollY, [0, 80], ['rgba(255,255,255,0)', 'rgba(255,255,255,0.9)']);
  const shadow = useTransform(scrollY, [0, 80], ['0 0 0 rgba(0,0,0,0)', '0 1px 12px rgba(12,36,49,0.08)']);
  return (
    <motion.nav
      style={{ backgroundColor: bg, boxShadow: shadow }}
      className="fixed inset-x-0 top-0 z-50 backdrop-blur-sm"
    >
      <div className="mx-auto flex max-w-6xl items-center justify-between px-5 py-3.5 sm:px-8">
        <a href="#" className="text-lg font-extrabold tracking-tight text-ink-900">
          Ayu<span className="text-brand-600">lekha</span>
        </a>
        <div className="flex items-center gap-5 text-sm font-medium text-ink-700">
          <a href="#how" className="hidden hover:text-brand-600 sm:block">
            Features
          </a>
          <a href="#pricing" className="hidden hover:text-brand-600 sm:block">
            Pricing
          </a>
          <motion.a
            href="#cta"
            whileHover={{ scale: 1.05 }}
            whileTap={{ scale: 0.95 }}
            className="rounded-lg bg-brand-600 px-4 py-2 text-sm font-semibold text-white"
          >
            Try free
          </motion.a>
        </div>
      </div>
    </motion.nav>
  );
}

/* ----------------------------------- app ------------------------------------- */

export default function App() {
  return (
    <main className="font-sans">
      <Nav />
      <Hero />
      <Problem />
      <Features />
      <ChatDemo />
      <Testimonials />
      <Pricing />
      <Cta />
      <Footer />
    </main>
  );
}
