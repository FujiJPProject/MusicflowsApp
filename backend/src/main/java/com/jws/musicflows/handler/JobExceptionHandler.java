package com.jws.musicflows.handler;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.http.ProblemDetail;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.RestControllerAdvice;

import com.jws.musicflows.exception.testjob.JobStorageUnavailableException;

@RestControllerAdvice
public class JobExceptionHandler {

    /** ロガー */
    private static final Logger log = LoggerFactory.getLogger(JobExceptionHandler.class);

    /**
     * ジョブ結果の保存ストレージが利用できない場合の例外ハンドラ。
     *
     * @param exception 例外オブジェクト
     * @return 問題詳細オブジェクト
     */
    @ExceptionHandler(JobStorageUnavailableException.class)
    public ProblemDetail handleStorageError(
            JobStorageUnavailableException exception
    ) {

        log.error("Job storage operation failed",exception);

        /*
         * AWS SDKの内部エラー詳細を
         * ブラウザへ返さない。
         */
        ProblemDetail detail = ProblemDetail.forStatusAndDetail(
                                HttpStatus.SERVICE_UNAVAILABLE,
                        "Job result storage is unavailable"
                        );

        detail.setTitle("Job storage unavailable");
        return detail;
    }
}
