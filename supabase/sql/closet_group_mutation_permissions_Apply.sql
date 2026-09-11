-- Move the audited group-aware mutations behind the existing private RPC boundary.
-- Abort on source drift rather than replacing a newer production implementation.
do $migration$
declare
  spec record;
  body text;
begin
  for spec in select * from (values
    ('fitmatch_vnext_upsert_closet_item', 'jsonb', 'p_request jsonb',
     'upsert_closet_item_with_group_for_swift', 'ee2f80a1db6517812e1d7079b8cef51a'),
    ('fitmatch_vnext_update_closet_item', 'uuid,jsonb', 'p_closet_item_id uuid,p_request jsonb',
     'update_closet_item_with_group_for_swift', 'b20fcae24832f5d3eea5134ba35b38de')
  ) as v(public_name, arg_types, args, private_name, expected_hash)
  loop
    select p.prosrc into strict body from pg_proc p
    where p.oid = to_regprocedure('public.' || spec.public_name || '(' || spec.arg_types || ')');
    if md5(body) <> spec.expected_hash then
      raise exception 'Closet RPC source drift: %', spec.public_name;
    end if;
    body := replace(body, E'begin\n', E'begin\n if auth.uid() is null then raise exception ''Authentication required''; end if;\n');
    execute format(
      'create function fitmatch_vnext.%I(%s) returns jsonb language plpgsql security definer set search_path = %L as %L',
      spec.private_name, spec.args, '', body
    );
    execute format('revoke all on function fitmatch_vnext.%I(%s) from public,anon',
      spec.private_name,spec.arg_types);
    execute format('grant execute on function fitmatch_vnext.%I(%s) to authenticated,service_role',
      spec.private_name,spec.arg_types);
  end loop;
end
$migration$;

create or replace function public.fitmatch_vnext_upsert_closet_item(p_request jsonb)
returns jsonb language sql security invoker set search_path = ''
as $function$
  select fitmatch_vnext.upsert_closet_item_with_group_for_swift(p_request)
$function$;

create or replace function public.fitmatch_vnext_update_closet_item(
  p_closet_item_id uuid,p_request jsonb
)
returns jsonb language sql security invoker set search_path = ''
as $function$
  select fitmatch_vnext.update_closet_item_with_group_for_swift(p_closet_item_id,p_request)
$function$;

revoke all on function public.fitmatch_vnext_upsert_closet_item(jsonb),
 public.fitmatch_vnext_update_closet_item(uuid,jsonb) from public,anon;
grant execute on function public.fitmatch_vnext_upsert_closet_item(jsonb),
 public.fitmatch_vnext_update_closet_item(uuid,jsonb) to authenticated,service_role;

