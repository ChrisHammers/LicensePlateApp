/**
 * F-21 slice 3: the owner-approved copy deck's `notice.*` English, verbatim (generated
 * from the deck JSON, not retyped). The restatement tests compare rendered notices with
 * these literals so a paraphrase in `consentNoticeStrings.ts` fails loudly.
 */
export const NOTICE_DECK = {
  "notice.request.scopes_heading":
    "What you are agreeing to",
  "notice.request.scope_core.join":
    "Family play: required to join a family. We save your child's nickname, cartoon avatar, game activity (plates found, scores, ranks, achievements, and the trips they join), the month and year they turn 13, and an account ID the app creates, plus a notification token if notifications are on, basic device details, and crash reports. Members of your family see the nickname, avatar, and scores, and people on a trip with your child (always family) see that trip. Notifications are about your family, your trips, and play reminders, never ads.",
  "notice.request.scope_core.member_flag":
    "Family play: required to stay in the family. We save this player's nickname, cartoon avatar, game activity (plates found, scores, ranks, achievements, and the trips they join), the month and year they turn 13, and an account ID the app creates, plus a notification token if notifications are on, basic device details, and crash reports. Members of your family see the nickname, avatar, and scores, and people on a trip with them (always family) see that trip. Notifications are about your family, your trips, and play reminders, never ads.",
  "notice.scopes_unavailable":
    "Not available yet (off for every child, nothing collected): usage analytics, ads made for kids, location shared with family, and being seen by other families. If we ever offer one of these, a parent or guardian who is a captain of your family will be asked first.",
  "notice.interstitial.scopes_heading":
    "By confirming, you agree to:",
  "notice.interstitial.scope_core":
    "Family play: your child's nickname, cartoon avatar, game activity, the month and year they turn 13, an account ID, basic device details, crash reports, and a notification token if notifications are on are saved and shared with your family. Notifications are about your family, your trips, and play reminders, never ads. This is required for your child to play in your family.",
  "notice.plus.scopes_heading":
    "What you agreed to",
  "notice.plus.scope_core.join":
    "Family play (required to join a family): we save this player's nickname, cartoon avatar, game activity, the month and year they turn 13, and an account ID, plus a notification token if notifications are on, basic device details, and crash reports. Members of your family see the nickname, avatar, and scores, and people on a trip with them see that trip. Notifications are about your family, your trips, and play reminders.",
  "notice.plus.scope_core.member_flag":
    "Family play (required to stay in the family): we save this player's nickname, cartoon avatar, game activity, the month and year they turn 13, and an account ID, plus a notification token if notifications are on, basic device details, and crash reports. Members of your family see the nickname, avatar, and scores, and people on a trip with them see that trip. Notifications are about your family, your trips, and play reminders.",
  "notice.plus.scopes_unavailable":
    "Nothing else is turned on: usage analytics, ads made for kids, location shared with family, and being seen by other families are not available and are off.",
  "notice.confirmed.title":
    "Consent confirmed",
  "notice.confirmed.body.join":
    "Thank you. The player's account is now active in your family. You agreed to Family play: their nickname, cartoon avatar, and game activity are saved and shown to your family, and notifications are about your family, your trips, and play reminders. Nothing else is turned on: usage analytics, ads made for kids, location shared with family, and being seen by other families are not available. You can review this, or withdraw consent, at any time from Family settings in the RoadTrip Royale app.",
  "notice.confirmed.body.member_flag":
    "Thank you. Their account stays active in your family. You agreed to Family play: their nickname, cartoon avatar, and game activity are saved and shown to your family, and notifications are about your family, your trips, and play reminders. Nothing else is turned on: usage analytics, ads made for kids, location shared with family, and being seen by other families are not available. You can review this, or withdraw consent, at any time from Family settings in the RoadTrip Royale app.",
  "notice.failure.scope_selection_invalid.title":
    "This link can't be completed",
  "notice.failure.scope_selection_invalid.body":
    "What this link asked you to agree to has changed, so it can't go through, and trying again won't help. Open RoadTrip Royale and approve the request again; you'll get a fresh email.",
  "notice.reject.consent_text_outdated":
    "This version of RoadTrip Royale can't approve a child. Update the app to the latest version and try again.",
  "notice.reject.consent_scopes_invalid":
    "This version of RoadTrip Royale can't approve a child. Update the app to the latest version and try again.",
} as const;
