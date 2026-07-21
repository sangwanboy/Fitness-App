import Foundation

/// Static legal copy shown in-app (Settings, LoginView's "Privacy Policy" /
/// "Terms of Service" links, presented via `LegalDocumentSheet`). Also the
/// source of truth mirrored — in Markdown, for hosting at a public URL — at
/// `docs/PRIVACY_POLICY.md` and `docs/TERMS_OF_SERVICE.md`. Keep the three in
/// sync when either changes.
///
/// Rendering note: `LegalDocumentSheet` displays these as plain `Text`, not
/// through a Markdown renderer, so this file deliberately avoids Markdown
/// syntax (`#`, `**`, etc.) in favor of plain caps headers and "•" bullets.
public enum LegalTexts {
    public static let privacyPolicy = """
    PRIVACY POLICY

    Fitness Guru
    Last updated: July 21, 2026
    Contact: team@atlasjob.tech

    Fitness Guru is a personal fitness app built by an independent developer. This policy explains what Fitness Guru reads from your device, what it sends off your device (and why), what it stores, and what it never does.

    WHAT THE APP READS

    • Apple Health (HealthKit) — Fitness Guru reads your full Health profile: activity, vitals, body measurements, nutrition, sleep, workouts, mobility, and mindfulness data, plus Medical ID details like date of birth, biological sex, and blood type. This powers your dashboard, on-device predictions, and Astra, the in-app AI coach.

    • Clinical records (optional) — If you turn on "Health Records" in Settings, Fitness Guru also reads your allergy, condition, medication, lab result, immunization, procedure, and vital sign records from Apple Health Records. This is off by default and only requested if you explicitly enable it. It's used to give Astra clinically relevant context — for example, to flag foods or activities that might conflict with a condition or medication.

    • Calendar and Reminders — Fitness Guru creates and uses one calendar ("Fitness Guru") and one reminder list ("Fitness Guru") to schedule workouts and nudges. It never reads, edits, or deletes events or reminders in your personal calendars or lists.

    • Camera and Photo Library — Used only when you choose to take or pick a photo of food or fitness equipment, so Astra can identify it.

    • Microphone — Used only while you're using sleep tracking, to detect snoring. Audio is analyzed on your device in real time using Apple's Sound Analysis framework; the sound itself is never recorded to a file and never leaves your device. Only a numeric confidence score from the on-device classifier is used by the app.

    • Focus status — Used to detect when Sleep Focus is on, so the app can align sleep tracking to your bedtime schedule.

    WHAT WE SEND OFF YOUR DEVICE, AND WHY

    When you chat with Astra or ask it to identify a food photo, your device sends a request over an encrypted (HTTPS) connection to the Atlas AI Gateway — the server that runs the AI model on our behalf. That request can include:

    • The Health and profile data relevant to that conversation (for example: today's steps, sleep, heart rate, recent workouts, your training goals, and — only if you've opted in — your clinical record summaries).
    • Your recent chat messages in that conversation.
    • Any photo you attached.

    The Gateway uses this only to generate Astra's reply to that one request. It is never stored, never logged, and never used to train any AI model. The Gateway is a stateless pass-through: your health and chat content lives in server memory for only as long as it takes to generate a reply, and then it's discarded.

    The only thing kept after each request is lightweight metering metadata: your account ID, how many AI tokens the request used, when it happened, and whether it succeeded. This is used to run the service and enforce fair-use limits — never the content of what you said or your health details.

    SIGN IN WITH APPLE

    Fitness Guru uses Sign in with Apple to create and secure your account. On your first sign-in, Apple may share your name and email address with us (you can choose to hide your real email behind Apple's private relay instead) — we ask for these so your account has a name and a way to reach you. We separately ask for your explicit opt-in before using either for marketing communications; that choice defaults to off and you can change it any time in Settings. Your account record on our server stores Apple's private identifier for you, your name and email address (only if Apple disclosed them), your marketing-communications choice, lightweight device metadata (locale, app version), account timestamps, and usage counters (like how many AI tokens you've used). It does not store any Health data. We never sell, rent, or share your name or email with advertisers or data brokers, and we only send marketing communications if you've explicitly opted in.

    WHAT STAYS ON YOUR DEVICE

    Your chat history with Astra, your saved preferences and goals, your sleep-tracking summaries, and your streaks and challenges are all stored locally on your device — not on any server. Raw Health samples always remain in Apple Health, governed by Apple's own privacy protections; Fitness Guru only reads processed summaries from it.

    BARCODE LOOKUPS

    If you scan a food barcode, Fitness Guru sends the barcode number to Open Food Facts, a public, non-profit food database, to look up the product. No account information, health data, or personal identifier is included in that request.

    ACCOUNT DELETION

    You can delete your account at any time from Settings. This immediately and permanently deletes your account record, sessions, and usage history from our systems — including any name, email address, and marketing preference we stored, and our record of your Sign in with Apple identifier. (You can additionally remove Fitness Guru from your Apple ID's Sign in with Apple list in iOS Settings.) Deleting the app from your device separately removes everything stored locally — chat history, preferences, and cached summaries. Your Apple Health data is unaffected either way; you manage that directly in the Health app.

    NO ADS, NO TRACKING, NO SALE OF DATA

    Fitness Guru has no advertising, no third-party analytics SDK, and no tracking code of any kind. We do not sell, rent, or share your data with advertisers or data brokers, and we never use your health data for anything other than generating your AI coach's replies and running the app you're using.

    NOT MEDICAL ADVICE

    Fitness Guru and Astra provide general fitness and wellness information for personal use. They are not a medical device and do not provide medical advice, diagnosis, or treatment, and are not a substitute for professional medical care. Always talk to a qualified healthcare provider about your health, especially before making decisions related to any condition, medication, or symptom Astra discusses with you. If you are experiencing a medical emergency, call your local emergency number immediately.

    CHANGES TO THIS POLICY

    If this policy changes in a way that affects how your data is handled, we'll update the "Last updated" date above and, for material changes, surface an in-app notice.

    CONTACT

    Questions about this policy or your data? Email team@atlasjob.tech.
    """

