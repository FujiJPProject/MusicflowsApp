-- 疎通確認用のtestテーブルを作成する
CREATE TABLE IF NOT EXISTS tests (
    id BIGSERIAL PRIMARY KEY,
    name VARCHAR(100) NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE tests IS '疎通確認用のテストテーブル';
COMMENT ON COLUMN tests.id IS 'テストID';
COMMENT ON COLUMN tests.name IS 'テスト名';
COMMENT ON COLUMN tests.created_at IS 'テスト作成日時';