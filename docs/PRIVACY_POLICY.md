<!--
  This document must be hosted at a public URL before App Store submission —
  App Store Connect requires a live Privacy Policy URL, and the App
  Description / LoginView links to it too. Content is mirrored, in plain
  Swift string form, in Services/Legal/LegalTexts.swift
  (LegalTexts.privacyPolicy) — keep both in sync when either changes.
-->

# Privacy Policy

**Fitness Guru**
Last updated: July 17, 2026
Contact: team@atlasjob.tech

Fitness Guru is a personal fitness app built by an independent developer. This policy explains what Fitness Guru reads from your device, what it sends off your device (and why), what it stores, and what it never does.

## What the app reads

- **Apple Health (HealthKit)** — Fitness Guru reads your full Health profile: activity, vitals, body measurements, nutrition, sleep, workouts, mobility, and mindfulness data, plus Medical ID details like date of birth, biological sex, and blood type. This powers your dashboard, on-device predictions, and Astra, the in-app AI coach.

- **Clinical records (optional)** — If you turn on "Health Records" in Settings, Fitness Guru also reads your allergy, condition, medication, lab result, immunization, procedure, and vital sign records from Apple Health Records. This is off by default and only requested if you explicitly enable it. It's used to give Astra clinically relevant context — for example, to flag foods or activities that might conflict with a condition or medication.

- **Calendar and Reminders** — Fitness Guru creates and uses one calendar ("Fitness Guru") and one reminder list ("Fitness Guru") to schedule workouts and nudges. It never reads, edits, or deletes events or reminders in your personal calendars or lists.

- **Camera and Photo Library** — Used only when you choose to take or pick a photo of food or fitness equipment, so Astra can identify it.

- **Microphone** — Used only while you're using sleep tracking, to detect snoring. Audio is analyzed on your device in real time using Apple's Sound Analysis framework; the sound itself is never recorded to a file and never leaves your device. Only a numeric confidence score from the on-device classifier is used by the app.

- **Focus status** — Used to detect when Sleep Focus is on, so the app can align sleep tracking to your bedtime schedule.

## What we send off your device, and why

When you chat with Astra or ask it to identify a food photo, your device sends a request over an encrypted (HTTPS) connection to the **Atlas AI Gateway** — the server that runs the AI model on our behalf. That request can include:

- The Health and profile data relevant to that conversation (for example: today's steps, sleep, heart rate, recent workouts, your training goals, and — only if you've opted in — your clinical record summaries).
- Your recent chat messages in that conversation.
- Any photo you attached.

The Gateway uses this only to generate Astra's reply to that one request. It is **never stored, never logged, and never used to train any AI model**. The Gateway is a stateless pass-through: your health and chat content lives in server memory for only as long as it takes to generate a reply, and then it's discarded.

The only thing kept after each request is lightweight metering metadata: your account ID, how many AI tokens the request used, when it happened, and whether it succeeded. This is used to run the service and enforce fair-use limits — never the content of what you said or your health details.

## Sign in with Apple

Fitness Guru uses Sign in with Apple to create and secure your account. We do not request your name or email address — Apple gives us only a private, anonymous identifier tied to your Apple ID. Your account record on our server stores that identifier, account timestamps, and usage counters (like how many AI tokens you've used). It does not store your name, your email, or any Health data.

## What stays on your device

Your chat history with Astra, your saved preferences and goals, your sleep-tracking summaries, and your streaks and challenges are all stored locally on your device — not on any server. Raw Health samples always remain in Apple Health, governed by Apple's own privacy protections; Fitness Guru only reads processed summaries from it.

## Barcode lookups

If you scan a food barcode, Fitness Guru sends the barcode number to Open Food Facts, a public, non-profit food database, to look up the product. No account information, health data, or personal identifier is included in that request.

## Account deletion

You can delete your account at any time from Settings. This immediately and permanently deletes your account record, sessions, and usage history from our systems, including our record of your Sign in with Apple identifier. (You can additionally remove Fitness Guru from your Apple ID's Sign in with Apple list in iOS Settings.) Deleting the app from your device separately removes everything stored locally — chat history, preferences, and cached summaries. Your Apple Health data is unaffected either way; you manage that directly in the Health app.

## No ads, no tracking, no sale of data

Fitness Guru has no advertising, no third-party analytics SDK, and no tracking code of any kind. We do not sell, rent, or share your data with advertisers or data brokers, and we never use your health data for anything other than generating your AI coach's replies and running the app you're using.

## Not medical advice

Fitness Guru and Astra provide general fitness and wellness information for personal use. They are not a medical device and do not provide medical advice, diagnosis, or treatment, and are not a substitute for professional medical care. Always talk to a qualified healthcare provider about your health, especially before making decisions related to any condition, medication, or symptom Astra discusses with you. If you are experiencing a medical emergency, call your local emergency number immediately.

## Changes to this policy

If this policy changes in a way that affects how your data is handled, we'll update the "Last updated" date above and, for material changes, surface an in-app notice.

## Contact

Questions about this policy or your data? Email [team@atlasjob.tech](mailto:team@atlasjob.tech).
