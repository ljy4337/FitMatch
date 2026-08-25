import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "npm:@supabase/supabase-js@2"

const jsonHeaders = {
  "Content-Type": "application/json; charset=utf-8",
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders })
}

Deno.serve(async (request: Request) => {
  if (request.method !== "POST") {
    return jsonResponse({ error: "method_not_allowed" }, 405)
  }

  const authorization = request.headers.get("Authorization")
  if (!authorization) {
    return jsonResponse({ error: "authentication_required" }, 401)
  }

  const supabaseURL = Deno.env.get("SUPABASE_URL")
  const anonKey = Deno.env.get("SUPABASE_ANON_KEY")
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
  if (!supabaseURL || !anonKey || !serviceRoleKey) {
    return jsonResponse({ error: "server_configuration_error" }, 500)
  }

  let body: { payload?: Record<string, unknown> }
  try {
    body = await request.json()
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400)
  }
  if (!body.payload || Array.isArray(body.payload)) {
    return jsonResponse({ error: "payload_must_be_object" }, 400)
  }

  // The user-scoped client keeps auth.uid() and the public submission boundary
  // intact. The service-role client is created only inside this Edge Function.
  const userClient = createClient(supabaseURL, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { error: authError } = await userClient.auth.getUser()
  if (authError) {
    return jsonResponse({ error: "invalid_session" }, 401)
  }

  const { data: observation, error: submissionError } = await userClient.rpc(
    "fitmatch_submit_product_observation",
    { p_payload: body.payload },
  )
  if (submissionError) {
    return jsonResponse(
      { error: "observation_rejected", detail: submissionError.message },
      422,
    )
  }

  const observationID = observation?.observation_id
  if (typeof observationID !== "string") {
    return jsonResponse({ error: "invalid_submission_response" }, 500)
  }

  const adminClient = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { data: processing, error: processingError } = await adminClient.rpc(
    "fitmatch_process_product_observation",
    { p_observation_id: observationID },
  )
  if (processingError) {
    return jsonResponse(
      {
        observation,
        processing: { status: "rejected", error: "processing_failed" },
      },
      500,
    )
  }

  const status = processing?.status === "promoted" ? 200 : 422
  return jsonResponse({ observation, processing }, status)
})
