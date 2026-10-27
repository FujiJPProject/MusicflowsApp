package com.jws.musicflows.application.testjob;

import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.json.JsonParserFactory;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import com.jws.musicflows.exception.testjob.JobStorageUnavailableException;
import com.jws.musicflows.infrastructure.testjob.TestJobMapper;
import com.jws.musicflows.infrastructure.testjob.TestJobOutputRecord;

import software.amazon.awssdk.core.ResponseBytes;
import software.amazon.awssdk.core.exception.SdkException;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectResponse;
import software.amazon.awssdk.services.s3.model.S3Exception;

/**
 * テストジョブの実行結果を取得するアプリケーションサービス。
 */
@Service
public class TestJobResultService {

    /** S3クライアント。 */
    private final S3Client s3Client;
    private final TestJobMapper jobMapper;
    /** S3のジョブ結果を格納するバケット名。 */
    private final String bucketName;
    /** S3のジョブ結果を格納するプレフィックス。 */
    private final String resultPrefix;

    /**
     * コンストラクタ
     *
     * @param jobResultS3Client S3クライアント
     * @param jobMapper TestJobMapper
     * @param bucketName S3のジョブ結果を格納するバケット名
     * @param resultPrefix S3のジョブ結果を格納するプレフィックス
     */
    public TestJobResultService(
            S3Client jobResultS3Client,
            TestJobMapper jobMapper,

            @Value("${app.music-job.bucket-name}")
            String bucketName,

            @Value("${app.music-job.result-prefix}")
            String resultPrefix
    ) {
        this.s3Client = jobResultS3Client;
        this.jobMapper = jobMapper;
        this.bucketName = bucketName;
        this.resultPrefix = resultPrefix;
    }

    public Optional<Map<String, Object>> find(
            String jobId,
            String currentOwner
    ) {

        // 1. jobIdの形式を検証する。
        UUID jobUuid;

        try {
            jobUuid = UUID.fromString(jobId);

        } catch (IllegalArgumentException exception) {

            throw new ResponseStatusException(
                    HttpStatus.BAD_REQUEST,
                    "Invalid jobId",
                    exception
            );
        }

        // 2. DBからジョブを取得する。
        TestJobOutputRecord job = jobMapper.findById(jobUuid);

        if (job == null) {
            throw notFound();
        }

        //3. 所有者を照合する。
        // 所有者が違う場合は404を返す。S3にはアクセスしない。
        if (!job.ownerSub().equals(currentOwner)) {
            throw notFound();
        }

        
        // 4. SQS登録に失敗したジョブをPROCESSINGとして扱わない。
        if ("ENQUEUE_FAILED".equals(job.status())) {
            throw new JobStorageUnavailableException("Job was not enqueued");
        }

        // 5. DBに保存されたS3キーが想定した形式かを確認する。
        String expectedKey = resultPrefix + "/" + jobId + ".json";
        if (!expectedKey.equals(job.resultKey())) {
            throw new JobStorageUnavailableException("Unexpected job result key");
        }

        // 6. 認可成功後にS3へアクセスする。
        ResponseBytes<GetObjectResponse> bytes;

        try {
            bytes = s3Client.getObjectAsBytes(
                    request -> request
                            .bucket(bucketName)
                            .key(job.resultKey())
            );

        } catch (S3Exception exception) {
            

            /*
             * 404: 結果がまだ存在しない。
             * ただしDBがCOMPLETEDなのに404の場合、
             * S3との整合性異常として処理する。
             */
            if (exception.statusCode() == 404) {

                if ("COMPLETED".equals(job.status())) {
                    throw new JobStorageUnavailableException(
                            "Completed job result is missing",
                            exception
                    );
                }

                return Optional.empty();
            }

            /*
             * 403:
             * 存在しないオブジェクトでも権限により
             * 403になる可能性がある。
             *
             * 202には変換せず、障害として扱う。
             */
            throw new JobStorageUnavailableException(
                    "S3 GetObject failed: status=" + exception.statusCode(),exception
            );

        } catch (SdkException exception) {

            throw new JobStorageUnavailableException(
                    "S3 client operation failed",
                    exception
            );
        }

        // 7. 結果JSONを解析する。
        Map<String, Object> result;

        try {
            String json = bytes.asString(StandardCharsets.UTF_8);

            result = JsonParserFactory
                    .getJsonParser()
                    .parseMap(json);

        } catch (RuntimeException exception) {

            throw new JobStorageUnavailableException(
                    "Invalid S3 result JSON",
                    exception
            );
        }

        /*
         * 8. S3結果がDB管理情報と一致するか確認する。
         *
         * S3の内容だけを認可の根拠にしない。
         */
        if (!jobId.equals(result.get("jobId"))) {
            throw new JobStorageUnavailableException("Result jobId mismatch");
        }

        if (!currentOwner.equals(result.get("requestedBy"))) {
            throw new JobStorageUnavailableException("Result owner mismatch");
        }

        if (!"COMPLETED".equals(result.get("status"))) {
            throw new JobStorageUnavailableException("Unexpected result status");
        }

        /*
         * 9. DBの状態をCOMPLETEDへ更新する。
         */
        if (!"COMPLETED".equals(job.status())) {
            int updated = jobMapper.updateStatus(jobUuid,"COMPLETED");

            if (updated != 1) {
                throw new IllegalStateException("Job status update failed");
            }
        }

        return Optional.of(result);
    }
    
    /**
     * 404 Not Found を返す ResponseStatusException を生成する。
     * @return
     */
    private ResponseStatusException notFound() {
        return new ResponseStatusException(HttpStatus.NOT_FOUND,"Job not found");
    }
}