-- Extensions required by the schema. Supabase Postgres images ship with
-- pgcrypto available already in most cases; declared explicitly here so
-- the migration is reproducible on any Postgres 17 instance.
create extension if not exists pgcrypto;
create extension if not exists "uuid-ossp";
