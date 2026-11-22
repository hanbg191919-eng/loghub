// sqlx::migrate! 는 컴파일 시점에 migrations/ 를 바이너리에 넣는다.
// 팀원 참고: 이 파일이 없으면 마이그레이션 SQL 만 추가된 경우 cargo 가 다시 빌드하지 않아
// `cargo run` 해도 새 마이그레이션이 적용되지 않는다 (sqlx 공식 권장 설정).
fn main() {
    println!("cargo:rerun-if-changed=migrations");
}
