# 태그 자동 추천 — 테스트 내용과 결과

> 기준: 팀 PR #20 브랜치 `d4a06e3` · 실행일 2026-11-20, 2026-11-23(태그 저장 규칙·마이그레이션 추가분) · macOS, 로컬 PostgreSQL

## 요약

| 구분 | 결과 |
| --- | --- |
| 백엔드 정적 검사·단위 테스트 | 통과 (16개) |
| 프론트엔드 lint·build | 통과 |
| 태그 추천 API | 통과 (6가지 경우) |
| 태그 저장 규칙 API | 통과 (12가지 경우) |
| 기존 글 이관 마이그레이션 | 통과 |
| 글쓰기 화면 (브라우저) | 통과 |
| 키워드 매칭 정확도 (샘플 12개) | 정밀도 93%, 재현율 81% |
| `callJev()` (가짜 Jev 서버) | 통과 (6가지 경우) |
| **실제 Jev 비교** | **미실시** — 받은 키가 401 인증 실패 |
| 레포 내 비밀 값 | 없음 |
| 팀 레포 반영 가능 여부 | 충돌 없음. Docker 빌드는 미확인 |

## 1. 백엔드 (`api/`)

| 명령 | 결과 |
| --- | --- |
| `cargo fmt --check` | 통과 |
| `cargo clippy --all-targets` | 경고 1개. 이번 변경 전부터 있던 `src/services/users.rs:48` (`nonminimal_bool`) |
| `cargo test` | 16개 통과 |

태그 추천 관련 단위 테스트:

| 테스트 | 확인 내용 |
| --- | --- |
| `ascii_keywords_respect_word_boundaries` | `go` 가 `google`·`my_go_var` 에 걸리지 않음, `c++` 매칭 |
| `korean_keywords_match_with_particles` | `리액트를`, `리액트로` 모두 매칭 |
| `title_weighs_more_and_results_are_sorted` | 제목 가중치 3, 점수순 정렬, 점수 0.6 |
| `excluded_and_unmatched_tags_are_left_out` | 이미 입력한 태그 제외 |
| `code_blocks_images_and_urls_are_ignored` | 코드 블록·이미지·링크 URL·맨 URL 제거 |
| `services::tag_vocabulary::tests` | 동의어 정규화·중복 제거, 개수·길이 제한 |
| `aliases_are_replaced_with_canonical_names_without_duplicates` | `리액트, backend, react, golang` → `react, backend, go` (변환 후 중복 제거, 순서 유지) |

## 2. 프론트엔드 (`frontend/`)

| 명령 | 결과 |
| --- | --- |
| `npm run lint` | 오류 없음 |
| `npm run build` | 성공 (500kB 넘는 청크 경고만 있음) |
| `npm ci` (Docker 빌드와 같은 방식) | 설치 성공 |

## 3. 태그 추천 API (`POST /api/tags/suggestions`)

로컬 서버 + 샘플 태그 15개 상태에서 직접 호출했다.

| 제목 / 본문 | 응답 | 판정 |
| --- | --- | --- |
| React 대신 Svelte 를 고른 이유 / SvelteKit 을 골랐다. React 와 비교하면 | `react`, `svelte` | 동작은 정상. `react` 는 키워드 방식의 알려진 오답 |
| 주간 스터디 일정 공지 / 수요일 8시 | `기타` | 통과 |
| 주말 잡담 / docker 공부 | `기타`, `docker` | 통과 |
| 오늘 점심 / 산책했다 | `[]` | 통과 (동의어 없음) |
| (빈 제목) / (빈 본문) | 400 | 통과 |
| 로그인 없이 호출 | 401 | 통과 |

## 3-1. 태그 저장 규칙 (`POST`/`PATCH /api/posts`)

로컬 서버에서 시험 계정으로 글을 쓰고 고친 뒤 결과를 확인했다. 시험 글과 시험용 목록 항목은 끝나고 지웠다.

