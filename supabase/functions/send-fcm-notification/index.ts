import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.0";
import { getGoogleAccessToken, sendFcmHttpV1, ServiceAccount } from "./fcm_v1.ts";

const UUID_REGEX = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { 
      headers: { 
        'Access-Control-Allow-Origin': '*', 
        'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type' 
      } 
    });
  }

  try {
    const payload = await req.json().catch(() => ({}));
    const reminder_event_id = payload.reminder_event_id;

    if (!reminder_event_id || !UUID_REGEX.test(reminder_event_id)) {
      return new Response(JSON.stringify({ error: 'Missing or invalid reminder_event_id' }), { 
        status: 400, headers: { 'Content-Type': 'application/json' } 
      });
    }

    const authHeader = req.headers.get('Authorization');
    const schedulerSecret = Deno.env.get('SCHEDULER_SECRET');

    // Strict internal endpoint authentication: only accepts valid SCHEDULER_SECRET
    if (!schedulerSecret || authHeader !== `Bearer ${schedulerSecret}`) {
      return new Response(JSON.stringify({ error: 'Unauthorized: Invalid or missing scheduler secret' }), { 
        status: 401, headers: { 'Content-Type': 'application/json' } 
      });
    }

    // 2. Atomic In-Flight Claim via RPC
    // Call dueit_claim_reminder directly to safely claim an eligible reminder (status 'pending' or expired 'processing')
    // and receive an opaque, cryptographically generated claim_token.
    const serviceRoleClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    const { data: claimRows, error: claimError } = await serviceRoleClient
      .rpc('dueit_claim_reminder', {
        p_reminder_id: reminder_event_id,
        p_lease_seconds: 120
      });

    if (claimError) {
      console.error('Claim RPC error:', claimError);
      return new Response(JSON.stringify({ error: 'Database claim RPC error', details: claimError.message }), {
        status: 500, headers: { 'Content-Type': 'application/json' }
      });
    }

    const claimResult = Array.isArray(claimRows) ? claimRows[0] : claimRows;

    if (!claimResult || !claimResult.claimed) {
      return new Response(JSON.stringify({ 
        success: true, 
        duplicate_prevented: true, 
        message: 'Reminder currently claimed by another in-flight worker, already processed, or max attempts reached' 
      }), { status: 200, headers: { 'Content-Type': 'application/json' } });
    }

    const claimToken = claimResult.claim_token;
    const reminderData = claimResult.reminder_record;

    if (!reminderData || !claimToken) {
      return new Response(JSON.stringify({ error: 'Claim succeeded but missing reminder record or token' }), {
        status: 500, headers: { 'Content-Type': 'application/json' }
      });
    }

    // 3. Verify underlying Task or Due active state (Cancel if completed, settled, or deleted)
    if (reminderData.task_id) {
      const { data: taskData, error: taskError } = await serviceRoleClient
        .from('tasks')
        .select('id, is_completed, due_date')
        .eq('id', reminderData.task_id)
        .maybeSingle();

      if (taskError || !taskData || taskData.is_completed) {
        await serviceRoleClient.rpc('dueit_finalize_reminder', {
          p_reminder_id: reminder_event_id,
          p_claim_token: claimToken,
          p_outcome: 'cancelled',
          p_error: !taskData ? 'Task deleted' : 'Task already completed'
        });

        return new Response(JSON.stringify({ 
          success: true, 
          cancelled: true, 
          reason: !taskData ? 'Task deleted' : 'Task already completed' 
        }), { status: 200, headers: { 'Content-Type': 'application/json' } });
      }
    } else if (reminderData.due_id) {
      const { data: dueData, error: dueError } = await serviceRoleClient
        .from('dues')
        .select('id, status, due_date')
        .eq('id', reminderData.due_id)
        .maybeSingle();

      if (dueError || !dueData || dueData.status === 'settled') {
        await serviceRoleClient.rpc('dueit_finalize_reminder', {
          p_reminder_id: reminder_event_id,
          p_claim_token: claimToken,
          p_outcome: 'cancelled',
          p_error: !dueData ? 'Due deleted' : 'Due already settled'
        });

        return new Response(JSON.stringify({ 
          success: true, 
          cancelled: true, 
          reason: !dueData ? 'Due deleted' : 'Due already settled' 
        }), { status: 200, headers: { 'Content-Type': 'application/json' } });
      }
    }

    // 4. Fetch User's Registered FCM Tokens
    const { data: tokensData, error: tokensError } = await serviceRoleClient
      .from('user_fcm_tokens')
      .select('fcm_token, device_id')
      .eq('user_id', reminderData.user_id);

    if (tokensError || !tokensData || tokensData.length === 0) {
      // If user has no registered devices, mark as 'failed' (permanent)
      await serviceRoleClient.rpc('dueit_finalize_reminder', {
        p_reminder_id: reminder_event_id,
        p_claim_token: claimToken,
        p_outcome: 'failed',
        p_error: 'No registered devices found for user'
      });

      return new Response(JSON.stringify({ 
        message: 'No registered devices found for user', 
        success: false 
      }), { status: 200, headers: { 'Content-Type': 'application/json' } });
    }

    const tokens = tokensData.map((t: any) => t.fcm_token);

    // 5. Initialize Firebase Service Account & Exchange OAuth2 Access Token
    const serviceAccountJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');
    if (!serviceAccountJson) {
      await serviceRoleClient.rpc('dueit_finalize_reminder', {
        p_reminder_id: reminder_event_id,
        p_claim_token: claimToken,
        p_outcome: 'retryable',
        p_error: 'Firebase credentials unavailable'
      });
      return new Response(JSON.stringify({ error: 'Firebase credentials unavailable' }), { 
        status: 500, headers: { 'Content-Type': 'application/json' } 
      });
    }

    let serviceAccount: ServiceAccount;
    let accessToken: string;
    try {
      serviceAccount = JSON.parse(serviceAccountJson);
      accessToken = await getGoogleAccessToken(serviceAccount, 10000);
    } catch (e: any) {
      console.error('Firebase OAuth authentication failed:', e.message || e);
      await serviceRoleClient.rpc('dueit_finalize_reminder', {
        p_reminder_id: reminder_event_id,
        p_claim_token: claimToken,
        p_outcome: 'retryable',
        p_error: 'Invalid Firebase credentials or OAuth exchange failed'
      });
      return new Response(JSON.stringify({ error: 'Invalid Firebase credentials or OAuth exchange failed' }), { 
        status: 500, headers: { 'Content-Type': 'application/json' } 
      });
    }

    // 6. Construct Generic FCM Payload
    const fcmPayload = {
      title: 'DueIt Reminder',
      body: 'You have a pending task or due.',
      data: {
        reminder_event_id: String(reminderData.id),
        reminder_type: String(reminderData.reminder_type),
        entity_type: reminderData.task_id ? 'task' : 'due',
        entity_id: String(reminderData.task_id || reminderData.due_id),
      },
    };

    // 7. Dispatch FCM HTTP v1 notifications concurrently with 15s bounded timeout
    const sendPromises = tokens.map((t: string) =>
      sendFcmHttpV1(serviceAccount.project_id, accessToken, t, fcmPayload, 15000)
    );

    const results = await Promise.all(sendPromises);

    const successfulTokens = results.filter((r) => r.success);
    const failedTokens = results.filter((r) => !r.success);
    const unregisteredTokens = results.filter((r) => r.unregistered).map((r) => r.token);

    // 8. Prune Confirmed Unregistered/Invalid Tokens
    if (unregisteredTokens.length > 0) {
      await serviceRoleClient
        .from('user_fcm_tokens')
        .delete()
        .in('fcm_token', unregisteredTokens);
    }

    // 9. Atomic Final Status Update via RPC:
    // Requires exact claim_token. Prevents stale workers whose lease expired from overwriting state.
    if (successfulTokens.length > 0) {
      const { data: finalized, error: finalizeError } = await serviceRoleClient
        .rpc('dueit_finalize_reminder', {
          p_reminder_id: reminder_event_id,
          p_claim_token: claimToken,
          p_outcome: 'sent'
        });

      if (finalizeError || !finalized) {
        // Another worker reclaimed the lease or finalized it; this worker is stale.
        return new Response(JSON.stringify({
          success: true,
          duplicate_prevented: true,
          stale_worker: true,
          message: 'Notification sent, but reminder was superseded or finalized by another worker',
          successCount: successfulTokens.length,
        }), { status: 200, headers: { 'Content-Type': 'application/json' } });
      }

      return new Response(JSON.stringify({
        success: true,
        message: 'Notification dispatched successfully',
        successCount: successfulTokens.length,
        failureCount: failedTokens.length,
        unregisteredPruned: unregisteredTokens.length,
      }), { status: 200, headers: { 'Content-Type': 'application/json' } });
    } else {
      // Total failure
      const isPermanent = tokens.length === unregisteredTokens.length;
      await serviceRoleClient.rpc('dueit_finalize_reminder', {
        p_reminder_id: reminder_event_id,
        p_claim_token: claimToken,
        p_outcome: isPermanent ? 'failed' : 'retryable',
        p_error: `All FCM sends failed (${failedTokens.map(f => f.error).join(', ')})`
      });

      return new Response(JSON.stringify({
        success: false,
        message: isPermanent ? 'All user devices were unregistered; reminder marked failed' : 'FCM dispatch failed; marked retryable',
        failureCount: failedTokens.length,
        errors: failedTokens.map(f => f.error),
      }), { status: 502, headers: { 'Content-Type': 'application/json' } });
    }

  } catch (error: any) {
    console.error('Unhandled notification sender error:', error);
    return new Response(JSON.stringify({ error: 'Internal Server Error' }), { 
      status: 500, headers: { 'Content-Type': 'application/json' } 
    });
  }
});
