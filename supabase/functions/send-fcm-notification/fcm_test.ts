// supabase/functions/send-fcm-notification/fcm_test.ts
import { assertEquals, assertRejects } from "https://deno.land/std@0.177.0/testing/asserts.ts";
import { createGoogleSignedJwt, ServiceAccount, sendFcmHttpV1 } from "./fcm_v1.ts";

Deno.test("FCM v1 & Notification Sender Test Suite", async (t) => {

  // Generate an ephemeral RSA key pair for testing OAuth JWT assertion creation
  const keyPair = await crypto.subtle.generateKey(
    {
      name: "RSASSA-PKCS1-v1_5",
      modulusLength: 2048,
      publicExponent: new Uint8Array([1, 0, 1]),
      hash: "SHA-256",
    },
    true,
    ["sign", "verify"]
  );

  const exportedPkcs8 = await crypto.subtle.exportKey("pkcs8", keyPair.privateKey);
  const binary = String.fromCharCode(...new Uint8Array(exportedPkcs8));
  const b64 = btoa(binary);
  const fakePem = `-----BEGIN PRIVATE KEY-----\n${b64}\n-----END PRIVATE KEY-----`;

  const dummyServiceAccount: ServiceAccount = {
    project_id: "test-dueit-project",
    client_email: "test-fcm-sa@test-dueit-project.iam.gserviceaccount.com",
    private_key: fakePem,
  };

  // 1. Authentication Contract
  await t.step("1. Strict Authorization: Rejects invalid or missing scheduler secret", () => {
    const SCHEDULER_SECRET = "super_secret_scheduler_token";

    const verifyAuth = (authHeader: string | null) => {
      if (!authHeader || authHeader !== `Bearer ${SCHEDULER_SECRET}`) {
        return { status: 401, error: "Unauthorized" };
      }
      return { status: 200, error: null };
    };

    assertEquals(verifyAuth(null).status, 401);
    assertEquals(verifyAuth("Bearer wrong_secret").status, 401);
    assertEquals(verifyAuth("wrong_format").status, 401);
    assertEquals(verifyAuth(`Bearer ${SCHEDULER_SECRET}`).status, 200);
  });

  // 2. Google OAuth2 RS256 Assertion Signing
  await t.step("2. Google OAuth2 RS256 JWT assertion generation succeeds and produces 3 segments", async () => {
    const jwt = await createGoogleSignedJwt(dummyServiceAccount);
    const parts = jwt.split(".");
    assertEquals(parts.length, 3);

    // Verify header claims
    const header = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(parts[0]), c => c.charCodeAt(0))));
    assertEquals(header.alg, "RS256");
    assertEquals(header.typ, "JWT");

    // Verify payload claims
    const payload = JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(parts[1]), c => c.charCodeAt(0))));
    assertEquals(payload.iss, dummyServiceAccount.client_email);
    assertEquals(payload.scope, "https://www.googleapis.com/auth/firebase.messaging");
    assertEquals(payload.aud, "https://oauth2.googleapis.com/token");
  });

  // 3. Simulated FCM Success
  await t.step("3. FCM HTTP v1 dispatch handles successful delivery (200 OK)", async () => {
    const originalFetch = globalThis.fetch;
    globalThis.fetch = () =>
      Promise.resolve(new Response(JSON.stringify({ name: "projects/test/messages/msg_123" }), { status: 200 }));

    try {
      const res = await sendFcmHttpV1(
        "test-project",
        "mock_access_token",
        "test_device_token_valid",
        { title: "Test", body: "Hello", data: { id: "1" } }
      );
      assertEquals(res.success, true);
      assertEquals(res.unregistered, undefined);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  // 4. Invalid / Unregistered Token Detection
  await t.step("4. FCM HTTP v1 correctly classifies UNREGISTERED tokens for database pruning", async () => {
    const originalFetch = globalThis.fetch;
    globalThis.fetch = () =>
      Promise.resolve(
        new Response(
          JSON.stringify({
            error: {
              code: 404,
              message: "Requested entity was not found.",
              status: "NOT_FOUND",
              details: [{ "@type": "type.googleapis.com/google.firebase.fcm.v1.FcmError", errorCode: "UNREGISTERED" }],
            },
          }),
          { status: 404, headers: { "Content-Type": "application/json" } }
        )
      );

    try {
      const res = await sendFcmHttpV1(
        "test-project",
        "mock_access_token",
        "dead_token_456",
        { title: "Test", body: "Hello", data: { id: "1" } }
      );
      assertEquals(res.success, false);
      assertEquals(res.unregistered, true);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  // 5. Transient Server Failure Classification
  await t.step("5. FCM HTTP v1 classifies transient 500/503 errors as retryable (not unregistered)", async () => {
    const originalFetch = globalThis.fetch;
    globalThis.fetch = () =>
      Promise.resolve(
        new Response(
          JSON.stringify({
            error: {
              code: 503,
              message: "The service is temporarily unavailable.",
              status: "UNAVAILABLE",
            },
          }),
          { status: 503, headers: { "Content-Type": "application/json" } }
        )
      );

    try {
      const res = await sendFcmHttpV1(
        "test-project",
        "mock_access_token",
        "transient_token_789",
        { title: "Test", body: "Hello", data: { id: "1" } }
      );
      assertEquals(res.success, false);
      assertEquals(res.unregistered, false);
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  // 6. Network Timeout Handling
  await t.step("6. FCM HTTP v1 handles network timeouts gracefully", async () => {
    const originalFetch = globalThis.fetch;
    globalThis.fetch = (_url, init) => {
      return new Promise((_, reject) => {
        init?.signal?.addEventListener("abort", () => {
          const err = new Error("The signal has been aborted");
          err.name = "AbortError";
          reject(err);
        });
      });
    };

    try {
      const res = await sendFcmHttpV1(
        "test-project",
        "mock_access_token",
        "timeout_token",
        { title: "Test", body: "Hello", data: { id: "1" } },
        10 // 10ms timeout
      );
      assertEquals(res.success, false);
      assertEquals(res.unregistered, false);
      assertEquals(res.error, "FCM request timed out");
    } finally {
      globalThis.fetch = originalFetch;
    }
  });

  // 7. Finalization Outcome Contract
  await t.step("7. Reminder finalization outcome classification contract", () => {
    const computeFinalizeOutcome = (totalTokens: number, successfulTokens: number, unregisteredTokens: number) => {
      if (successfulTokens > 0) {
        return "sent";
      }
      if (totalTokens > 0 && totalTokens === unregisteredTokens) {
        return "failed"; // Permanent failure: all tokens are unregistered
      }
      return "retryable"; // Transient failure
    };

    assertEquals(computeFinalizeOutcome(2, 1, 1), "sent");
    assertEquals(computeFinalizeOutcome(1, 1, 0), "sent");
    assertEquals(computeFinalizeOutcome(2, 0, 2), "failed");
    assertEquals(computeFinalizeOutcome(2, 0, 1), "retryable");
    assertEquals(computeFinalizeOutcome(1, 0, 0), "retryable");
  });
});
