# 태그 자동 추천 — 코드 소개

> 팀 레포 `log-dev-club/loghub` main(`1f409a1`) 대비 변경 34개 파일 (PR #20, `d4a06e3`) · 작성일 2026-11-20 · 갱신 2026-11-23

## 전체 흐름

```
[관리자] AdminPage ─ TagVocabularyManager ─▶ /api/admin/tag-vocabulary ─▶ tag_vocabulary 서비스 ─▶ tag_vocabulary, tag_aliases 테이블
                                                                                                          │
[작성자] WritePage ─ 태그 추천 버튼 ─▶ POST /api/tags/suggestions ─▶ tag_suggest 서비스 ─ all_terms() ◀────┘
                    ◀─ { tags: [{ name, score }], source: "keyword" } ─┘

[작성자] WritePage ─ 게시하기 ─▶ POST/PATCH /api/posts ─▶ posts::set_tags
                                    ├─ normalize_tags            정규화·중복 제거
                                    ├─ tag_vocabulary::canonicalize   동의어 → 대표 태그
                                    └─ tag_vocabulary::add_missing    새 태그 → 목록 자동 추가

[개발자] tools/jev-eval/eval.mjs ─▶ 위 추천 API + Jev(api.typesafe.ai) 를 같은 샘플 글로 비교 → results/report-*.md
```

## 파일 구조

### DB

| 파일 | 내용 |
| --- | --- |
| `api/migrations/20261120100000_add_tag_vocabulary.sql` (팀 PR #18 과 버전이 겹치지 않도록 번호 조정) | `tag_vocabulary`(id, name UNIQUE, description, created_at, updated_at), `tag_aliases`(vocabulary_id, alias, PK 둘, `ON DELETE CASCADE`) |
| `api/migrations/20261122000000_backfill_tag_vocabulary_from_posts.sql` | 기존 게시물에 쓰인 태그를 목록에 한 번 담는다. 다른 태그의 동의어인 이름은 뺀다 |
| `api/migrations/20261122100000_canonicalize_post_tag_aliases.sql` | 기존 게시물의 동의어 태그를 대표 태그로 바꾼다 (아래 "기존 글 이관" 참고) |
| `api/build.rs` | `cargo:rerun-if-changed=migrations`. `sqlx::migrate!` 가 컴파일 때 SQL 을 넣으므로, SQL 만 추가돼도 다시 빌드되게 한다. Dockerfile 에 `COPY build.rs ./` 추가 |

`tag_vocabulary` 는 게시물 태그(`tags`, `post_tags`)와 **외래 키로 연결하지 않는다**. 목록에서 지워도 게시물 태그는 남는다.
대신 게시물을 저장할 때 서비스 코드가 목록을 읽어 동의어를 바꾸고, 새 태그를 목록에 넣는다.

### 백엔드 (`api/src`) — CLAUDE.md 의 `models → services → handlers → routes` 구조를 따름

| 파일 | 역할 |
| --- | --- |
| `models/tag_vocabulary.rs` | `TagVocabulary` (응답), `CreateTagVocabularyRequest`, `UpdateTagVocabularyRequest` |
| `models/tag.rs` | `SuggestTagsRequest { title, content, exclude }`, `TagSuggestion { name, score }`, `TagSuggestionResponse { tags, source }` |
| `services/tags.rs` | `TAG_MAX_LEN`(50), `normalize_tag()` 를 공용으로 옮김. 게시물 태그와 태그 목록이 같은 정규화 규칙을 쓴다 |
| `services/posts.rs` | 위 공용 함수를 쓰도록 바꿈. `set_tags` 에서 `canonicalize` → 태그 저장 → `add_missing` 순으로 호출 (게시물 저장과 같은 트랜잭션) |
| `services/tag_vocabulary.rs` | 목록 CRUD, 입력 검증, 관리자 권한 검사, 추천용 `all_terms()`, 저장용 `canonicalize()`·`add_missing()` |
| `services/tag_suggest.rs` | 키워드 매칭 추천 (`suggest`, `strip_markdown_noise`, `rank`, `count_matches`) |
| `handlers/tag_vocabulary.rs`, `handlers/tags.rs` | 요청 파싱 → 서비스 호출 → 응답. 둘 다 `CurrentUser` 로 로그인 필수 |
| `routes/tag_vocabulary.rs`, `routes/tags.rs` | 경로 등록 (아래 표) |

| 메서드 | 경로 | 권한 | 핸들러 |
| --- | --- | --- | --- |
| GET / POST | `/api/admin/tag-vocabulary` | 관리자 | `list` / `create` (201) |
| PATCH / DELETE | `/api/admin/tag-vocabulary/{id}` | 관리자 | `update` / `delete` (204) |
| POST | `/api/tags/suggestions` | 로그인 | `suggest` |

### 프론트엔드 (`frontend/src`)

| 파일 | 역할 |
| --- | --- |
| `types.ts` | `TagVocabulary`, `TagSuggestion`, `TagSuggestionResponse` 타입 (백엔드 DTO 와 필드명 일치) |
| `api/tagVocabulary.ts` | 목록 조회·추가·수정·삭제 fetch 래퍼 |
| `api/tags.ts` | `suggestTags()` 추가 |
| `components/TagVocabularyManager.tsx` (+ `.css`) | 관리자 화면의 태그 목록 영역 (추가 폼, 목록, 수정·삭제, 후보 칩) |
| `pages/AdminPage.tsx` | `<TagVocabularyManager />` 를 붙임 |
| `pages/WritePage.tsx` (+ `.css`) | 태그 추천 버튼, 추천 칩, 안내 문구, 태그 입력란을 벗어날 때 정규화 |
| `utils/tags.ts` | `normalizeTag()`, `parseTags()`. 백엔드 `normalize_tag` 와 같은 규칙 (바꿀 때 둘 다 수정) |

### 시험 도구 (`tools/jev-eval`)

| 파일 | 역할 |
| --- | --- |
| `eval.mjs` | `seed`, `run` 명령. Node 22+, 의존성 없음 |
| `sample-vocabulary.json` | 샘플 태그 15개 (설명, 동의어. `기타` 포함) |
| `sample-posts.json` | 샘플 글 12개와 사람이 정한 정답 태그(`expected`) |
| `results/` | 리포트 출력 위치. `.gitignore` 로 커밋 제외 |

## 핵심 코드 설명

### 1. 태그 목록 서비스 — `services/tag_vocabulary.rs`

- **권한**: 모든 변경 함수가 처음에 `ensure_admin(actor)` 를 부른다. 관리자가 아니면 `AppError::Forbidden`(403). 미들웨어가 아니라 서비스에서 검사한다 (CLAUDE.md 규칙).
- **검증**:
  - `validate_name`: 비면 400, 50자 초과면 400.
  - `validate_description`: 200자 초과면 400.
  - `normalize_aliases`: 정규화 → 빈 값·이름과 같은 값 제거 → 중복 제거 → 30개 초과면 400.
- **추가(`create`)**: 트랜잭션 안에서 `INSERT ... ON CONFLICT (name) DO NOTHING RETURNING id`. 이미 있으면 409. 이어서 `replace_aliases` 로 동의어를 넣는다.
- **수정(`update`)**: `SELECT ... FOR UPDATE` 로 잠그고 보낸 필드만 바꾼다. 동의어를 보내면 전체 교체한다.
- **조회 쿼리**: `array_agg(a.alias) FILTER (WHERE a.alias IS NOT NULL)` 로 동의어를 배열로 묶는다. 동의어가 없으면 빈 배열이 된다.
- **`all_terms()`**: 추천용으로 `(이름, 동의어 목록)` 만 가져온다. 로그인한 누구나 추천을 받으므로 권한 검사는 없다.
- **`canonicalize(tx, tags)`**: 게시물 저장 중에 동의어를 대표 태그로 바꾼다.
  - SQL 로 `동의어 → 대표 태그` 쌍을 고른다. 이때 조건이 둘 있다.
    - 그 동의어가 목록의 태그 이름이 아니어야 한다 (`NOT EXISTS ... v2.name = a.alias`).
    - 그 동의어가 한 태그에만 있어야 한다 (`HAVING count(*) = 1`).
  - `apply_aliases` 가 바꾸면서 중복을 빼고 입력 순서를 유지한다. DB 없이 단위 테스트할 수 있게 따로 분리했다.
- **`add_missing(tx, tags)`**: 목록에 없는 태그를 `INSERT ... SELECT unnest($1) ... ON CONFLICT DO NOTHING` 으로 한 번에 넣는다. 다른 태그의 동의어인 이름은 넣지 않는다.
  - 둘 다 게시물 저장과 같은 트랜잭션 안에서 돌기 때문에, 글 저장이 실패하면 목록 변경도 함께 취소된다.

### 2. 키워드 매칭 — `services/tag_suggest.rs`

```
suggest(pool, req)
 ├─ 제목·본문 둘 다 비면 400
 ├─ all_terms()                         태그 목록 전체
 ├─ title: 200자, 소문자
 ├─ body : strip_markdown_noise → 2,000자 → 소문자
 ├─ exclude: normalize_tag 로 정규화
 └─ rank(terms, title, body, exclude) → { tags, source: "keyword" }
```

- **`strip_markdown_noise`**: 매칭을 방해하는 마크다운 요소를 지운다.
  - ```` ``` ```` / `~~~` 사이 코드 블록을 줄 단위로 건너뛴다.
  - 정규식으로 이미지 `![..](..)` 를 지운다.
  - 링크 `[텍스트](url)` 는 텍스트만 남긴다.
  - 맨 URL 을 지운다.
- **`rank`**:
  - 태그마다 `Σ(3 × 제목 등장 수 + 본문 등장 수)` 를 이름과 모든 동의어에 대해 더한다.
  - 0점은 버리고, 점수 내림차순(같으면 이름순)으로 상위 5개를 고른다.
  - `normalize_score(raw) = raw / (raw + 2)` 로 0~1 로 바꾼다. 1회 0.33, 2회 0.5, 6회 0.75.
- **`count_matches`**:
  - ASCII 키워드는 앞뒤 글자가 영문·숫자·`_` 가 아닐 때만 센다 (`go` ≠ `google`, `my_go_var`).
  - 한글이 섞인 키워드는 조사가 바로 붙으므로 부분 일치로 센다.

### 3. 기존 글 이관 — `20261122100000_canonicalize_post_tag_aliases.sql`

`canonicalize` 와 같은 규칙을 이미 저장된 글에 한 번 적용한다.

1. `alias_to_canonical` 임시 테이블에 `동의어 → 대표 태그` 쌍을 만든다. 조건은 `canonicalize` 와 같다.
2. 대표 태그가 `tags` 에 없으면 만든다.
3. 동의어 태그가 붙은 글에 대표 태그를 붙인다. 이미 붙어 있으면 `ON CONFLICT DO NOTHING` 이라 중복이 생기지 않는다.
4. 동의어 태그 연결(`post_tags`)을 지운다. `tags` 행 자체는 남지만, 게시물이 0개라 `GET /api/tags` 에는 나오지 않는다.

### 4. 글쓰기 화면 — `pages/WritePage.tsx`

- `normalizeTagsInput` (태그 입력란 `onBlur`): `parseTags` 로 정규화한 결과가 입력과 다르면 입력란을 바꾼다. 동의어 변환은 서버에서만 한다.
- `handleSuggestTags`:
  - 버튼을 누를 때만 호출한다 (입력할 때마다 자동으로 부르지 않음).
  - 입력란의 태그를 `exclude` 로 보낸다.
  - 결과가 0개면 "추천할 태그가 없습니다", 429 면 "잠시 후 다시 시도해 주세요" 를 보여 준다.
- `addSuggestedTag`: 칩을 누르면 입력란 끝에 `, 태그` 를 붙이고 그 칩을 목록에서 뺀다.
- `visibleSuggestions`: 사용자가 그새 직접 입력한 태그와 겹치는 추천은 숨긴다.
- 버튼은 제목과 본문이 모두 비었거나 요청 중일 때 꺼진다.

### 5. 관리자 화면 — `components/TagVocabularyManager.tsx`

- 처음에 `fetchTagVocabulary()`(목록)와 `fetchTags()`(사용 중인 태그)를 부른다. 후보용 `fetchTags` 가 실패해도 관리 기능은 그대로 동작한다.
- `candidates`: 사용 중인 태그 중 **목록의 이름이나 동의어에 없는 것**을 게시물 수 순으로 보여 준다.
- `run(action)`: 요청 중 버튼을 잠그고, 오류를 화면에 표시하는 공통 래퍼.
- 삭제할 때 "기존 게시물의 태그는 그대로 남습니다" 확인창을 띄운다.

### 6. 시험 도구 — `tools/jev-eval/eval.mjs`

| 구역 | 내용 |
| --- | --- |
| 설정 | 환경 변수 `JEV_API_KEY`, `JEV_API_URL`(기본 공식 주소), `JEV_MODEL`(기본 `jev-latest`), `JEV_THRESHOLD`(기본 0.6), `JEV_TIMEOUT_MS`(기본 5000), `LOGHUB_URL`, `LOGHUB_ADMIN_NICKNAME`, `LOGHUB_ADMIN_PASSWORD`. 상수 `MISC_TAG = '기타'` |
| `callJev()` | 후보 태그마다 Noul(예/아니오) 질문을 만들어 **한 요청**에 담는다 (`t0`, `t1`…). `answers.tN.noul` 확률을 `{ name, score }` 로 바꿔 돌려준다. 200 이 아니면 예외 (응답 본문만 담고 키는 담지 않음) |
| 전처리 | `stripMarkdownNoise`, `takeChars`. 서버의 `tag_suggest.rs` 와 같은 규칙 |
| `seed()` | `sample-vocabulary.json` 을 `POST /api/admin/tag-vocabulary` 로 등록. 409 는 "이미 있음" |
| `run()` | 글마다 키워드 추천 API 를 호출하고, 키가 있으면 `callJev()` 도 호출한다. Jev 결과는 목록 안 이름만, 기준 확률 이상만, 높은 순 5개. 오류가 나면 그 글을 "실패" 로 세고 계속 진행 |
| 리포트 | `score`/`summarize` 가 정밀도(추천 중 정답 비율), 재현율(정답 중 추천 비율), 태그 없어야 할 글(s11·s12)의 비추천 수를 계산. `buildReport` 가 마크다운 표로 저장 |

`기타` 처리:
- `기타` 는 동의어로만 붙는 일반 태그다.
- 시험 목적이 기술 주제 태그 비교라서 Jev 후보와 키워드 결과 양쪽에서 `MISC_TAG` 를 뺀다.
- 빼지 않으면 s12 "주간 스터디 일정 공지" 에 붙는 `기타` 가 오답으로 세진다.

## 4단계(Jev 연동)로 갈 때 바꿀 곳

| 할 일 | 위치 |
| --- | --- |
| `callJev` 를 Rust 로 옮기고, 실패·타임아웃 시 지금의 `rank()` 로 대체. 응답 `source: "jev"` | `api/src/services/tag_suggest.rs` |
| `JEV_API_KEY`, `JEV_API_URL` 읽기 | `api/src/config.rs` + `api/.env.example` (키 이름만) |
| HTTP 클라이언트 | `AppState.http` (reqwest) 재사용 |
| 요청 횟수 제한 | `routes/tags.rs` 의 `/api/tags/suggestions` 를 `rate_limit::limit_per_ip` 로 감싸기 |
| 외부 전송 안내 문구 | `WritePage.tsx` 추천 버튼 옆 (`source === 'jev'` 일 때) |
