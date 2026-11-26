# Morning Check

An open-source iPhone and Apple Watch app that shows **where Apple's Sleep Score and how rested you feel agree, and where they don't**.

## Why this exists

[Apple's Sleep Score](https://support.apple.com/en-us/108906) uses estimates of sleep duration, bedtime consistency, and interruptions. It doesn't ask how refreshed you feel when you wake up. A high score and low restedness can both be real observations; they answer different questions.

Morning Check keeps the two numbers separate. Rate your restedness from **1–5 before seeing the score**, then pair it with the **exact 0–100 number Apple displayed** for that morning. The chart shows the relationship across mornings and calls out high-score mornings when you didn't feel rested. The mismatch is worth seeing on its own, not averaging away into another score.

This is a personal comparison, not a claim that the watch is wrong or that either number diagnoses a sleep problem. The app leaves missing values blank, and the results stay on your devices.

## Use it

1. Open **Morning Check** on your Watch or iPhone after waking. Choose how rested you feel before looking at Apple’s score. The Watch saves your response locally and tries to transfer it directly to the paired iPhone. “Received by iPhone” means the phone acknowledged the rating payload; the earliest report of the day is the one shown if you entered both.
2. Open **Health → Sleep → Sleep Score**, and check the wake date. On your iPhone, enter the exact number in Morning Check, or choose **Read screenshot** and select a screenshot of Apple’s English-language detail card. Include the Sleep Score heading, date, and large score and band. Verify both the proposed number and the date. Reading the image does not save anything automatically. The original screenshot stays where you took it; the app does not keep a copy. If the image is unclear, type the number instead. To add a score later, select that wake date under **Compare → Morning history**.
3. **Compare** charts the paired observations, counts missing scores, and shows how often a high Apple score (81–100) coincided with low restedness (1–2). A tie-aware Spearman rank correlation appears when there are at least five pairs and both measures vary. Treat that as descriptive; start by collecting about a month of pairs. Missing data is left missing and scores are never estimated. Titles and views are in English.

## Choose a prompt source on iPhone

Automatic prompts start **off**. Manual check-ins always work.

- **When Watch sleep data arrives:** in Settings, select this mode and allow notifications and sleep read access. The app observes `.sleepAnalysis`, queries recent Apple Watch asleep intervals, merges overlaps and nearby intervals, and schedules at most one prompt per wake date after a recent qualifying session. For this prototype, a session must contain at least three hours of asleep intervals, with an end within the last two hours on the current local day. This helps skip naps and old sync batches, but can miss short nights, detect a long daytime sleep, or fire late. The operating system can defer background delivery; the phone may need to unlock before the app can read the sleep records. No alarm, Sleep Focus, polling, third-party cloud, or overnight workout is required.
- **Apple Sleep Score alert experiment (iOS 27):** select this mode in Morning Check. In Shortcuts, create a shortcut with **Check In from Apple Sleep Alert**, then add a **Notification** automation for the app that actually sends the Sleep Score alert, if selectable. Try it without filters first, then use the actual alert's title or message as a filter before leaving it enabled. If the trigger exposes notification variables, pass its text (include the Sleep Score label and message, if available) and delivery date. Leave the text blank for a prompt-only test. A unique candidate is staged without showing it, then can be confirmed after rating. If the actual Watch alert never triggers Shortcuts, switch to sleep-data mode. Receiving the Watch-only alert in Shortcuts has **not** been verified. This mode does not suppress Apple's own banner; if you see its number first, that day's rating is no longer blind.
- **Routing test:** tap **Test Watch notification routing** and lock your iPhone while keeping your Watch unlocked and on your wrist. A neutral notification is scheduled about 12 seconds later. It never creates a diary entry. Apple decides whether to deliver iPhone-originated local notifications to the phone or the Watch, based on device state and notification settings. This tests notification routing, not wake detection.

## Open the project

Open `MorningCheck.xcodeproj` in Xcode. The iPhone target uses iOS 18+ APIs and the Watch target uses watchOS 11+ APIs; these are deployment targets, not a verified compatibility matrix. The exact Apple Sleep Score feature and the optional Shortcuts notification automation have separate Apple OS requirements.

- For a simulator check, choose scheme **MorningCheck**, an iPhone simulator, then Run or Test. To open the Watch app separately, choose scheme **MorningCheckWatch** and a paired Watch simulator.
- For a real-device trial, select your own Xcode signing team for both targets. If Xcode asks for unique bundle IDs, keep the watch ID prefixed with the phone ID and set the Watch Info `WKCompanionAppBundleIdentifier` to the new phone ID. Enable the phone's HealthKit and HealthKit Background Delivery capabilities. Run on the physical iPhone and open the companion once on its paired Watch. A local install on both devices with a free Personal Team has been verified. [Personal Team profiles expire after seven days](https://developer.apple.com/help/account/basics/about-your-developer-account/). This repository ships source only, not a signed app or a provisioning profile.
- `project.yml` is the reproducible [XcodeGen](https://github.com/yonaskolb/XcodeGen) spec. `xcodegen generate` recreates the Xcode project; reapply local signing changes afterward unless you added them to an unshared local configuration.

## Device validation checklist

1. **Confirm transfer.** On a paired device, record a real rating on your Watch when you intend to log it, with no score visible beforehand. Verify “Received by iPhone” and the same wake date and rating in the phone app. Repeat on another morning with the phone unavailable, then reconnect. Device arrival time must not replace the original rating time.
2. **Confirm timing.** With your chosen mode enabled, check several mornings, including an unscheduled wake. Note whether the prompt arrived before or after Apple’s alert, what device displayed it, whether tapping **Rate** landed on the check-in, and whether duplicates occurred. An alert that only arrived after unlock is not a real-time wake trigger. If the alert experiment does not fire, verify manual score capture before trying sleep-data mode.
3. **Confirm pairing.** Take or select the actual Sleep Score detail card for the same wake date on iPhone, inspect the OCR result, and confirm it only if it matches. Check the comparison view. Use manual entry if the card format or language prevents recognition.

## Privacy and boundaries

- No network client, analytics, account, CloudKit, or iCloud Drive. Apple Watch and iPhone exchange only your rating payload and its receipt using Watch Connectivity. The paired phone holds the comparison. There is no Mac or iPad sync.
- Sleep access is optional and read-only. The transient interval query only signals a prompt; raw HealthKit samples are not persisted. The log lives in the app sandbox under Application Support with backup exclusion and protection until the first device unlock after restart, so transfers can be handled later in the background. To remove it, use **Erase iPhone log** and **Erase Watch log** separately. The iPhone ignores older queued Watch data after its log is erased. The app does not change Apple Health when you erase its log.
- HealthKit exposes predefined data types; a third-party app cannot add a custom numerical Restedness chart to Apple Health. The two numbers appear together in Morning Check, **not** inside Health. No private API or spoofed symptom data is used.
- This is a personal tracking prototype, not a medical tool, a validated diagnostic test, or a claim that Sleep Score should match subjective restedness on any particular morning.

## How the open-source pieces informed the build

- [Pulso’s observer at commit `9676cf7`](https://github.com/lenilsonjr/pulso/blob/9676cf77040205d1b0c8b7308f99a3135a0a2006/Pulso/Sync/TriggerHub.swift) is the reference for reacting to saved HealthKit samples and acknowledging an observer after work. This app swaps the server sync for a local, deduplicated user prompt. No Pulso code is vendored.
- [Sleep Trigger](https://github.com/Padasdaf/Sleep-Trigger) is a public reference for a Watch-to-phone signal. Its live sensor approach uses a workout session; this app does not use that approach, and does not copy its implementation.
- [Apple: HealthKit background delivery](https://developer.apple.com/documentation/healthkit/hkhealthstore/enablebackgrounddelivery(for:frequency:withcompletion:)), [Watch Connectivity transfers](https://developer.apple.com/documentation/watchconnectivity/wcsession/transferuserinfo(_:)), [notification forwarding](https://developer.apple.com/documentation/watchos-apps/taking-advantage-of-notification-forwarding), [Vision text recognition](https://developer.apple.com/documentation/vision/vnrecognizetextrequest), [Shortcuts notifications, WWDC 2026](https://developer.apple.com/videos/play/wwdc2026/310/), [HealthKit data types](https://developer.apple.com/documentation/healthkit/about-the-healthkit-framework), [App Review health data rules](https://developer.apple.com/app-store/review/guidelines/#health-and-health-research).
- The rating anchors are adapted from the expanded [Consensus Sleep Diary](https://pmc.ncbi.nlm.nih.gov/articles/PMC3250369/) (Carney et al., *Sleep*, 2012); this app does not implement the full diary.

## Run the checks

`swift test` runs the core tests. To also run OCR against an actual screen layout, download the [public illustration linked from Apple Support 108906](https://cdsassets.apple.com/live/7WUAS350/images/health/ios-27-iphone-17-pro-health-sleep-sleep-score.png), then pass its local path as `MORNING_CHECK_APPLE_FIXTURE` to `swift test`. The image is not shipped with the source. Run the **MorningCheck** scheme’s UI test on an iPhone simulator to verify the rating-first flow and comparison view; it uses a disposable in-memory store. Watch Connectivity background transfers and HealthKit background delivery are not verified by simulators.

## Contributing

Device and OS versions, steps to reproduce, and redacted logs are helpful in bug reports. Please don't attach Apple Health exports, personal ratings, or screenshots containing health or account data to public issues. For a privacy bug, use GitHub's private vulnerability reporting if available.

Morning Check is [MIT licensed](LICENSE) and is not affiliated with Apple.
