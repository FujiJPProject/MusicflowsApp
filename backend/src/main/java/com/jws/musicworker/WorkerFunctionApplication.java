package com.jws.musicworker;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.boot.jdbc.autoconfigure.DataSourceAutoConfiguration;
import org.springframework.scheduling.annotation.EnableScheduling;

/**
 * Worker専用Spring Boot Application。
 *
 * API側のMusicflowsApplicationとはComponent Scan範囲を分離する。
 */
@EnableScheduling
@SpringBootApplication(
        exclude = DataSourceAutoConfiguration.class
)
public class WorkerFunctionApplication {

    public static void main(String[] args) {
        SpringApplication.run(
                WorkerFunctionApplication.class,
                args
        );
    }
}