package com.jws.musicflows.api.test;

import org.springframework.web.bind.annotation.RestController;

import java.net.URI;
import java.util.List;

import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;

import com.jws.musicflows.application.test.TestsService;
import com.jws.musicflows.application.test.TestsDto;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;

/**
 * 接続確認用API
 */
@RestController
@RequestMapping("/api/tests")
public class TestsController {

    private final TestsService testsService;

    public TestsController(TestsService testsService) {
        this.testsService = testsService;
    }

    /**
     * すべての接続確認用エンティティを取得します。
     * @return
     */
    @GetMapping
    public ResponseEntity<List<TestsDto>> getTestsAll() {
        return ResponseEntity.ok(testsService.findAll());
    }

    /**
     * 接続確認用エンティティを登録します。
     * @param request
     * @return
     */
    @PostMapping
    public ResponseEntity<TestsDto> postTests(@RequestBody CreateTestsRequest request) {
        
        TestsDto result = testsService.create(request.name());
        return ResponseEntity.created(
            URI.create("/api/tests/" + result.getId())
        ).body(result);
    }
    

}
