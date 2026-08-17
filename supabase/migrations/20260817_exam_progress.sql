-- exam_progress: 試験の途中経過をユーザーごとに保存（再開機能用）
create table if not exists public.exam_progress (
  user_id uuid primary key references auth.users(id) on delete cascade,
  section text not null default 'all',
  question_ids jsonb not null,
  current_index int not null default 0,
  score int not null default 0,
  updated_at timestamptz not null default now()
);

alter table public.exam_progress enable row level security;

drop policy if exists "Users can select own progress" on public.exam_progress;
create policy "Users can select own progress"
  on public.exam_progress for select
  using (auth.uid() = user_id);

drop policy if exists "Users can insert own progress" on public.exam_progress;
create policy "Users can insert own progress"
  on public.exam_progress for insert
  with check (auth.uid() = user_id);

drop policy if exists "Users can update own progress" on public.exam_progress;
create policy "Users can update own progress"
  on public.exam_progress for update
  using (auth.uid() = user_id);

drop policy if exists "Users can delete own progress" on public.exam_progress;
create policy "Users can delete own progress"
  on public.exam_progress for delete
  using (auth.uid() = user_id);
