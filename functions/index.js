const { onDocumentCreated } = require("firebase-functions/v2/firestore");
const logger = require("firebase-functions/logger");
const admin = require("firebase-admin");

admin.initializeApp();
const db = admin.firestore();

/**
 * Deliver background SOS notifications only to the caregivers that the patient
 * explicitly paired. The client never supplies a destination token or recipient.
 *
 * Deployment may require the Firebase/Google Cloud Blaze billing plan.
 */
exports.notifyLinkedCaregiversOfSos = onDocumentCreated(
  {
    document: "patients/{patientUid}/alerts/{alertId}",
    region: "asia-south1",
  },
  async (event) => {
    const alert = event.data?.data();
    if (!alert || alert.type !== "sos") return;

    const patientUid = event.params.patientUid;
    const patientSnap = await db.collection("patients").doc(patientUid).get();
    if (!patientSnap.exists) {
      logger.warn("SOS has no patient record", { patientUid, alertId: event.params.alertId });
      await event.data.ref.update({
        deliveryStatus: "failed_no_patient",
        deliveryAttemptedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      return;
    }

    const caregiverUids = Array.isArray(patientSnap.data().caregiverUids)
      ? [...new Set(patientSnap.data().caregiverUids)]
      : [];

    if (caregiverUids.length === 0) {
      await event.data.ref.update({
        deliveryStatus: "no_linked_caregivers",
        deliveryAttemptedAt: admin.firestore.FieldValue.serverTimestamp(),
        deliverySuccessCount: 0,
      });
      logger.info("SOS saved but there are no linked caregivers", { patientUid, alertId: event.params.alertId });
      return;
    }

    const tokenDocs = await Promise.all(caregiverUids.map(async (uid) => ({
      uid,
      ref: db.collection("users").doc(uid).collection("fcmTokens").doc("primary"),
      snap: await db.collection("users").doc(uid).collection("fcmTokens").doc("primary").get(),
    })));

    const recipients = tokenDocs
      .filter((item) => item.snap.exists && typeof item.snap.data().token === "string")
      .map((item) => ({ uid: item.uid, token: item.snap.data().token, ref: item.ref }));

    if (recipients.length === 0) {
      await event.data.ref.update({
        deliveryStatus: "no_registered_devices",
        deliveryAttemptedAt: admin.firestore.FieldValue.serverTimestamp(),
        deliverySuccessCount: 0,
      });
      return;
    }

    const title = "BlindStick Companion emergency alert";
    const body = typeof alert.message === "string" && alert.message.length > 0
      ? alert.message.slice(0, 180)
      : "Someone using BlindStick Companion requested help.";

    const result = await admin.messaging().sendEachForMulticast({
      tokens: recipients.map((item) => item.token),
      notification: { title, body },
      data: {
        type: "sos",
        patientUid,
        alertId: event.params.alertId,
      },
      android: {
        priority: "high",
        notification: {
          channelId: "blindstick_companion_emergency_alerts",
          sound: "default",
          priority: "max",
        },
      },
    });

    const invalidTokenCodes = new Set([
      "messaging/invalid-registration-token",
      "messaging/registration-token-not-registered",
    ]);
    const cleanup = [];
    result.responses.forEach((response, index) => {
      if (!response.success && invalidTokenCodes.has(response.error?.code)) {
        cleanup.push(recipients[index].ref.delete());
      }
    });
    await Promise.allSettled(cleanup);

    await event.data.ref.update({
      deliveryStatus: result.successCount > 0 ? "sent" : "failed",
      deliveryAttemptedAt: admin.firestore.FieldValue.serverTimestamp(),
      deliverySuccessCount: result.successCount,
      deliveryFailureCount: result.failureCount,
    });

    logger.info("SOS push delivery attempted", {
      patientUid,
      alertId: event.params.alertId,
      successCount: result.successCount,
      failureCount: result.failureCount,
    });
  }
);
