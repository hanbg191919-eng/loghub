# 태그 추천 3단계 인수인계 — Jev 로컬 시험

> 기획서: [태그 자동 추천 기획서](https://claude.ai/artifact/WkAJu4twLuKqXipeWwKnQB) · PR: hanbg191919-eng/loghub#1
> 작성일: 2026-11-20

## 한 줄 요약

1·2단계(태그 목록 관리, 키워드 매칭 추천)는 끝났다. 3단계는 **샘플 글로 키워드 매칭과 Jev 를 비교**하는 시험이고,
이 폴더의 `eval.mjs` 에서 **`callJev()` 함수 하나만 채우면** 바로 비교 리포트가 나온다. 앱 코드는 건드리지 않는다.

## 지금 상태

| 단계 | 상태 | 내용 |
| --- | --- | --- |
| 1. 태그 목록 | 완료 (PR #1) | `tag_vocabulary`/`tag_aliases`, `/api/admin/tag-vocabulary`, 관리자 화면 |
| 2. 키워드 매칭 | 완료 (PR #1) | `POST /api/tags/suggestions`, 글쓰기 화면 추천 버튼·칩 |
| 3. Jev 시험 | **진행 대기 — 이 문서** | 샘플 글 12개로 비교. `callJev()` 미구현 |
| 4. Jev 연동 | 시작 전 | 3단계 결과가 키워드 매칭보다 확실히 나을 때만 |

## 꼭 지킬 것

- **실제 팀 게시물은 Jev 로 보내지 않는다.** 외부 전송에 대한 팀 동의가 아직 없다 (기획서 10장).
  이 폴더의 `sample-posts.json` 은 공개해도 되는 샘플 글이다. 실제 글 시험은 동의 후에.
- **API 키는 환경 변수로만** 넘긴다. 코드·커밋·`.env.example` 에 값을 넣지 않는다.
- `results/` 는 `.gitignore` 에 있다. 리포트는 커밋하지 말고, 결론만 기획서에 옮긴다.

## 맥북에서 실행 순서

### 1. 브랜치 받기

```bash
git fetch origin claude/serene-meitner-g9bnh0
```

```bash
git checkout claude/serene-meitner-g9bnh0
```

### 2. 서버 띄우기

`api/.env` 가 이미 있다면 그대로 쓰면 된다. 마이그레이션은 서버가 기동 시 자동 적용한다.

```bash
cd api && cargo run
```

관리자 계정(`admin`) 비밀번호를 모르면: DB 에 최고 관리자가 없을 때 첫 기동 로그에 한 번만 출력된다.
이미 만들어진 DB 라면 기존 비밀번호를 쓴다.

### 3. 샘플 태그 목록 등록 (다른 터미널)

```bash
cd tools/jev-eval
```

```bash
export LOGHUB_ADMIN_PASSWORD='관리자 비밀번호'
```

```bash
node eval.mjs seed
```

`sample-vocabulary.json` 의 태그 14개를 등록한다. 같은 이름이 이미 있으면 건너뛴다 (그 경우 동의어도 기존 것 유지).

### 4. 키워드 매칭만 먼저 돌려 보기

```bash
node eval.mjs run
```

`results/report-<시각>.md` 가 생긴다. 이 환경에서 미리 돌린 결과(깨끗하지 않은 DB 라 동의어가 약간 다름):

| 방식 | 정밀도 | 재현율 | 태그 없어야 할 글에서 비추천 |
| --- | --- | --- | --- |
| 키워드 매칭 | 93% | 81% | 2/2 |

키워드 매칭이 틀리는 지점 — **Jev 가 이겨야 하는 곳**:
- `s02` "React 대신 Svelte" → `react` 를 잘못 추천 (문맥을 모름)
- `s04`, `s05` → 단어로는 안 나오는 `performance` 를 놓침
- `s08` XSS 글 → 마크다운 렌더링 = `react` 연결을 못 함

### 5. Jev 호출 구현 (`callJev`)

`eval.mjs` 의 `callJev()` 만 채운다. 입력·반환 형식은 함수 주석에 있다.

- 입력: 전처리된 `title`, `body` (서버와 같은 방식: 코드 블록·이미지·URL 제거, 본문 2,000자) + `candidates` (`{ name, description }` 목록)
- 반환: `[{ name, score }]` — score 는 0~1 확률. 정렬·5개 제한·기준 확률(0.6) 필터·목록 밖 이름 제거는 호출부가 한다
- `signal` 을 `fetch` 에 넘기면 타임아웃(기본 5초)이 걸린다

공식 문서에서 확인할 것 (제3자 글에서만 본 내용이라 **미확인**):

- [ ] 엔드포인트와 인증 — 제3자 글: `POST https://api.typesafe.ai/v1/systemone`, `Authorization: Bearer`, 모델 `jev-latest`
- [ ] 후보 목록(라벨)을 넘기는 필드 이름과 형식
- [ ] 여러 개를 한 번에 고를 수 있는지 (다중 라벨). 안 되면 후보마다 따로 묻는 방식 → 호출 수 증가를 리포트에 기록
- [ ] 후보 수·입력 길이 제한, 응답에서 확률이 오는 필드
- [ ] 데이터 보관·학습 사용 정책 (기획서 10장 미결 사항)

구현 후:

```bash
export JEV_API_KEY='발급받은 키'
```

```bash
export JEV_API_URL='공식 문서의 엔드포인트'
```

```bash
node eval.mjs run
```

조절 가능한 환경 변수: `JEV_THRESHOLD` (기본 0.6), `JEV_MODEL` (기본 jev-latest), `JEV_API_URL` (기본 https://api.typesafe.ai/v1/systemone), `JEV_TIMEOUT_MS` (기본 5000), `LOGHUB_URL` (기본 http://127.0.0.1:8080), `LOGHUB_ADMIN_NICKNAME` (기본 admin).

### 6. 판단과 기록

리포트의 요약 표로 아래를 판단해 기획서 9장(진행 계획)과 10장(미결 사항)에 적는다.

- 정밀도·재현율이 키워드 매칭보다 **확실히** 높은가 (위 s02·s04·s05·s08 을 맞히는가)
- 태그가 없어야 할 글(s11, s12)에 엉뚱한 태그를 붙이지 않는가
- 평균 응답 시간이 3초 이내인가 (기획서 1장 성공 기준)
- 한국어 본문에서 품질이 충분한가
- 기준 확률 0.6 이 적절한가 (`JEV_THRESHOLD` 를 바꿔 몇 번 돌려 본다)

**확실히 낫다면 4단계(Jev 연동)로**, 아니면 키워드 매칭 + 동의어 보강으로 마무리한다.

## 4단계로 갈 때 참고 (코드 위치)

| 할 일 | 위치 |
| --- | --- |
| Jev 호출 함수 (이 폴더의 `callJev` 를 Rust 로 옮김) | `api/src/services/tag_suggest.rs` — 키 있으면 Jev, 실패·타임아웃 시 지금의 `rank()` 로 대체, `source: "jev"` |
| 환경 변수 `JEV_API_KEY`, `JEV_API_URL` | `api/src/config.rs` + `api/.env.example` (값 없이 키 이름만) |
| HTTP 클라이언트 | `AppState.http` (reqwest) 재사용 |
| 요청 횟수 제한 | `api/src/routes/tags.rs` 의 `/api/tags/suggestions` 를 `rate_limit::limit_per_ip` 로 감싸고, CLAUDE.md 에 "외부 유료 API 호출 엔드포인트" 예외 규칙 추가 |
| 외부 전송 안내 문구 | `frontend/src/pages/WritePage.tsx` 추천 버튼 옆 (`source === 'jev'` 일 때) |
| 문서 | `docs/api.md` 의 `POST /api/tags/suggestions`, CLAUDE.md 환경 변수 표 |

## 파일

| 파일 | 내용 |
| --- | --- |
| `eval.mjs` | `seed` (샘플 태그 등록), `run` (비교 리포트). Node 22, 의존성 없음 |
| `sample-vocabulary.json` | 샘플 태그 14개 + 설명 + 동의어 |
| `sample-posts.json` | 샘플 글 12개 + 사람이 정한 정답 태그(`expected`). 함정 글 포함 (s02 문맥, s11 코드 블록에만 등장, s12 태그 없음) |
| `results/` | 실행 리포트 (git 무시) |
