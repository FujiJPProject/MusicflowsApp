package com.jws.musicflows.infrastructure.testjob;

import java.util.UUID;

import org.apache.ibatis.annotations.Mapper;
import org.apache.ibatis.annotations.Param;

/**
 * TestJobMapper インターフェース。
 */
@Mapper
public interface TestJobMapper {

    /**
     * TestJobRecordを登録する。
     *
     * @param job 登録するTestJobRecord
     * @return 登録された行数
     */
    int insert(@Param("job") TestJobInputRecord job);

    /**
     * TestJobRecordをIDで取得する。
     *
     * @param jobId 取得するジョブのID
     * @return 該当するTestJobRecord。存在しない場合は{@code null}
     */
    TestJobOutputRecord findById(@Param("jobId") UUID jobId);

    /**
     * ジョブの状態を更新する。
     *
     * @param jobId 状態を更新するジョブのID
     * @param status 更新後の状態
     * @return 更新された行数
     */
    int updateStatus(@Param("jobId") UUID jobId, @Param("status") String status);
}