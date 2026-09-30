create table public.garment_length_classification_rules (
id uuid primary key default gen_random_uuid(), source_id uuid null references public.sources(id) on delete restrict,
app_category_id uuid not null references public.app_categories(id) on delete restrict, audience text not null,
measurement_basis_code text not null, threshold_cm numeric(6,2) not null,
short_result_category_id uuid not null references public.app_categories(id) on delete restrict,
long_result_category_id uuid not null references public.app_categories(id) on delete restrict,
comparison_operator text not null default 'lte_short', measurement_priority smallint not null,
rule_priority smallint not null default 10, policy_version text not null, is_active boolean not null default true,
evidence_note text, created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
constraint garment_length_rules_audience_check check (audience in ('MEN','WOMEN','KIDS','BABY','UNKNOWN','ALL')),
constraint garment_length_rules_basis_check check (measurement_basis_code in ('shoulder_to_sleeve_end','center_back_to_sleeve_end','raglan_neck_to_sleeve_end','inseam','outseam_total_length')),
constraint garment_length_rules_threshold_check check (threshold_cm > 0),
constraint garment_length_rules_operator_check check (comparison_operator = 'lte_short'),
constraint garment_length_rules_measurement_priority_check check (measurement_priority > 0),
constraint garment_length_rules_rule_priority_check check (rule_priority > 0),
constraint garment_length_rules_distinct_results_check check (short_result_category_id <> long_result_category_id),
constraint garment_length_rules_unique unique nulls not distinct (source_id,app_category_id,audience,measurement_basis_code,policy_version));
comment on table public.garment_length_classification_rules is 'FitMatch length-based garment detail classification thresholds. NULL source_id means common fallback.';
create index garment_length_rules_lookup_idx on public.garment_length_classification_rules
(app_category_id,measurement_basis_code,audience,source_id,rule_priority desc) where is_active=true;
alter table public.garment_length_classification_rules enable row level security;
revoke all on table public.garment_length_classification_rules from anon, authenticated;
grant select on table public.garment_length_classification_rules to anon, authenticated;
create policy "Public can read active garment length rules" on public.garment_length_classification_rules
for select to anon, authenticated using (is_active=true);