| 경우 | 입력 태그 | 저장된 태그 / 결과 | 판정 |
| --- | --- | --- | --- |
| 정규화 + 동의어 + 중복 | `#React, 리액트, Golang, BRAND-NEW-T1, 스터디, " docker "` | `react, go, brand-new-t1, 기타, docker` | 통과 |
| 새 태그 목록 추가 | 위 글 | `brand-new-t1` 이 목록에 생김 | 통과 |
| 동의어 이름은 목록에 안 생김 | 위 글 | `리액트`·`golang`·`스터디` 항목 없음 | 통과 |
| 두 태그에 걸친 동의어 | `jsx` (react 와 시험용 태그 둘 다의 동의어) | `jsx` 그대로, 목록에도 안 생김 | 통과 |
| 태그 이름 우선 | `TS` (`ts` 를 목록 태그로 추가한 상태, typescript 의 동의어이기도 함) | `ts` 그대로 | 통과 |
| 수정에도 같은 규칙 | `파이썬, #Python, golang` | `python, go` | 통과 |
| 권한 | 일반 사용자의 태그 목록 조회 | 403 | 통과 |

## 3-2. 기존 글 이관 마이그레이션

새 마이그레이션 2개를 적용하기 전에, 동의어 태그가 붙은 시험 글 3개를 DB 에 직접 넣었다. 그 뒤 서버를 띄워 결과를 확인했다.

| 글 | 이관 전 | 이관 후 |
| --- | --- | --- |
| A | `리액트, react` | `react` (하나로 합쳐짐) |
| B | `golang, newtag-mig` | `go, newtag-mig` |
| C | `스터디, docker` | `기타, docker` |

- `_sqlx_migrations` 에 `20261122000000`, `20261122100000` 이 기록되고, 서버가 정상 기동했다.
- 새 태그 `newtag-mig` 는 목록에 담겼고, 동의어(`리액트`·`golang`·`스터디`)는 목록에 따로 생기지 않았다.

## 4. 글쓰기 화면 (브라우저, 테스트 계정 `tagtester`)

| 입력 | 화면 | 판정 |
| --- | --- | --- |
| s02 React 대신 Svelte | `+ react`, `+ svelte` | 동작 정상 |
| `+ svelte` 칩 클릭 | 입력란에 `svelte` 추가, 칩 사라짐 | 통과 |
| s12 주간 스터디 일정 공지 | `+ 기타` (`기타` 등록 전에는 "추천할 태그가 없습니다") | 통과 |
| s06 1GB 서버에서 Rust 빌드 | `+ rust`, `+ ci-cd`, `+ docker` | 통과 |
| 주말 잡담 / 주말에 docker 공부하다가 쉬었다. | `+ 기타`, `+ docker` | 통과 |
| 오늘 점심 / 날씨가 좋아서 산책했다. | "추천할 태그가 없습니다" | 통과 |
| 태그 입력란에 `#React, 리액트, Golang, react,  ,#Docker` 입력 후 벗어나기 | `react, 리액트, golang, docker` 로 바뀜 (동의어 변환은 서버에서) | 통과 |
| 위 태그를 입력한 채 "주말에 docker 공부하고 리액트 잡담." 으로 추천 | `+ 기타` 만 뜸 (이미 입력한 `react`·`docker` 는 빠짐) | 통과 |

- 추천 요청은 모두 200 이었다.
- 콘솔 오류는 로그인 전의 `/api/auth/me` 401 과 로그인 실패 400 뿐이었다. 추천 기능과는 관계없다.
- 화면 시험 중 게시물은 올리지 않았다.

## 5. 키워드 매칭 정확도 (`node eval.mjs run`)

샘플 글 12개(`sample-posts.json`). `기타` 는 비교에서 뺀다.

| 방식 | 정밀도 | 재현율 | 태그 없어야 할 글(s11·s12) |
| --- | --- | --- | --- |
| 키워드 매칭 | 93% (13/14) | 81% (13/16) | 2/2 비추천 |

