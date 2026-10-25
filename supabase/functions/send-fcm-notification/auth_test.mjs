import assert from 'node:assert';
import test from 'node:test';

// Simulation of the updated authorization check in send-fcm-notification/index.ts
function checkSchedulerAuth(authHeader, schedulerSecret) {
  if (!schedulerSecret || authHeader !== `Bearer ${schedulerSecret}`) {
    return {
      status: 401,
      body: { error: 'Unauthorized: Invalid or missing scheduler secret' }
    };
  }
  return { status: 200, authorized: true };
}

test('send-fcm-notification authorization contracts', async (t) => {
  const SECRET = 'test_scheduler_secret_98765';

  await t.test('1. Rejects request when Authorization header is missing', () => {
    const res = checkSchedulerAuth(null, SECRET);
    assert.strictEqual(res.status, 401);
    assert.strictEqual(res.body.error, 'Unauthorized: Invalid or missing scheduler secret');
  });

  await t.test('2. Rejects request when SCHEDULER_SECRET environment variable is missing/unset', () => {
    const res = checkSchedulerAuth(`Bearer ${SECRET}`, null);
    assert.strictEqual(res.status, 401);
    assert.strictEqual(res.body.error, 'Unauthorized: Invalid or missing scheduler secret');
  });

  await t.test('3. Rejects user JWT tokens (alternate user authorization path removed)', () => {
    const userJwt = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.do_not_accept';
    const res = checkSchedulerAuth(`Bearer ${userJwt}`, SECRET);
    assert.strictEqual(res.status, 401);
  });

  await t.test('4. Rejects invalid or mismatched scheduler secret', () => {
    const res = checkSchedulerAuth('Bearer wrong_secret', SECRET);
    assert.strictEqual(res.status, 401);
  });

  await t.test('5. Rejects malformed authorization header scheme (e.g. Basic / token without Bearer prefix)', () => {
    const res1 = checkSchedulerAuth(`Basic ${SECRET}`, SECRET);
    assert.strictEqual(res1.status, 401);

    const res2 = checkSchedulerAuth(SECRET, SECRET);
    assert.strictEqual(res2.status, 401);
  });

  await t.test('6. Accepts exactly valid Authorization: Bearer <SCHEDULER_SECRET>', () => {
    const res = checkSchedulerAuth(`Bearer ${SECRET}`, SECRET);
    assert.strictEqual(res.status, 200);
    assert.strictEqual(res.authorized, true);
  });
});