with src as (
select max(id::text) filter(where code='musinsa')::uuid musinsa_id,
max(id::text) filter(where code='uniqlo')::uuid uniqlo_id from public.sources),
cat as (
select max(id::text) filter(where code='tops' and depth=0)::uuid tops_id,
max(id::text) filter(where code='bottoms' and depth=0)::uuid bottoms_id,
max(id::text) filter(where code='short_sleeve' and depth=1)::uuid short_sleeve_id,
max(id::text) filter(where code='long_sleeve' and depth=1)::uuid long_sleeve_id,
max(id::text) filter(where code='short_pants' and depth=1)::uuid short_pants_id,
max(id::text) filter(where code='long_pants' and depth=1)::uuid long_pants_id from public.app_categories),
rules(source_code,audience,app_category,basis,threshold,short_code,long_code,measurement_priority,rule_priority,note) as (values
('uniqlo','MEN','tops','center_back_to_sleeve_end',67.0,'short_sleeve','long_sleeve',2,100,'17e9a8b Uniqlo MEN center-back sleeve'),
('uniqlo','WOMEN','tops','center_back_to_sleeve_end',60.0,'short_sleeve','long_sleeve',2,100,'17e9a8b Uniqlo WOMEN center-back sleeve'),
('uniqlo','KIDS','tops','center_back_to_sleeve_end',34.5,'short_sleeve','long_sleeve',2,100,'17e9a8b Uniqlo KIDS center-back sleeve'),
('uniqlo','BABY','tops','center_back_to_sleeve_end',34.5,'short_sleeve','long_sleeve',2,100,'17e9a8b Uniqlo BABY center-back sleeve'),
('uniqlo','UNKNOWN','tops','center_back_to_sleeve_end',63.5,'short_sleeve','long_sleeve',2,100,'17e9a8b Uniqlo unknown center-back sleeve'),
('musinsa','MEN','tops','shoulder_to_sleeve_end',52.0,'short_sleeve','long_sleeve',1,100,'17e9a8b Musinsa MEN shoulder-to-cuff'),
('musinsa','WOMEN','tops','shoulder_to_sleeve_end',43.0,'short_sleeve','long_sleeve',1,100,'17e9a8b Musinsa WOMEN shoulder-to-cuff'),
('musinsa','UNKNOWN','tops','shoulder_to_sleeve_end',47.5,'short_sleeve','long_sleeve',1,100,'17e9a8b Musinsa unknown shoulder-to-cuff'),
(null,'MEN','tops','shoulder_to_sleeve_end',50.0,'short_sleeve','long_sleeve',1,10,'17e9a8b common MEN shoulder-to-cuff fallback'),
(null,'WOMEN','tops','shoulder_to_sleeve_end',42.0,'short_sleeve','long_sleeve',1,10,'17e9a8b common WOMEN shoulder-to-cuff fallback'),
(null,'UNKNOWN','tops','shoulder_to_sleeve_end',46.0,'short_sleeve','long_sleeve',1,10,'17e9a8b common unknown shoulder-to-cuff fallback'),
(null,'MEN','tops','center_back_to_sleeve_end',67.0,'short_sleeve','long_sleeve',2,10,'17e9a8b common MEN center-back fallback'),
(null,'WOMEN','tops','center_back_to_sleeve_end',60.0,'short_sleeve','long_sleeve',2,10,'17e9a8b common WOMEN center-back fallback'),
(null,'UNKNOWN','tops','center_back_to_sleeve_end',63.5,'short_sleeve','long_sleeve',2,10,'17e9a8b common unknown center-back fallback'),
(null,'ALL','tops','raglan_neck_to_sleeve_end',52.5,'short_sleeve','long_sleeve',3,10,'17e9a8b common raglan fallback'),
('uniqlo','ALL','bottoms','inseam',46.5,'short_pants','long_pants',1,100,'17e9a8b Uniqlo inseam'),
(null,'ALL','bottoms','inseam',48.0,'short_pants','long_pants',1,10,'17e9a8b common inseam fallback'),
('musinsa','MEN','bottoms','outseam_total_length',84.0,'short_pants','long_pants',2,100,'17e9a8b Musinsa MEN outseam/total'),
('musinsa','WOMEN','bottoms','outseam_total_length',65.0,'short_pants','long_pants',2,100,'17e9a8b Musinsa WOMEN outseam/total'),
('musinsa','UNKNOWN','bottoms','outseam_total_length',74.0,'short_pants','long_pants',2,100,'17e9a8b Musinsa unknown outseam/total'),
(null,'MEN','bottoms','outseam_total_length',84.0,'short_pants','long_pants',2,10,'17e9a8b common MEN outseam/total fallback'),
(null,'WOMEN','bottoms','outseam_total_length',65.0,'short_pants','long_pants',2,10,'17e9a8b common WOMEN outseam/total fallback'),
(null,'UNKNOWN','bottoms','outseam_total_length',74.0,'short_pants','long_pants',2,10,'17e9a8b common unknown outseam/total fallback'))
insert into public.garment_length_classification_rules
(source_id,app_category_id,audience,measurement_basis_code,threshold_cm,short_result_category_id,long_result_category_id,comparison_operator,measurement_priority,rule_priority,policy_version,evidence_note)
select case r.source_code when 'musinsa' then s.musinsa_id when 'uniqlo' then s.uniqlo_id else null end,
case r.app_category when 'tops' then c.tops_id else c.bottoms_id end,r.audience,r.basis,r.threshold,
case r.short_code when 'short_sleeve' then c.short_sleeve_id else c.short_pants_id end,
case r.long_code when 'long_sleeve' then c.long_sleeve_id else c.long_pants_id end,
'lte_short',r.measurement_priority,r.rule_priority,'17e9a8b-v1',r.note
from rules r cross join src s cross join cat c;;
