import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.38.0";

// Configuration Constants
const UPCOMING_ADVANCE_MS = 24 * 60 * 60 * 1000; // 24 hours before
const DEADLINE_TOLERANCE_MS = 15 * 60 * 1000;    // 15 minutes tolerance for deadline expiration
const OVERDUE_DELAY_MS = 60 * 60 * 1000;         // 1 hour after due date

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
    const authHeader = req.headers.get('Authorization');
    const schedulerSecret = Deno.env.get('SCHEDULER_SECRET');

    if (!schedulerSecret || authHeader !== `Bearer ${schedulerSecret}`) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), { 
        status: 401, headers: { 'Content-Type': 'application/json' } 
      });
    }

    const supabase = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? ''
    );

    const now = new Date();
    const newReminders: any[] = [];

    const { data: tasks, error: tasksError } = await supabase
      .from('tasks')
      .select('id, user_id, due_date')
      .eq('is_completed', false)
      .not('due_date', 'is', null)
      .limit(1000);

    if (tasksError) throw tasksError;

    const { data: dues, error: duesError } = await supabase
      .from('dues')
      .select('id, user_id, due_date, status')
      .neq('status', 'settled')
      .not('due_date', 'is', null)
      .limit(1000);

    if (duesError) throw duesError;

    const taskIds = tasks?.map(t => t.id) || [];
    const dueIds = dues?.map(d => d.id) || [];

    const chunk = (arr: any[], size: number) => 
      Array.from({ length: Math.ceil(arr.length / size) }, (v, i) => arr.slice(i * size, i * size + size));

    const existingReminders: any[] = [];
    
    for (const chunked of chunk(taskIds, 200)) {
       const { data, error } = await supabase.from('reminder_events').select('task_id, reminder_type').in('task_id', chunked);
       if (error) throw error;
       if (data) existingReminders.push(...data);
    }
    
    for (const chunked of chunk(dueIds, 200)) {
       const { data, error } = await supabase.from('reminder_events').select('due_id, reminder_type').in('due_id', chunked);
       if (error) throw error;
       if (data) existingReminders.push(...data);
    }

    const hasReminder = (entityId: string, isTask: boolean, type: string) => {
      return existingReminders.some(r => 
        (isTask ? r.task_id === entityId : r.due_id === entityId) && 
        r.reminder_type === type
      );
    };

    if (tasks) {
      for (const task of tasks) {
        const dueDate = new Date(task.due_date);
        const upcomingDate = new Date(dueDate.getTime() - UPCOMING_ADVANCE_MS);
        const deadlineExp = new Date(dueDate.getTime() + DEADLINE_TOLERANCE_MS);
        const overdueDate = new Date(dueDate.getTime() + OVERDUE_DELAY_MS);

        // Rule 1: Upcoming - only before due date
        if (now >= upcomingDate && now < dueDate && !hasReminder(task.id, true, 'upcoming')) {
          newReminders.push({
            user_id: task.user_id,
            task_id: task.id,
            due_id: null,
            entity_type: 'task',
            reminder_type: 'upcoming',
            scheduled_time: upcomingDate.toISOString(),
            status: 'pending'
          });
          existingReminders.push({ task_id: task.id, reminder_type: 'upcoming' });
        }

        // Rule 2: Deadline - only if within tolerance window
        if (now >= dueDate && now <= deadlineExp && !hasReminder(task.id, true, 'deadline')) {
          newReminders.push({
            user_id: task.user_id,
            task_id: task.id,
            due_id: null,
            entity_type: 'task',
            reminder_type: 'deadline',
            scheduled_time: dueDate.toISOString(),
            status: 'pending'
          });
          existingReminders.push({ task_id: task.id, reminder_type: 'deadline' });
        }

        // Rule 3: Overdue - valid anytime after +1 hour
        if (now >= overdueDate && !hasReminder(task.id, true, 'overdue')) {
          newReminders.push({
            user_id: task.user_id,
            task_id: task.id,
            due_id: null,
            entity_type: 'task',
            reminder_type: 'overdue',
            scheduled_time: overdueDate.toISOString(),
            status: 'pending'
          });
          existingReminders.push({ task_id: task.id, reminder_type: 'overdue' });
        }
      }
    }

    if (dues) {
      for (const due of dues) {
        const dueDate = new Date(due.due_date);
        const upcomingDate = new Date(dueDate.getTime() - UPCOMING_ADVANCE_MS);
        const deadlineExp = new Date(dueDate.getTime() + DEADLINE_TOLERANCE_MS);
        const overdueDate = new Date(dueDate.getTime() + OVERDUE_DELAY_MS);

        if (now >= upcomingDate && now < dueDate && !hasReminder(due.id, false, 'upcoming')) {
          newReminders.push({
            user_id: due.user_id,
            task_id: null,
            due_id: due.id,
            entity_type: 'due',
            reminder_type: 'upcoming',
            scheduled_time: upcomingDate.toISOString(),
            status: 'pending'
          });
          existingReminders.push({ due_id: due.id, reminder_type: 'upcoming' });
        }

        if (now >= dueDate && now <= deadlineExp && !hasReminder(due.id, false, 'deadline')) {
          newReminders.push({
            user_id: due.user_id,
            task_id: null,
            due_id: due.id,
            entity_type: 'due',
            reminder_type: 'deadline',
            scheduled_time: dueDate.toISOString(),
            status: 'pending'
          });
          existingReminders.push({ due_id: due.id, reminder_type: 'deadline' });
        }

        if (now >= overdueDate && !hasReminder(due.id, false, 'overdue')) {
          newReminders.push({
            user_id: due.user_id,
            task_id: null,
            due_id: due.id,
            entity_type: 'due',
            reminder_type: 'overdue',
            scheduled_time: overdueDate.toISOString(),
            status: 'pending'
          });
          existingReminders.push({ due_id: due.id, reminder_type: 'overdue' });
        }
      }
    }

    let insertedCount = 0;
    let duplicateCount = 0;
    let invalidCount = 0;

    if (newReminders.length > 0) {
      for (const chunkedReminders of chunk(newReminders, 200)) {
        const { data: rpcResult, error: rpcError } = await supabase
          .rpc('dueit_insert_reminder_occurrences', {
            p_reminders: chunkedReminders
          });
          
        if (rpcError) {
          console.error('RPC error during reminder ingestion:', rpcError);
          throw new Error(`Failed to insert reminder batch: ${rpcError.message}`);
        } else if (rpcResult) {
          insertedCount += rpcResult.inserted_count || 0;
          duplicateCount += rpcResult.duplicate_count || 0;
          invalidCount += rpcResult.invalid_count || 0;
        }
      }
    }

    return new Response(JSON.stringify({
      success: true,
      evaluatedTasks: tasks?.length || 0,
      evaluatedDues: dues?.length || 0,
      generatedReminders: newReminders.length,
      insertedReminders: insertedCount,
      duplicateReminders: duplicateCount,
      invalidReminders: invalidCount
    }), { 
      status: 200, headers: { 'Content-Type': 'application/json' } 
    });

  } catch (error: any) {
    console.error('Generator error:', error);
    return new Response(JSON.stringify({ error: 'Internal Server Error' }), { 
      status: 500, headers: { 'Content-Type': 'application/json' } 
    });
  }
});
