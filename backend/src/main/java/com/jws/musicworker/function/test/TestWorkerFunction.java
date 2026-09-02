package com.jws.musicworker.function.test;

import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.function.Function;

import com.amazonaws.services.lambda.runtime.events.SQSBatchResponse;
import com.amazonaws.services.lambda.runtime.events.SQSEvent;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.json.JsonParserFactory;
import org.springframework.boot.json.JsonWriter;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;

import software.amazon.awssdk.core.sync.RequestBody;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;

@Configuration
public class TestWorkerFunction {

    private static final Logger log = LoggerFactory.getLogger(TestWorkerFunction.class);

    @Bean
    Function<SQSEvent, SQSBatchResponse> musicJobWorker(
            S3Client workerS3Client,

            @Value("${app.worker.bucket-name}")
            String bucketName
    ) {

        return event -> {

            // 処理失敗したメッセージIDを格納するリスト。
            var failures = new ArrayList<SQSBatchResponse.BatchItemFailure>();

            // SQSイベントのレコードがnullの場合は、空の失敗リストを返す。
            if (event.getRecords() == null) {
                return new SQSBatchResponse(failures);
            }

            // SQSイベントの各レコードを処理する。
            for (SQSEvent.SQSMessage record : event.getRecords()) {

                try {

                    // SQSメッセージを処理する。
                    process(
                        workerS3Client,
                        bucketName,
                        record
                    );

                } catch (Exception exception) {

                    log.error(
                            "Music job processing failed: messageId={}",
                            record.getMessageId(),
                            exception
                    );

                    failures.add(
                            new SQSBatchResponse.BatchItemFailure(
                                    record.getMessageId()
                            )
                    );
                }
            }

            return new SQSBatchResponse(
                    failures
            );
        };
    }


    /**
     * SQSメッセージを処理する。
     * @param s3Client 
     * @param bucketName
     * @param record
     */
    private void process(
            S3Client s3Client,
            String bucketName,
            SQSEvent.SQSMessage record
    ) {

        // SQSメッセージのJSONをMapに変換する。
        Map<String, Object> message = JsonParserFactory
                                      .getJsonParser()
                                      .parseMap(record.getBody());

        String jobId = required(message, "jobId");
        String requestedBy = required(message,"requestedBy");
        String payload = required(message,"payload");
        String resultKey = required(message,"resultKey");


        Map<String, Object> result = new LinkedHashMap<>();
        result.put("jobId",jobId);
        result.put("status","COMPLETED");
        result.put("requestedBy",requestedBy);

        /*
         * 疎通確認用処理。
         * 将来ここを実際の音声処理へ置き換える。
         */
        result.put("processedPayload",payload.toUpperCase());
        result.put("processedAt",Instant.now().toString());

        // MapをJSON文字列に変換する。
        String resultJson = JsonWriter.<Map<String, Object>>standard()
                            .writeToString(result);

        // S3にジョブ結果を保存する。
        s3Client.putObject(
                PutObjectRequest.builder()
                        .bucket(bucketName)
                        .key(resultKey)
                        .contentType("application/json")
                        .build(),

                RequestBody.fromString(resultJson)
        );


        log.info(
                "Music job completed: jobId={}, bucket={}, key={}",
                jobId,
                bucketName,
                resultKey
        );
    }

    /**
     * Mapから必須フィールドを取得する。
     * @param values
     * @param key
     * @return
     */
    private String required(Map<String, Object> values,String key) {

        Object value = values.get(key);
        // 値がnullまたは空文字の場合は例外をスローする。
        if (value == null || value.toString().isBlank()) {

            throw new IllegalArgumentException("Required field is missing: " + key);
        }

        return value.toString();
    }
}
