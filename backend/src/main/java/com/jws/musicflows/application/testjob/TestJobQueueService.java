package com.jws.musicflows.application.testjob;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.json.JsonWriter;
import org.springframework.http.HttpStatus;
import org.springframework.stereotype.Service;
import org.springframework.web.server.ResponseStatusException;

import com.jws.musicflows.infrastructure.testjob.TestJobInputRecord;
import com.jws.musicflows.infrastructure.testjob.TestJobMapper;

import software.amazon.awssdk.core.exception.SdkException;
import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.GetQueueUrlRequest;
import software.amazon.awssdk.services.sqs.model.SendMessageRequest;
import software.amazon.awssdk.services.sqs.model.SendMessageResponse;

/**
 * テストジョブをデータベースに登録し、SQSキューへ送信するサービス。
 */
@Service
public class TestJobQueueService {

    /** ロガー */
    private static final Logger log =
            LoggerFactory.getLogger(TestJobQueueService.class);

    /** ジョブ送信に使用するSQSクライアント。 */
    private final SqsClient sqsClient;
    /** ジョブ情報の登録および状態更新を行うマッパー。 */
    private final TestJobMapper jobMapper;
    /** 送信先のSQSキュー名。 */
    private final String queueName;
    /** ジョブ結果キーの接頭辞。 */
    private final String resultPrefix;

    /** SQSメッセージ本文をJSON形式に変換するライター。 */
    private final JsonWriter<Map<String, Object>> jsonWriter =
            JsonWriter.standard();

    /**
     * キュー送信に必要な依存関係と設定値を初期化する。
     *
     * @param sqsClient SQSクライアント
     * @param jobMapper ジョブ情報を永続化するマッパー
     * @param queueName 送信先のキュー名
     * @param resultPrefix 結果キーの接頭辞
     */
    public TestJobQueueService(
            SqsClient sqsClient,
            TestJobMapper jobMapper,

            @Value("${app.music-job.queue-name}")
            String queueName,

            @Value("${app.music-job.result-prefix}")
            String resultPrefix
    ) {
        this.sqsClient = sqsClient;
        this.jobMapper = jobMapper;
        this.queueName = queueName;
        this.resultPrefix = resultPrefix;
    }

     /**
      * ジョブをデータベースに登録してSQSへ送信する。
      *
      * @param requestedBy ジョブを要求したユーザー
      * @param payload ジョブの入力データ
      * @return 受付済みジョブのIDと結果キー
      * @throws IllegalArgumentException 要求ユーザーが未指定または空白の場合
      * @throws IllegalStateException ジョブの登録または状態更新に失敗した場合
      * @throws ResponseStatusException SQSへの送信に失敗した場合
      */
     public QueuedTestJob enqueue(
            String requestedBy,
            String payload
    ) {

        // 要求ユーザーが未指定または空白の場合は例外をスローする。
        if (requestedBy == null || requestedBy.isBlank()) {
            throw new IllegalArgumentException("Job owner is required");
        }

        // ジョブIDと結果キーを生成する。
        UUID jobUuid = UUID.randomUUID();
        String jobId = jobUuid.toString();
        String resultKey = resultPrefix + "/" + jobId + ".json";

        /*
         * 1. ジョブ管理情報をDBへ登録する。
         * SQS送信より先に所有者情報を確定する。
         */
        var jobInputRecord = new TestJobInputRecord(
                jobUuid,
                requestedBy,
                resultKey,
                "CREATED"
        );
        int inserted = jobMapper.insert(jobInputRecord);
        if (inserted != 1) {
            throw new IllegalStateException("Job record creation failed");
        }

        /*
         * 2. 既存のSQSメッセージ形式は維持する。
         * Issue #2のWorker処理を変更しない。
         */
        Map<String, Object> message = new LinkedHashMap<>();

        message.put("version", "1");
        message.put("jobId", jobId);
        message.put("requestedBy", requestedBy);
        message.put("payload", payload);
        message.put("resultKey", resultKey);

        SendMessageResponse response;

        /*
         * 3. SQSへ送信する。
         */
        try {
            // キューURLを取得する。
            String queueUrl = sqsClient.getQueueUrl(
                                           GetQueueUrlRequest.builder()
                                                      .queueName(queueName)
                                                      .build()
                                        ).queueUrl();
            // メッセージを送信する。
            response = sqsClient.sendMessage(
                    SendMessageRequest.builder()
                            .queueUrl(queueUrl)
                            .messageBody(
                                    jsonWriter.writeToString(
                                            message
                                    )
                            )
                            .build()
            );

        } catch (SdkException exception) {

            /*
             * SQSで失敗した場合はDBへ記録する。
             * DBへの状態更新に失敗した場合も
             * CREATEDが残るため、後で調査できる。
             */
            try {
                jobMapper.updateStatus(jobUuid,"ENQUEUE_FAILED");
            } catch (RuntimeException updateException) {
                log.error("Failed to update job status: jobId={}", jobId, updateException);
            }

            log.error("SQS enqueue failed: jobId={}",jobId,exception);

            throw new ResponseStatusException(
                    HttpStatus.SERVICE_UNAVAILABLE,
                    "Job queue is unavailable",
                    exception
            );
        }

        /*
         * 4. SQS送信成功後、DB状態を更新する。
         */
        int updated = jobMapper.updateStatus(jobUuid,"QUEUED");
        if (updated != 1) {
            throw new IllegalStateException("Job status update failed: " + jobId);
        }

        /*
         * 5. jobIdとmessageIdをログへ記録。
         * Issue #2のログ照合を維持する。
         */
        log.info(
                "Test job queued: jobId={}, messageId={}, queueName={}, resultKey={}",
                jobId,
                response.messageId(),
                queueName,
                resultKey
        );

        return new QueuedTestJob(jobId,resultKey);
    }
}