    public static let terms = """
    TERMS OF SERVICE

    Fitness Guru
    Last updated: July 17, 2026
    Contact: team@atlasjob.tech

    These terms govern your use of Fitness Guru (the "app"). By using the app, you agree to them. If you don't agree, please don't use the app.

    THE SERVICE

    Fitness Guru is a personal fitness-information app. It reads data from Apple Health, your calendar and reminders, your camera, and your microphone (on-device only) to power dashboards, on-device predictions, and an AI coach called Astra, which runs on a backend service we call the Atlas AI Gateway.

    NOT MEDICAL ADVICE

    Fitness Guru and Astra are for general fitness and wellness information only. Nothing in the app is medical advice, diagnosis, or treatment, and the app is not a substitute for a qualified healthcare professional. Always consult a doctor or other qualified provider before acting on anything Astra tells you, especially anything related to a medical condition, medication, symptom, or injury. If you are having a medical emergency, call your local emergency number (for example, 911 in the US) immediately — do not rely on this app.

    ACCEPTABLE USE

    You agree to use Fitness Guru only for its intended personal, non-commercial purpose, and not to:

    • attempt to circumvent, reverse-engineer, or overload the Atlas AI Gateway or any other part of the service;
    • use the app to generate content that is illegal, abusive, or intended to harm yourself or others;
    • misrepresent your identity or attempt to access another person's account.

    We reserve the right to suspend or terminate access for use that violates these terms.

    YOUR ACCOUNT

    Your account is created and secured with Sign in with Apple. You're responsible for keeping your device and Apple ID secure. You can delete your account and its server-side data at any time from Settings — see the Privacy Policy for exactly what that removes.

    TERMINATION

    You may stop using the app and delete your account at any time. We may suspend or terminate your access if you violate these terms or misuse the service. Either way, deleting your account removes your server-side account record as described in the Privacy Policy.

    NO WARRANTY; LIMITATION OF LIABILITY

    Fitness Guru is provided "as is," without warranties of any kind, express or implied, including accuracy, fitness for a particular purpose, or uninterrupted availability. AI-generated content, on-device predictions, and estimated nutrition values may be incomplete or wrong — always use your own judgment. To the maximum extent permitted by law, the developer of Fitness Guru is not liable for any indirect, incidental, or consequential damages arising from your use of the app.

    CHANGES

    We may update these terms from time to time; we'll update the "Last updated" date above when we do. Continued use of the app after a change means you accept the updated terms.

    CONTACT

    Questions about these terms? Email team@atlasjob.tech.
    """
}
