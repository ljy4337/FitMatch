import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "npm:@supabase/supabase-js@2"

const jsonHeaders = {
  "Content-Type": "application/json; charset=utf-8",
}

function jsonResponse(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), { status, headers: jsonHeaders })
}

function isDomainIngestionError(code: string | undefined): boolean {
  return code === "P0001" || code?.startsWith("22") === true ||
    code?.startsWith("23") === true
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
  if (
    !body.payload ||
    typeof body.payload !== "object" ||
    Array.isArray(body.payload)
  ) {
    return jsonResponse({ error: "payload_must_be_object" }, 400)
  }

  // Validate the caller's signed-in user JWT before creating the server-only
  // client. The service role never leaves this Edge Function.
  const userClient = createClient(supabaseURL, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { data: authData, error: authError } = await userClient.auth.getUser()
  if (authError || !authData.user) {
    return jsonResponse({ error: "invalid_session" }, 401)
  }

  const adminClient = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { data: ingestion, error: ingestionError } = await adminClient
    .rpc("fitmatch_vnext_ingest_product_observation", {
      p_payload: body.payload,
      p_actor_id: authData.user.id,
    })
  if (ingestionError) {
    if (!isDomainIngestionError(ingestionError.code)) {
      console.error("vNext ingestion failed", { code: ingestionError.code })
      return jsonResponse({ error: "server_processing_failed" }, 500)
    }

    return jsonResponse(
      {
        error: "observation_rejected",
        detail: ingestionError.message,
      },
      422,
    )
  }

  const observationID = ingestion?.observation?.observation_id
  const processingID = ingestion?.processing?.observation_id
  if (
    typeof observationID !== "string" ||
    observationID !== processingID ||
    typeof ingestion?.processing?.product_id !== "string"
  ) {
    return jsonResponse({ error: "invalid_ingestion_response" }, 500)
  }

  // Keep the existing iOS DTO success value while exposing the vNext state as
  // additive provenance. No legacy database write occurs.
  return jsonResponse({
    ...ingestion,
    processing: {
      ...ingestion.processing,
      status: "promoted",
      vnext_status: ingestion.processing.status,
    },
  }, 200)
})
