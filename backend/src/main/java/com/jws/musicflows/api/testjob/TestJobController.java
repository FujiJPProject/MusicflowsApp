package com.jws.musicflows.api.testjob;

import java.util.Map;

import com.jws.musicflows.application.testjob.TestJobQueueService;
import com.jws.musicflows.application.testjob.TestJobResultService;

import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.*;
import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/test-jobs")
public class TestJobController {
private final TestJobQueueService queueService;
    private final TestJobResultService resultService;

    public TestJobController(
            TestJobQueueService queueService,
            TestJobResultService resultService
    ) {
        this.queueService = queueService;
        this.resultService = resultService;
    }


    @PostMapping
    public ResponseEntity<CreateTestJobResponse> create(
            @Valid @RequestBody CreateTestJobRequest request,
            @AuthenticationPrincipal Jwt jwt
    ) {

        String requestedBy = jwt != null ? jwt.getSubject() : "local";

        // SQSキューにジョブを登録する。
        var job = queueService.enqueue(
                        requestedBy,
                        request.payload()
                );

        /*
         * 非同期処理なので201ではなく202。
         */
        return ResponseEntity.accepted().body(
                new CreateTestJobResponse(
                        job.jobId(),
                        "QUEUED",
                        job.resultKey())
        );
    }


    @GetMapping("/{jobId}/result")
    public ResponseEntity<?> result(@PathVariable String jobId) {

        // S3からジョブ結果を取得する。
        return resultService.find(jobId)
                .<ResponseEntity<?>>map(ResponseEntity::ok)
                .orElseGet(() ->
                        ResponseEntity.accepted().body(
                                Map.of(
                                        "jobId", jobId,
                                        "status", "PROCESSING"
                                )
                        )
                );
    }
}