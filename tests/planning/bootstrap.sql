-- Local test-only Supabase auth/storage boundary. Never applied to a hosted project.
create role anon;create role authenticated;create role service_role;
create schema auth;create schema storage;
create table auth.users(id uuid primary key,email text,email_confirmed_at timestamptz,is_anonymous boolean default false,banned_until timestamptz,created_at timestamptz,updated_at timestamptz);
create table auth.sessions(id uuid primary key,user_id uuid references auth.users(id),aal text,not_after timestamptz,created_at timestamptz,updated_at timestamptz);
create table auth.mfa_amr_claims(id uuid primary key,session_id uuid references auth.sessions(id),authentication_method text,created_at timestamptz not null,updated_at timestamptz not null);
create function auth.jwt() returns jsonb language sql stable as $$select coalesce(nullif(current_setting('request.jwt.claims',true),''),'{}')::jsonb$$;
create function auth.uid() returns uuid language sql stable as $$select nullif(auth.jwt()->>'sub','')::uuid$$;
grant usage on schema auth,storage to anon,authenticated,service_role;
create table storage.buckets(id text primary key,name text,public boolean default false,file_size_limit bigint,allowed_mime_types text[]);
create table storage.objects(id uuid primary key default gen_random_uuid(),bucket_id text references storage.buckets(id),name text,metadata jsonb,unique(bucket_id,name));
alter table storage.objects enable row level security;
grant select,insert,update,delete on storage.objects to anon,authenticated;
