-- exam_progress に回答済み問題IDを記録する列を追加
-- 背景: 中断→再開時に「回答済みの境界問題」が再回答されスコアが二重加算される
--       （例: 50問中最後の問題を回答後に中断→再開で再回答→51/50）ことを防ぐ
alter table public.exam_progress add column if not exists answered_ids jsonb not null default '[]'::jsonb;

-- 既存の進行中データのバックフィル: 現在位置の問題は回答済みとして扱う
update public.exam_progress
set answered_ids = coalesce(jsonb_build_array(question_ids -> current_index), '[]'::jsonb)
where (question_ids -> current_index) is not null;
