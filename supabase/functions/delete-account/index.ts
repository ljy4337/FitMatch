import "jsr:@supabase/functions-js/edge-runtime.d.ts"
import { createClient } from "npm:@supabase/supabase-js@2"

const confirmationText = "DELETE_MY_FITMATCH_ACCOUNT"
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

  let body: { confirmation?: string }
  try {
    body = await request.json()
  } catch {
    return jsonResponse({ error: "invalid_json" }, 400)
  }
  if (body.confirmation !== confirmationText) {
    return jsonResponse({ error: "confirmation_required" }, 400)
  }

  const userClient = createClient(supabaseURL, anonKey, {
    global: { headers: { Authorization: authorization } },
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { data: userData, error: authError } = await userClient.auth.getUser()
  if (authError || !userData.user) {
    return jsonResponse({ error: "invalid_session" }, 401)
  }

  // Provider-neutral deletion: deleting the Supabase user removes every linked
  // identity (Apple now, Kakao/Naver later) and cascades user-owned FitMatch rows.
  const adminClient = createClient(supabaseURL, serviceRoleKey, {
    auth: { persistSession: false, autoRefreshToken: false },
  })
  const { error: deletionError } = await adminClient.auth.admin.deleteUser(
    userData.user.id,
  )
  if (deletionError) {
    return jsonResponse({ error: "account_deletion_failed" }, 500)
  }

  return jsonResponse({ deleted: true })
})
