const fs = require("node:fs");
const path = require("node:path");
const { after, before, beforeEach, test } = require("node:test");

const {
  assertFails,
  assertSucceeds,
  initializeTestEnvironment
} = require("@firebase/rules-unit-testing");
const {
  deleteDoc,
  doc,
  getDoc,
  setDoc,
  Timestamp,
  updateDoc
} = require("firebase/firestore");

const repositoryRoot = path.resolve(__dirname, "..", "..");
const rulesPath = path.join(repositoryRoot, "Documentation", "firestore.rules");
const firestoreHost = process.env.FIRESTORE_EMULATOR_HOSTNAME || "127.0.0.1";
const firestorePort = Number(process.env.FIRESTORE_EMULATOR_PORT || "8080");
const projectId = process.env.FIREBASE_EMULATOR_PROJECT_ID || "spotter-rules-test";

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId,
    firestore: {
      host: firestoreHost,
      port: firestorePort,
      rules: fs.readFileSync(rulesPath, "utf8")
    }
  });
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

after(async () => {
  await testEnv.cleanup();
});

test("wrong uid cannot read or write another user's profile", async () => {
  const db = testEnv.authenticatedContext("uid-a").firestore();
  const otherProfile = doc(db, "users/uid-b/profile/current");

  await assertFails(getDoc(otherProfile));
  await assertFails(setDoc(otherProfile, profilePayload("uid-b")));
});

test("owner can write profile/current with account ownership", async () => {
  const db = testEnv.authenticatedContext("uid-owner").firestore();

  await assertSucceeds(
    setDoc(doc(db, "users/uid-owner/profile/current"), profilePayload("uid-owner"))
  );
});

test("owner cannot write arbitrary fields to users/{uid}", async () => {
  const db = testEnv.authenticatedContext("uid-root").firestore();

  await assertFails(
    setDoc(doc(db, "users/uid-root"), {
      ...rootUserPayload("uid-root"),
      displayName: "Root profile must stay out of this doc"
    })
  );
});

test("owner can write allowlisted users/{uid} metadata", async () => {
  const db = testEnv.authenticatedContext("uid-root-ok").firestore();

  await assertSucceeds(
    setDoc(doc(db, "users/uid-root-ok"), rootUserPayload("uid-root-ok"))
  );
});

test("raw sensor field names are denied across user subcollections", async () => {
  const uid = "uid-raw-deny";
  const db = testEnv.authenticatedContext(uid).firestore();

  await assertFails(
    setDoc(doc(db, `users/${uid}/profile/current`), {
      ...profilePayload(uid),
      rawVideo: "blocked"
    })
  );
  await assertFails(
    setDoc(doc(db, `users/${uid}/workouts/workout-1`), {
      ...workoutPayload(uid, "workout-1"),
      cameraFrame: "blocked"
    })
  );
  await assertFails(
    setDoc(doc(db, `users/${uid}/workouts/workout-1/sets/set-1`), {
      accountId: uid,
      rawPoseStream: "blocked"
    })
  );
});

test("workout tombstone setData merge is allowed", async () => {
  const uid = "uid-workout-delete";
  const db = testEnv.authenticatedContext(uid).firestore();

  await assertSucceeds(
    setDoc(
      doc(db, `users/${uid}/workouts/workout-delete`),
      {
        accountId: uid,
        schemaVersion: 1,
        workoutId: "workout-delete",
        deletedAt: Timestamp.fromDate(new Date("2026-05-17T00:00:00.000Z")),
        operationId: "delete-operation",
        syncMetadata: pendingSyncMetadata("delete-operation")
      },
      { merge: true }
    )
  );
});

test("normal workout write is allowed", async () => {
  const uid = "uid-workout-normal";
  const db = testEnv.authenticatedContext(uid).firestore();

  await assertSucceeds(
    setDoc(doc(db, `users/${uid}/workouts/workout-normal`), workoutPayload(uid, "workout-normal"))
  );
});

test("trophy events are append-only", async () => {
  const uid = "uid-trophy";
  const db = testEnv.authenticatedContext(uid).firestore();
  const trophyRef = doc(db, `users/${uid}/trophyEvents/event-1`);

  await assertSucceeds(
    setDoc(trophyRef, {
      accountId: uid,
      eventId: "event-1",
      trophyId: "first_saved_workout",
      earnedAt: Timestamp.fromDate(new Date("2026-05-17T00:00:00.000Z"))
    })
  );
  await assertFails(updateDoc(trophyRef, { title: "Changed later" }));
});

test("insights can be created and updated but not deleted", async () => {
  const uid = "uid-insight";
  const db = testEnv.authenticatedContext(uid).firestore();
  const insightRef = doc(db, `users/${uid}/insights/insight-1`);

  await assertSucceeds(
    setDoc(insightRef, {
      accountId: uid,
      dedupeKey: "insight-1",
      headline: "Derived coaching only"
    })
  );
  await assertSucceeds(updateDoc(insightRef, { shortMessage: "Still derived" }));
  await assertFails(deleteDoc(insightRef));
});

function rootUserPayload(uid) {
  const now = Timestamp.fromDate(new Date("2026-05-17T00:00:00.000Z"));
  return {
    accountId: uid,
    schemaVersion: 1,
    createdAt: now,
    updatedAt: now,
    lastSeenAt: now
  };
}

function profilePayload(uid) {
  return {
    accountId: uid,
    updatedAt: Timestamp.fromDate(new Date("2026-05-17T00:00:00.000Z")),
    schemaVersion: 1
  };
}

function workoutPayload(uid, workoutId) {
  return {
    accountId: uid,
    schemaVersion: 1,
    workoutId,
    title: "Rules test workout",
    deletedAt: null
  };
}

function pendingSyncMetadata(operationId) {
  return {
    localUpdatedAt: "2026-05-17T00:00:00.000Z",
    lastSyncedAt: null,
    serverVersion: null,
    syncState: "pendingUpload",
    pendingOperationId: operationId
  };
}
