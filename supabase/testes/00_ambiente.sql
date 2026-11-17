-- Corte DÚ Amigo · testes · 00 · O que o Supabase já entrega pronto
-- Roda ANTES das migrations, num Postgres vazio, pra elas encontrarem o mesmo chão
-- que encontram no Supabase. Não rodar no banco de verdade.

create role anon nologin;
create role authenticated nologin;

create schema extensions;
grant usage on schema extensions to public;

create schema auth;
grant usage on schema auth to public;

create table auth.users (
  id uuid primary key default gen_random_uuid(),
  email text
);

-- No Supabase o login chega como claim do JWT. Aqui o teste escreve o claim na mão.
create function auth.uid() returns uuid
language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid
$$;

create publication supabase_realtime;

-- No Supabase, tudo que nasce no schema public já vem liberado pra anon e authenticated.
-- É por isso que as migrations precisam revogar: sem repetir isso aqui, o teste de
-- permissão passaria mesmo se o revoke estivesse faltando.
grant usage on schema public to anon, authenticated;
alter default privileges in schema public grant all on tables to anon, authenticated;
alter default privileges in schema public grant all on sequences to anon, authenticated;
alter default privileges in schema public grant execute on functions to anon, authenticated;
