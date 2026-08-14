begin;
set local lock_timeout = '10s';
set local statement_timeout = '30s';

-- This function is invoked by auth.on_auth_user_created. It must not also be
-- exposed as a directly callable SECURITY DEFINER RPC.
revoke execute on function public.handle_new_user() from public, anon, authenticated;
grant execute on function public.handle_new_user() to supabase_auth_admin, service_role;

commit;
