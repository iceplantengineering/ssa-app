-- ============================================================
-- ssa-app: 管理者ダッシュボード用ユーザー情報テーブル追加
-- 2026-08-15
--
-- 内容:
--   1. profiles テーブル新設（email / display_name を auth.users から保持）
--   2. 既存ユーザーのバックフィル
--   3. RLS ポリシー（本人のみ + 管理者は全件）
--   4. handle_new_user トリガー拡張（user_roles + profiles に自動登録）
-- ============================================================

-- ------------------------------------------------------------
-- 1. profiles テーブル作成
-- ------------------------------------------------------------
create table if not exists public.profiles (
  user_id      uuid primary key references auth.users(id) on delete cascade,
  email        text not null,
  display_name text,
  created_at   timestamptz not null default now()
);

comment on table public.profiles is 'ユーザー表示情報（メール・表示名）。auth.users の INSERT 時に自動同期';

-- ------------------------------------------------------------
-- 2. 既存ユーザーのバックフィル（表示名はメールのローカル部）
-- ------------------------------------------------------------
insert into public.profiles (user_id, email, display_name)
select id, email, split_part(email, '@', 1)
from auth.users
on conflict (user_id) do nothing;

-- ------------------------------------------------------------
-- 3. RLS 有効化 + ポリシー
--    SELECT: 自分の行のみ + 管理者は全件（管理者ダッシュボード表示用）
-- ------------------------------------------------------------
alter table public.profiles enable row level security;

drop policy if exists "profiles_select" on public.profiles;
create policy "profiles_select" on public.profiles
  for select
  using (auth.uid() = user_id or public.is_admin());

-- ------------------------------------------------------------
-- 4. handle_new_user トリガー拡張
--    auth.users に INSERT されたら user_roles + profiles に自動登録
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

  insert into public.profiles (user_id, email, display_name)
  values (
    new.id,
    new.email,
    coalesce(nullif(new.raw_user_meta_data ->> 'display_name', ''), split_part(new.email, '@', 1))
  )
  on conflict (user_id) do nothing;

  return new;
end;
$$;
