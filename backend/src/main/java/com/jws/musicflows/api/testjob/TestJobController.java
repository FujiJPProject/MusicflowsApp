package com.jws.musicflows.api.testjob;

import java.util.Map;

import org.springframework.http.ResponseEntity;
import org.springframework.security.core.annotation.AuthenticationPrincipal;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import com.jws.musicflows.application.testjob.TestJobQueueService;
import com.jws.musicflows.application.testjob.TestJobResultService;
import com.jws.musicflows.config.security.CurrentJobOwner;

import jakarta.validation.Valid;

@RestController
@RequestMapping("/api/test-jobs")
public class TestJobController {

    private final TestJobQueueService queueService;
    private final TestJobResultService resultService;
    private final CurrentJobOwner currentJobOwner;

    public TestJobController(
            TestJobQueueService queueService,
            TestJobResultService resultService,
            CurrentJobOwner currentJobOwner
    ) {
        this.queueService = queueService;
        this.resultService = resultService;
        this.currentJobOwner = currentJobOwner;
    }

    /*
     * ジョブ登録。
     */
    @PostMapping
    public ResponseEntity<CreateTestJobResponse> create(
            @Valid @RequestBody CreateTestJobRequest request,
            @AuthenticationPrincipal Jwt jwt
    ) {

        /*
         * サーバー側でジョブ所有者を確定する。
         * クライアント指定の所有者情報は信用しない。
         */
        String requestedBy =
                currentJobOwner.requireOwner(jwt);

        var job = queueService.enqueue(
                requestedBy,
                request.payload()
        );

        return ResponseEntity.accepted().body(
                new CreateTestJobResponse(
                        job.jobId(),
                        "QUEUED",
                        job.resultKey()
                )
        );
    }

    /*
     * ジョブ結果取得。
     */
    @GetMapping("/{jobId}/result")
    public ResponseEntity<?> result(
            @PathVariable String jobId,
            @AuthenticationPrincipal Jwt jwt
    ) {

        /*
         * 現在のユーザーを取得する。
         */
        String requestedBy = currentJobOwner.requireOwner(jwt);

        /*
         * サービス側で所有者を照合し、認可成功後にS3へアクセスする。
         */
        return resultService.find(jobId, requestedBy)
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