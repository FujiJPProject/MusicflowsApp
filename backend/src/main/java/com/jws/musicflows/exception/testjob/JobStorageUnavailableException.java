package com.jws.musicflows.exception.testjob;

/**
 * ジョブの結果を保存するストレージが利用できない場合にスローされる例外。
 */
public class JobStorageUnavailableException extends RuntimeException {

    /**
     * コンストラクタ
     *
     * @param message 例外メッセージ
     */
    public JobStorageUnavailableException(String message) {
        super(message);
    }

    /**
     * コンストラクタ
     *
     * @param message 例外メッセージ
     * @param cause 原因となる例外
     */
    public JobStorageUnavailableException( String message,Throwable cause) {
        super(message, cause);
    }
}