| 글 | 정답 | 키워드 매칭 | 비고 |
| --- | --- | --- | --- |
| s01 useEffect 의존성 배열 정리 | react | react | |
| s02 React 대신 Svelte | svelte | react, svelte | 문맥 오답 |
| s03 axum 에러 처리 | rust, axum | axum, rust | |
| s04 고루틴 누수 찾기 | go, performance | go | performance 놓침 |
| s05 Postgres 인덱스 | postgresql, performance | postgresql | performance 놓침 |
| s06 Rust 빌드 멈춤 | ci-cd, docker, rust | rust, ci-cd, docker | |
| s07 이분 탐색 풀이 | algorithm | algorithm | |
| s08 마크다운 XSS | security, react | security | react 놓침 |
| s09 프로젝트 회고 | retrospective | retrospective | |
| s10 tsconfig strict | typescript | typescript | |
| s11 코드 블록에만 나오는 단어 | (없음) | (없음) | 코드 블록 무시 확인 |
| s12 주간 스터디 일정 공지 | (없음) | (없음) | |

## 6. `callJev()` — 가짜 Jev 서버 시험

유효한 키가 없어서, 공식 OpenAPI 명세(`https://api.typesafe.ai/openapi.json`)로 요청을 검사하는 가짜 서버를 로컬에 띄워 시험했다.

- 가짜 서버는 정답 태그에 0.9, 아니면 0.1 을 준다.
- 기준 확률 필터를 확인하려고 오답 `docker` 에만 0.55 를 준다.

| 경우 | 결과 | 확인한 것 |
| --- | --- | --- |
| 정상, 기준 0.5 | 정밀도 59%, 재현율 100%, s11·s12 0/2 | 0.55 가 통과됨 → 필터가 값대로 동작 |
| 정상, 기준 0.6 / 0.7 | 정밀도·재현율 100%, s11·s12 2/2 | 응답 → 태그 변환이 맞음 |
| 401 응답 | 실패 12, 멈추지 않음 | 오류 처리 |
| 3초 지연, 제한 1초 | 약 1002ms 에 중단, 실패 12 | `signal` 타임아웃 |
| 답 일부 누락 | 재현율 56%, 실패 0 | **약점**: 빠진 답이 오류로 잡히지 않음 |
| 요청 형식 (모든 경우) | 12개 요청 모두 스키마 오류 0 | `model`, `state{title, body}`, Noul 질문 14개, Bearer 헤더 |

추가로 확인한 것:

- 본문에서 코드 블록·URL 이 빠진 채 전송된다.
- 리포트·로그에 키 값이 남지 않는다.
- 요청당 질문은 14개다. 목록은 15개지만 `기타` 가 후보에서 빠진다.

## 7. 실제 Jev 시험 — 미실시

- 받은 키(111자)로 호출했을 때 `401 authentication_error` 가 났다.
- 엔드포인트와 `Bearer` 형식은 맞다 (서버까지 도달해 인증 단계에서 거부됨).
- 다시 하는 방법:
  1. TypeSafe 콘솔에서 키를 확인한다.
  2. `JEV_API_KEY` 를 설정한다.
  3. `JEV_THRESHOLD` 를 0.5 / 0.6 / 0.7 로 바꿔 가며 `node eval.mjs run` 을 실행한다.
- 확인할 것:
  - s02·s04·s05·s08 을 맞히는가.
  - s11·s12 에 엉뚱한 태그를 붙이지 않는가.
  - 평균 응답 시간이 3초 이내인가.

## 8. 보안·배포 점검

| 항목 | 결과 |
| --- | --- |
| 커밋된 `.env` | 없음 (`.env.example` 두 개만) |
| 커밋 기록 속 키·비밀번호 | 없음 (지운 README 의 안내 문구 예시뿐) |
| `api/.env`, `tools/jev-eval/results/` | `.gitignore` 로 제외 |
| 팀 레포 main 대비 | 팀에만 있는 커밋 0개. PR #20 은 팀 main 위에 일렬로 쌓은 12커밋(머지 커밋 없음) → 충돌 없음, 머지 가능 |
| 마이그레이션 | 새 파일 3개(`20261120100000`, `20261122000000`, `20261122100000`), 기존 파일 수정 없음. 팀 PR #18 의 `20261120000000` 과 겹치지 않음 |
| 의존성·환경 변수 | 변경 없음 |
| `cargo build --release --locked` (macOS) | 실패. 이 맥에서 `libsqlx_macros` 를 불러오지 못함 (`mis-aligned LINKEDIT`). 우리 코드 컴파일 전 단계이고 의존성이 팀과 같아, 이 맥 환경 문제로 판단. 팀 CI(리눅스 Docker) 결과로 최종 확인 필요 |
