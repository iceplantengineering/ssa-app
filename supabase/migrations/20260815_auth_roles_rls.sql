-- ============================================================
-- ssa-app: 認証・権限まわり改修マイグレーション
-- 2026-08-15
--
-- 内容:
--   1. user_roles テーブル新設（admin / user ロール管理）
--   2. 既存ユーザーへのロール付与
--   3. scores / user_roles の RLS 有効化とポリシー再設計
--   4. 管理者判定関数 is_admin()（security definer）
--   5. 新規ユーザー自動ロール付与トリガー
-- ============================================================

-- ------------------------------------------------------------
-- 1. user_roles テーブル作成
-- ------------------------------------------------------------
create table if not exists public.user_roles (
  user_id    uuid primary key references auth.users(id) on delete cascade,
  role       text not null check (role in ('admin', 'user')),
  created_at timestamptz not null default now()
);

comment on table public.user_roles is 'アプリケーションロール管理（admin: 管理者 / user: 一般ユーザー）';

-- ------------------------------------------------------------
-- 2. 既存ユーザーへのロール付与（2026-08-15 時点の登録3名）
-- ------------------------------------------------------------
insert into public.user_roles (user_id, role)
values
  ('581e8328-279d-45c8-8b93-28fba8f559c7', 'admin'), -- iceplantengineering@gmail.com（管理者）
  ('6912be8c-1ece-43cf-a8c8-c42cea18de94', 'user'),  -- y-furuhashi@icej.co.jp
  ('180b4477-e1b3-4f9e-8ee4-2946c1bbcad0', 'user')   -- j-yamamoto@icej.co.jp
on conflict (user_id) do nothing;

-- ------------------------------------------------------------
-- 3. RLS 有効化
-- ------------------------------------------------------------
alter table public.scores     enable row level security;
alter table public.user_roles enable row level security;

-- ------------------------------------------------------------
-- 4. 管理者判定関数（security definer で RLS をバイパスしてロール参照）
-- ------------------------------------------------------------
create or replace function public.is_admin()
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.user_roles
    where user_id = auth.uid() and role = 'admin'
  );
$$;

-- ------------------------------------------------------------
-- 5. scores の RLS ポリシー再設計
--    SELECT: 自分の行のみ + 管理者は全件
--    INSERT: 自分の user_id のみ
--    UPDATE: 自分の行のみ + 管理者は全件
--    DELETE: 自分の行のみ + 管理者は全件
-- ------------------------------------------------------------
drop policy if exists "scores_select" on public.scores;
drop policy if exists "scores_insert" on public.scores;
drop policy if exists "scores_update" on public.scores;
drop policy if exists "scores_delete" on public.scores;
-- 旧ポリシー（既存）の削除
drop policy if exists "Anyone can view scores" on public.scores;
drop policy if exists "Users can insert own scores" on public.scores;

create policy "scores_select" on public.scores
  for select
  using (auth.uid() = user_id or public.is_admin());

drop policy if exists "scores_insert" on public.scores;
create policy "scores_insert" on public.scores
  for insert
  with check (auth.uid() = user_id);

drop policy if exists "scores_update" on public.scores;
create policy "scores_update" on public.scores
  for update
  using (auth.uid() = user_id or public.is_admin());

drop policy if exists "scores_delete" on public.scores;
create policy "scores_delete" on public.scores
  for delete
  using (auth.uid() = user_id or public.is_admin());

-- ------------------------------------------------------------
-- 6. user_roles の RLS ポリシー
--    SELECT: 自分のロールのみ参照可 + 管理者は全件
--    （管理者ダッシュボードのユーザー一覧表示用）
-- ------------------------------------------------------------
drop policy if exists "user_roles_select" on public.user_roles;
create policy "user_roles_select" on public.user_roles
  for select
  using (auth.uid() = user_id or public.is_admin());

-- ------------------------------------------------------------
-- 7. 新規ユーザー自動ロール付与トリガー
--    auth.users に INSERT されたら user_roles に 'user' を自動追加
-- ------------------------------------------------------------
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.user_roles (user_id, role)
  values (new.id, 'user')
  on conflict (user_id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();
