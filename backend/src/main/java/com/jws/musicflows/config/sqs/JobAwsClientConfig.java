package com.jws.musicflows.config.sqs;

import java.net.URI;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.util.StringUtils;

import software.amazon.awssdk.auth.credentials.AwsBasicCredentials;
import software.amazon.awssdk.auth.credentials.StaticCredentialsProvider;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.sqs.SqsClient;

@Configuration
public class JobAwsClientConfig {

    @Bean(destroyMethod = "close")
    SqsClient sqsClient(
            @Value("${aws.region}") String region,
            @Value("${aws.endpoint-url:}") String endpointUrl
    ) {

        var builder = SqsClient.builder()
                .region(Region.of(region));

        if (StringUtils.hasText(endpointUrl)) {

            builder.endpointOverride(
                    URI.create(endpointUrl)
            );

            /*
             * Floci用ダミー資格情報。
             *
             * 実AWSではendpoint-urlを設定しないため、
             * Lambda実行ロールの資格情報が利用される。
             */
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


    @Bean(destroyMethod = "close")
    S3Client jobResultS3Client(
            @Value("${aws.region}") String region,
            @Value("${aws.endpoint-url:}") String endpointUrl
    ) {

        var builder = S3Client.builder()
                .region(Region.of(region));

        if (StringUtils.hasText(endpointUrl)) {

            builder.endpointOverride(
                    URI.create(endpointUrl)
            );

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
}