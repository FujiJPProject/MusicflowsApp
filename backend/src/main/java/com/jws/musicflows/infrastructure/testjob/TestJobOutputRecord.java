package com.jws.musicflows.infrastructure.testjob;

import java.util.UUID;

public record TestJobOutputRecord(
        /** ジョブID */
        UUID jobId,
        /** ジョブ所有者のサブ */
        String ownerSub,
        /** ジョブ結果のS3キー */
        String resultKey,
        /** ジョブの状態 */
        String status
) {
}