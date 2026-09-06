package com.jws.musicflows.application.testjob;

import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.json.JsonWriter;
import org.springframework.stereotype.Service;

import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.GetQueueUrlRequest;
import software.amazon.awssdk.services.sqs.model.SendMessageRequest;

@Service
public class TestJobQueueService {

    private final SqsClient sqsClient;
    private final String queueName;
    private final String resultPrefix;

    private final JsonWriter<Map<String, Object>> jsonWriter =
            JsonWriter.standard();

    public TestJobQueueService(
            SqsClient sqsClient,

            @Value("${app.music-job.queue-name}")
            String queueName,

            @Value("${app.music-job.result-prefix}")
            String resultPrefix
    ) {
        this.sqsClient = sqsClient;
        this.queueName = queueName;
        this.resultPrefix = resultPrefix;
    }


    public QueuedTestJob enqueue(
            String requestedBy,
            String payload
    ) {

        String jobId =
                UUID.randomUUID().toString();

        String resultKey =
                resultPrefix
                        + "/"
                        + jobId
                        + ".json";

        // SQSキューのURLを取得する。
        String queueUrl =
                sqsClient.getQueueUrl(
                        GetQueueUrlRequest.builder()
                                .queueName(queueName)
                                .build()
                ).queueUrl();


        Map<String, Object> message =
                new LinkedHashMap<>();

        message.put("version", "1");
        message.put("jobId", jobId);
        message.put("requestedBy", requestedBy);
        message.put("payload", payload);
        message.put("resultKey", resultKey);

        // SQSへメッセージを送信する。
        sqsClient.sendMessage(
                SendMessageRequest.builder()
                        .queueUrl(queueUrl)
                        .messageBody(
                                jsonWriter.writeToString(
                                        message
                                )
                        )
                        .build()
        );

        return new QueuedTestJob(
                jobId,
                resultKey
        );
    }
}