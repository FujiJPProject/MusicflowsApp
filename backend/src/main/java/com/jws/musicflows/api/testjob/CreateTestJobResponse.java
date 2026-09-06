package com.jws.musicflows.api.testjob;

    public record CreateTestJobResponse(
            String jobId,
            String status,
            String resultKey
    ) {
    }