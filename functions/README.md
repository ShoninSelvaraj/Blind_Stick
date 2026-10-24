# Optional Cloud Function reference — not part of the zero-budget deployment

This folder preserves a reference implementation of server-triggered Firebase Cloud Messaging for SOS alerts. **It is intentionally not configured in the root `firebase.json` and is not deployed by the supported zero-billing setup.**

Firebase Spark mode is the project's requirement. Since a trusted sender/server is required to send background FCM notifications and Cloud Functions deployment requires Blaze billing, this reference function is inactive.

## Zero-budget behavior

- SOS alerts are written to Firestore.
- A linked caregiver can see them while their app is open and connected.
- After the alert is saved, the patient can open the device SMS composer and choose a trusted contact. The user must select the recipient and send the message.
- The app does not claim that an automatic background push was sent, that a caregiver has seen an alert, or that emergency services were contacted.

The app's root deployment is restricted to Firestore rules:

```powershell
firebase.cmd deploy --only firestore:rules
```

Do not deploy this function unless the project owner has explicitly chosen and can fund a billing-enabled Firebase/Google Cloud configuration. Even when deployed, push delivery is not guaranteed and must not be the only emergency mechanism.
