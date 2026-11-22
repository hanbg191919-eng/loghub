-- 이미 게시물에 쓰인 태그를 태그 추천 목록에 담는다 (1회성 데이터 이관).
-- 이후 새 태그는 게시물 저장 시 services/posts.rs 에서 자동으로 목록에 추가된다.
-- 다른 태그의 동의어로 등록된 이름은 따로 항목을 만들지 않는다 (예: react 의 동의어 "리액트").
INSERT INTO tag_vocabulary (name)
SELECT DISTINCT t.name
FROM tags t
JOIN post_tags pt ON pt.tag_id = t.id
WHERE NOT EXISTS (SELECT 1 FROM tag_aliases a WHERE a.alias = t.name)
ON CONFLICT (name) DO NOTHING;
