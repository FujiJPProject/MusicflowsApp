package com.jws.musicworker.config;

import java.net.URI;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.util.StringUtils;
import org.springframework.context.annotation.Profile;

import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.sqs.SqsClient;

/**
 * AWS SDKクライアント設定。
 * 
 * WorkerAwsConfig
 */
@Configuration
public class WorkerAwsConfig {

    @Bean(destroyMethod = "close")
    S3Client workerS3Client(
            @Value("${aws.region}") String region,
            @Value("${aws.endpoint-url:}") String endpointUrl
    ) {

        // S3Clientのビルダーを作成し、リージョンを設定する。
        var builder = S3Client.builder()
                              .region(Region.of(region));

        // Floci環境ではendpoint-urlを設定する。
        if (StringUtils.hasText(endpointUrl)) {

            // Floci環境ではS3のエンドポイントを設定する。
            builder.endpointOverride(
                    URI.create(endpointUrl)
            );
            // Floci環境ではダミー資格情報を使用する。
            builder.forcePathStyle(true);
            builder.credentialsProvider(    
                    StaticCredentialsProvider.create(
                            AwsBasicCredentials.create(
                                    "test",
                                    "test"
                            )
                    )
            );
        }

        return builder.build();
    }


    /*
     * SQSクライアントを作成する。
     */
    @Bean(destroyMethod = "close")
    @Profile("worker-local")
    SqsClient workerSqsClient(
            @Value("${aws.region}") String region,
            @Value("${aws.endpoint-url:}") String endpointUrl
    ) {

        var builder =
                SqsClient.builder()
                        .region(Region.of(region));

        if (StringUtils.hasText(endpointUrl)) {

            builder.endpointOverride(
                    URI.create(endpointUrl)
            );

            builder.credentialsProvider(
                    StaticCredentialsProvider.create(
                            AwsBasicCredentials.create(
                                    "test",
                                    "test"
                            )
                    )
            );
        }

        return builder.build();
    }
}