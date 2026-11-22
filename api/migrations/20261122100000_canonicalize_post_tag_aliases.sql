-- 기존 게시물의 태그 중 태그 추천 목록에 동의어로 등록된 것을 대표 태그로 바꾼다 (1회성 데이터 이관).
-- 예: 리액트 → react, golang → go. 한 글에 동의어와 대표 태그가 같이 있으면 하나로 합쳐진다.
-- 규칙은 게시물 저장 시의 services/tag_vocabulary.rs::canonicalize 와 같다.
--   - 그 이름 자체가 목록의 태그이면 바꾸지 않는다 (태그 이름 우선)
--   - 같은 동의어가 둘 이상의 태그에 있으면 바꾸지 않는다 (어느 쪽인지 정할 수 없음)
-- 팀원 참고: 이 마이그레이션 이후에 추가한 동의어는 그 뒤에 저장되는 글부터 적용된다.
-- 동의어가 붙어 있던 tags 행은 지우지 않는다 (게시물이 0개인 태그는 GET /api/tags 에 나오지 않는다).

CREATE TEMP TABLE alias_to_canonical ON COMMIT DROP AS
SELECT a.alias AS alias, min(v.name) AS canonical
FROM tag_aliases a
JOIN tag_vocabulary v ON v.id = a.vocabulary_id
WHERE NOT EXISTS (SELECT 1 FROM tag_vocabulary v2 WHERE v2.name = a.alias)
GROUP BY a.alias
HAVING count(*) = 1;

-- 1. 대표 태그가 tags 에 아직 없으면 만든다
INSERT INTO tags (name)
SELECT DISTINCT m.canonical
FROM alias_to_canonical m
JOIN tags t ON t.name = m.alias
JOIN post_tags pt ON pt.tag_id = t.id
ON CONFLICT (name) DO NOTHING;

-- 2. 동의어 태그가 붙은 글에 대표 태그를 붙인다 (이미 있으면 그대로)
INSERT INTO post_tags (post_id, tag_id)
SELECT pt.post_id, c.id
FROM post_tags pt
JOIN tags t ON t.id = pt.tag_id
JOIN alias_to_canonical m ON m.alias = t.name
JOIN tags c ON c.name = m.canonical
ON CONFLICT DO NOTHING;

-- 3. 동의어 태그 연결을 지운다
DELETE FROM post_tags pt
USING tags t, alias_to_canonical m
WHERE pt.tag_id = t.id AND t.name = m.alias;
