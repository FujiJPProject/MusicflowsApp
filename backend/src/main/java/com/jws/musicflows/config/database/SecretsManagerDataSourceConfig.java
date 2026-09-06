package com.jws.musicflows.config.database;

import java.net.URI;
import java.util.Map;

import javax.sql.DataSource;

import com.zaxxer.hikari.HikariConfig;
import com.zaxxer.hikari.HikariDataSource;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.boot.json.JsonParserFactory;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.context.annotation.Profile;
import org.springframework.util.StringUtils;

import software.amazon.awssdk.regions.Region;

import software.amazon.awssdk.services.secretsmanager.SecretsManagerClient;

/**
 * Lambda環境のDB接続設定。
 *
 * DB接続情報をLambda環境変数から直接取得せず、
 * AWS Secrets Managerから取得してDataSourceを生成する。
 */
@Configuration
@Profile("lambda")
public class SecretsManagerDataSourceConfig {

    private static final Logger log =
            LoggerFactory.getLogger(
                    SecretsManagerDataSourceConfig.class
            );


    /**
     * Secrets ManagerへアクセスするAWS SDKクライアント。
     */
    @Bean(destroyMethod = "close")
    SecretsManagerClient secretsManagerClient(
            @Value("${aws.region}") String awsRegion,
            @Value("${aws.endpoint-url:}") String endpointUrl
    ) {

        var builder =
                SecretsManagerClient.builder()
                        .region(
                                Region.of(awsRegion)
                        );

        /*
         * Floci環境ではhttp://floci:4566 を使用する。
         *
         * 実AWSではendpoint-urlを設定しないため、
         * AWS SDK標準のSecrets Manager endpointが使用される。
         */
        if (StringUtils.hasText(endpointUrl)) {
            builder.endpointOverride(
                    URI.create(endpointUrl)
            );
        }

        return builder.build();
    }


    /**
     * Secrets ManagerからDB接続情報を読み込み、
     * HikariDataSourceを生成する。
     */
    @Bean(destroyMethod = "close")
    DataSource dataSource(
            SecretsManagerClient secretsManagerClient,

            @Value("${app.database.secret-name}")
            String secretName,

            @Value("${app.database.hikari.maximum-pool-size:2}")
            int maximumPoolSize,

            @Value("${app.database.hikari.minimum-idle:0}")
            int minimumIdle,

            @Value("${app.database.hikari.connection-timeout:5000}")
            long connectionTimeout,

            @Value("${app.database.hikari.idle-timeout:30000}")
            long idleTimeout
    ) {

        /*
         * Secrets Manager:
         *
         * music-app/local/db
         *
         * からSecretStringを取得する。
         */
        String secretString =
                secretsManagerClient
                        .getSecretValue(request ->
                                request.secretId(
                                        secretName
                                )
                        )
                        .secretString();

        if (!StringUtils.hasText(secretString)) {
            throw new IllegalStateException(
                    "Secrets ManagerのSecretStringが空です: "
                            + secretName
            );
        }


        /*
         * 04-init-secretsmanager.shで登録している
         * JSONをMapへ変換する。
         */
        Map<String, Object> secret =
                JsonParserFactory
                        .getJsonParser()
                        .parseMap(secretString);


        String host =
                requiredValue(
                        secret,
                        "host"
                );

        int port =
                Integer.parseInt(
                        requiredValue(
                                secret,
                                "port"
                        )
                );

        String databaseName =
                requiredValue(
                        secret,
                        "dbname"
                );

        String username =
                requiredValue(
                        secret,
                        "username"
                );

        String password =
                requiredValue(
                        secret,
                        "password"
                );


        /*
         * SecretからJDBC URLを生成する。
         */
        String jdbcUrl =
                "jdbc:postgresql://%s:%d/%s"
                        .formatted(
                                host,
                                port,
                                databaseName
                        );


        /*
         * Lambda向けのHikariCP設定。
         */
        HikariConfig hikari =
                new HikariConfig();

        hikari.setJdbcUrl(jdbcUrl);

        hikari.setUsername(username);

        hikari.setPassword(password);

        hikari.setDriverClassName(
                "org.postgresql.Driver"
        );

        hikari.setMaximumPoolSize(
                maximumPoolSize
        );

        hikari.setMinimumIdle(
                minimumIdle
        );

        hikari.setConnectionTimeout(
                connectionTimeout
        );

        hikari.setIdleTimeout(
                idleTimeout
        );


        /*
         * passwordなどの秘密情報はログへ出さない。
         *
         * Secret名のみログに残し、
         * Secrets Manager経由で初期化されたことを
         * 確認できるようにする。
         */
        log.info(
                "Database configuration loaded from Secrets Manager: secretName={}",
                secretName
        );

        return new HikariDataSource(
                hikari
        );
    }


    /**
     * Secret JSONの必須項目を取得する。
     */
    private static String requiredValue(
            Map<String, Object> secret,
            String key
    ) {

        Object value =
                secret.get(key);

        if (value == null
                || value.toString().isBlank()) {

            throw new IllegalStateException(
                    "DB Secretに必須項目がありません: "
                            + key
            );
        }

        return value.toString();
    }
}