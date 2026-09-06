package com.jws.musicworker.local;

import java.util.List;
import java.util.function.Function;

import com.amazonaws.services.lambda.runtime.events.SQSBatchResponse;
import com.amazonaws.services.lambda.runtime.events.SQSEvent;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.cloud.function.context.FunctionCatalog;
import org.springframework.context.annotation.Profile;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;

import software.amazon.awssdk.services.sqs.SqsClient;
import software.amazon.awssdk.services.sqs.model.DeleteMessageRequest;
import software.amazon.awssdk.services.sqs.model.GetQueueUrlRequest;
import software.amazon.awssdk.services.sqs.model.ReceiveMessageRequest;

/**
 * ローカルWorkerがSQSをpollするためのクラス。
 *
 * LambdaではSQSイベントがトリガーされるため、
 * このクラスは使用されない。
 */
@Component
@Profile("worker-local")
public class LocalSqsWorkerPoller {

    private static final Logger log = LoggerFactory.getLogger(LocalSqsWorkerPoller.class);

    /**
     * SQSクライアント。
     */
    private final SqsClient sqsClient;

    /**
     * FunctionCatalog。
     */
    private final FunctionCatalog functionCatalog;

    /**
     * SQSキュー名。
     */
    private final String queueName;


    public LocalSqsWorkerPoller(
            SqsClient workerSqsClient,
            FunctionCatalog functionCatalog,

            @Value("${app.worker.queue-name}")
            String queueName
    ) {
        this.sqsClient = workerSqsClient;
        this.functionCatalog = functionCatalog;
        this.queueName = queueName;
    }


    @Scheduled(fixedDelay = 1000)
    @SuppressWarnings("unchecked")
    public void poll() {

        // SQSキューのURLを取得する。
        String queueUrl = sqsClient.getQueueUrl(
                            GetQueueUrlRequest.builder()
                                    .queueName(queueName)
                                    .build()
                            ).queueUrl();

        // SQSキューからメッセージを1件取得する。
        var messages = sqsClient.receiveMessage(
                            ReceiveMessageRequest.builder()
                                    .queueUrl(queueUrl)
                                    .maxNumberOfMessages(1)
                                    .waitTimeSeconds(1)
                                    .build()).messages();

        // 受信したメッセージがない場合は、何もしない。
        if (messages.isEmpty()) {
            return;
        }

        for (var message : messages) {

            // SQSイベントを作成する。
            SQSEvent.SQSMessage sqsMessage = new SQSEvent.SQSMessage();
            sqsMessage.setMessageId(message.messageId());
            sqsMessage.setBody(message.body());

            
            SQSEvent event = new SQSEvent();
            event.setRecords(List.of(sqsMessage));

            // musicJobWorker関数をFunctionCatalogから取得する。
            Function<SQSEvent, SQSBatchResponse> function = functionCatalog.lookup("musicJobWorker");

            // SQSイベントを関数に渡して処理する。
            SQSBatchResponse response = function.apply(event);

            // 処理結果をログに出力する。
            boolean success = response.getBatchItemFailures() == null
                            || response.getBatchItemFailures().isEmpty();


            /*
             * 成功時だけQueueから削除する。
             *
             * 失敗時は削除しないため、
             * Visibility Timeout後に再取得できる。
             */
            if (success) {

                // SQSメッセージを削除する。
                sqsClient.deleteMessage(
                        DeleteMessageRequest.builder()
                                .queueUrl(queueUrl)
                                .receiptHandle(
                                        message.receiptHandle()
                                )
                                .build());

                log.info(
                        "Local worker processed message: messageId={}",
                        message.messageId()
                );
            }
        }
    }
}