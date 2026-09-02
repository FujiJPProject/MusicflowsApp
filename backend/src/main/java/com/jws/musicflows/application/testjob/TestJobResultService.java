package com.jws.musicflows.application.testjob;

import java.nio.charset.StandardCharsets;
import java.util.Map;
import java.util.Optional;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.json.JsonParserFactory;
import org.springframework.stereotype.Service;

import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.S3Exception;

@Service
public class TestJobResultService {

    private final S3Client s3Client;
    private final String bucketName;
    private final String resultPrefix;

    public TestJobResultService(
            S3Client jobResultS3Client,

            @Value("${app.music-job.bucket-name}")
            String bucketName,

            @Value("${app.music-job.result-prefix}")
            String resultPrefix
    ) {
        this.s3Client = jobResultS3Client;
        this.bucketName = bucketName;
        this.resultPrefix = resultPrefix;
    }


    public Optional<Map<String, Object>> find(
            String jobId
    ) {

        String key =
                resultPrefix
                        + "/"
                        + jobId
                        + ".json";

        try {

            // S3からオブジェクトを取得する。
            var bytes = s3Client.getObjectAsBytes(
                            request ->  request
                                        .bucket(bucketName)
                                        .key(key)
                    );

            String json = bytes.asString(StandardCharsets.UTF_8);

            // JSON文字列をMapに変換して返す。
            return Optional.of(
                    JsonParserFactory.getJsonParser()
                                     .parseMap(json)
            );

        } catch (S3Exception exception) {

            if (exception.statusCode() == 404) {
                return Optional.empty();
            }

            throw exception;
        }
    }
}