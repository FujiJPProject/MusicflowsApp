 -- 疎通確認用のジョブ管理テーブルを作成する
CREATE TABLE IF NOT EXISTS test_jobs (
    job_id UUID PRIMARY KEY,
    owner_sub VARCHAR(128) NOT NULL,
    result_key TEXT NOT NULL UNIQUE,
    status VARCHAR(24) NOT NULL
        CHECK (
            status IN (
                'CREATED',
                'QUEUED',
                'ENQUEUE_FAILED',
                'COMPLETED',
                'FAILED'
            )
        ),
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

COMMENT ON TABLE test_jobs IS '疎通確認用のジョブ管理テーブル';
COMMENT ON COLUMN test_jobs.job_id IS 'ジョブID';
COMMENT ON COLUMN test_jobs.owner_sub IS 'ジョブ所有者のサブ';
COMMENT ON COLUMN test_jobs.result_key IS 'ジョブ結果のS3キー';
COMMENT ON COLUMN test_jobs.status IS 'ジョブの状態';
COMMENT ON COLUMN test_jobs.created_at IS 'ジョブ作成日時';
COMMENT ON COLUMN test_jobs.updated_at IS 'ジョブ更新日時';