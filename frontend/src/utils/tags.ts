/**
 * 태그 한 개 정규화: 앞뒤 공백·선행 `#` 제거, 소문자.
 * 팀원 참고: 백엔드 `services/tags.rs::normalize_tag` 와 같은 규칙이다. 바꿀 때 둘 다 수정한다.
 */
export function normalizeTag(raw: string) {
  return raw.trim().replace(/^#+/, '').trim().toLowerCase()
}

/** 쉼표로 구분한 태그 입력을 정규화된 배열로 (빈 값·중복 제거, 입력 순서 유지) */
export function parseTags(input: string) {
  const seen = new Set<string>()
  for (const raw of input.split(',')) {
    const tag = normalizeTag(raw)
    if (tag) seen.add(tag)
  }
  return [...seen]
}
