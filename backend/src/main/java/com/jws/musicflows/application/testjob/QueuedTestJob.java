package com.jws.musicflows.application.testjob;

    public record QueuedTestJob(
            String jobId,
            String resultKey
    ) {
    }
