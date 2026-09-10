import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.0";
import admin from "https://esm.sh/firebase-admin@11.11.0";

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
    if (!authHeader) {
      return new Response(JSON.stringify({ error: 'Missing Authorization header' }), { 
        status: 401, headers: { 'Content-Type': 'application/json' } 
      });
    }

    // 1. Authorization Design
    let supabaseClient;
    const schedulerSecret = Deno.env.get('SCHEDULER_SECRET');
    const isScheduler = schedulerSecret && authHeader === `Bearer ${schedulerSecret}`;

    if (isScheduler) {
      // Model B: Trusted Server/Scheduler (bypasses RLS to fetch any reminder, but still respects ownership internally)
      supabaseClient = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
      );
    } else {
      // Model A: Authenticated User (uses user JWT, RLS enforces ownership)
      supabaseClient = createClient(
        Deno.env.get('SUPABASE_URL') ?? '',
        Deno.env.get('SUPABASE_ANON_KEY') ?? '',
        { global: { headers: { Authorization: authHeader } } }
      );
    }

    // 2. Fetch Reminder Event
    const { data: reminderData, error: reminderError } = await supabaseClient
      .from('reminder_events')
      .select('*')
      .eq('id', reminder_event_id)
      .single();

    if (reminderError || !reminderData) {
      return new Response(JSON.stringify({ error: 'Reminder not found or unauthorized' }), { 
        status: 404, headers: { 'Content-Type': 'application/json' } 
      });
    }

    if (reminderData.status !== 'pending') {
      return new Response(JSON.stringify({ error: 'Reminder is not pending' }), { 
        status: 400, headers: { 'Content-Type': 'application/json' } 
      });
    }

    if (!!reminderData.task_id === !!reminderData.due_id) {
        return new Response(JSON.stringify({ error: 'Reminder must have exactly one task_id or due_id' }), { status: 400, headers: { 'Content-Type': 'application/json' } });
    }

    // 3. Fetch User's Registered FCM Tokens (Use Service Role to query target user's tokens safely)
    const serviceRoleClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    const { data: tokensData, error: tokensError } = await serviceRoleClient
      .from('user_fcm_tokens')
      .select('fcm_token, device_id')
      .eq('user_id', reminderData.user_id);

    if (tokensError || !tokensData || tokensData.length === 0) {
      return new Response(JSON.stringify({ message: 'No registered devices found for user', success: false }), { 
        status: 200, headers: { 'Content-Type': 'application/json' } 
      });
    }

    const tokens = tokensData.map((t: any) => t.fcm_token);

    // 4. Initialize Firebase Admin
    const serviceAccountJson = Deno.env.get('FIREBASE_SERVICE_ACCOUNT_JSON');
    if (!serviceAccountJson) {
      return new Response(JSON.stringify({ error: 'Firebase credentials unavailable' }), { 
        status: 500, headers: { 'Content-Type': 'application/json' } 
      });
    }

    if (!admin.apps.length) {
      try {
        admin.initializeApp({
          credential: admin.credential.cert(JSON.parse(serviceAccountJson))
        });
      } catch (e) {
        return new Response(JSON.stringify({ error: 'Invalid Firebase credentials format' }), { 
          status: 500, headers: { 'Content-Type': 'application/json' } 
        });
      }
    }

    // 5. Construct Generic FCM Payload
    const message = {
      notification: {
        title: 'DueIt Reminder',
        body: 'You have a pending task or due.',
      },
      data: {
        reminder_event_id: reminderData.id,
        reminder_type: reminderData.reminder_type,
        entity_type: reminderData.task_id ? 'task' : 'due',
        entity_id: reminderData.task_id || reminderData.due_id,
      },
      tokens: tokens,
    };

    // 6. Send FCM Multicast
    const response = await admin.messaging().sendEachForMulticast(message);

    // 7. Cleanup Invalid Tokens
    const failedTokens: string[] = [];
    if (response.failureCount > 0) {
      response.responses.forEach((resp: any, idx: number) => {
        if (!resp.success) {
          const errorCode = resp.error?.code;
          if (errorCode === 'messaging/invalid-registration-token' ||
              errorCode === 'messaging/registration-token-not-registered') {
            failedTokens.push(tokens[idx]);
          }
        }
      });
    }

    if (failedTokens.length > 0) {
      await serviceRoleClient
        .from('user_fcm_tokens')
        .delete()
        .in('fcm_token', failedTokens);
    }

    // 8. Idempotency / Status Update
    if (response.successCount > 0 || tokens.length === failedTokens.length) {
      await serviceRoleClient
        .from('reminder_events')
        .update({ status: 'sent', sent_at: new Date().toISOString() })
        .eq('id', reminder_event_id);
    }

    return new Response(JSON.stringify({
      success: true,
      successCount: response.successCount,
      failureCount: response.failureCount,
      cleanedTokens: failedTokens.length,
    }), { 
      status: 200, headers: { 'Content-Type': 'application/json' } 
    });

  } catch (error) {
    return new Response(JSON.stringify({ error: 'Internal Server Error' }), { 
      status: 500, headers: { 'Content-Type': 'application/json' } 
    });
  }
});
