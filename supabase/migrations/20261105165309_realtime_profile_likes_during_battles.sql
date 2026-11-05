do $$
begin
  if not exists (
    select 1
    from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'profile_likes'
  ) then
    alter publication supabase_realtime add table public.profile_likes;
  end if;
end
$$;
