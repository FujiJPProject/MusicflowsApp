package com.jws.musicworker.config;

import org.springframework.beans.factory.InitializingBean;
import org.springframework.context.annotation.Profile;
import org.springframework.core.env.Environment;
import org.springframework.stereotype.Component;
import org.springframework.util.StringUtils;

/**
 * Worker Lambdaの起動時に必須設定を確認するクラス
 */
@Component
@Profile("worker-lambda")
public class WorkerRequiredSettingsValidator implements InitializingBean {

    /** 環境設定 */
    private final Environment environment;

    /**
     * コンストラクタ
     * @param environment 環境設定
     *
     */
    public WorkerRequiredSettingsValidator(Environment environment) {
        this.environment = environment;
    }

    /**
     * プロパティ設定後に必須設定を確認する
     */
    @Override
    public void afterPropertiesSet() {
        require("aws.region");
        require("app.worker.bucket-name");
        require("app.worker.processor-type");

        String target = require("app.runtime.target");

        if (!target.equals("aws") && !target.equals("floci")) {
            throw new IllegalStateException("Invalid runtime target: " + target);
        }

        String endpoint = environment.getProperty("aws.endpoint-url", "");

        if (target.equals("aws") && StringUtils.hasText(endpoint)) {
            throw new IllegalStateException("AWS環境ではendpoint-urlを設定できません");
        }

        if (target.equals("floci") && !StringUtils.hasText(endpoint)) {
            throw new IllegalStateException("Floci環境ではendpoint-urlが必須です");
        }
    }

    /**
     * 必須設定を取得する
     * @param key 設定キー
     * @return 設定値
     * @throws IllegalStateException 設定値が空文字の場合にスローされる
     */
    private String require(String key) {
        String value = environment.getProperty(key);

        if (!StringUtils.hasText(value)) {
            throw new IllegalStateException("Required setting is missing: " + key);
        }

        return value.trim();
    }
}