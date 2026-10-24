# Firebase Cloud Function — DishaFlow SOS push

This function sends a background Firebase Cloud Messaging notification when an authorized patient writes a new `sos` alert to `patients/{patientUid}/alerts/{alertId}`.

## Deploy

From the repository root:

```bash
firebase login
firebase deploy --only firestore:rules,functions
```

The project must have billing enabled as required by Firebase Cloud Functions/Cloud Build. Confirm the target project is `blindstick001` before deploying.

## Behaviour

- Reads the patient record and its explicitly linked `caregiverUids`.
- Loads only those users' `fcmTokens/primary` records.
- Sends an FCM notification with high Android priority.
- Writes an attempt result to the SOS alert document (`sent`, `failed`, `no_linked_caregivers`, or `no_registered_devices`).
- Removes invalid/unregistered tokens.
- Does not trust a recipient or FCM token supplied in the SOS request.

This function does not guarantee delivery or that a person has seen the notification. FCM/APNs delivery, Android notification permissions, phone battery restrictions, network availability, and Firebase deployment configuration still matter. Test notifications on physical devices before emergency use.
