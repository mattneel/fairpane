#include "fairpane.h"
#include <assert.h>
#include <stddef.h>
#include <string.h>

_Static_assert(sizeof(uint32_t) == 4, "A 32-bit uint32_t is required");
_Static_assert(offsetof(fp_capabilities, abi_revision) == 4, "Unexpected revision offset");
_Static_assert(offsetof(fp_capabilities, feature_bits) == 8, "Unexpected feature offset");
_Static_assert(sizeof(fp_capabilities) == 16, "Unexpected capability structure size");
_Static_assert(sizeof(fp_engine_options) == 16, "Unexpected engine option structure size");
_Static_assert(offsetof(fp_engine_options, max_response_body_bytes) == 8, "Unexpected body bound offset");
_Static_assert(sizeof(fp_step_outcome) == 32, "Unexpected step outcome structure size");
_Static_assert(offsetof(fp_step_outcome, next_deadline) == 24, "Unexpected deadline offset");
_Static_assert(offsetof(fp_response, request_id) == 8, "Unexpected response request offset");
_Static_assert(offsetof(fp_response, body) == 16, "Unexpected response body offset");
_Static_assert(offsetof(fp_document_info, body) == 8, "Unexpected document body offset");
_Static_assert(offsetof(fp_event, request_id) == 16, "Unexpected event request offset");
_Static_assert(offsetof(fp_event, reject_reason) == 36, "Unexpected event reason offset");
_Static_assert(offsetof(fp_event, url) == 40, "Unexpected event URL offset");

static void check_capabilities(void) {
    fp_capabilities result = {19, 23, 42};
    assert(fp_abi_revision() == 0);
    assert(fp_query_capabilities(NULL, sizeof(result)) == FP_STATUS_INVALID_ARGUMENT);
    assert(fp_query_capabilities(&result, sizeof(result) - 1) == FP_STATUS_INVALID_ARGUMENT);
    assert(result.struct_size == 19 && result.abi_revision == 23 && result.feature_bits == 42);
    assert(fp_query_capabilities(&result, sizeof(result)) == FP_STATUS_OK);
    assert(result.struct_size == sizeof(result));
    assert(result.abi_revision == 0 && result.feature_bits == 0);
}

static int is_filled(const void *bytes, size_t size, unsigned char value) {
    const unsigned char *cursor = bytes;
    for (size_t index = 0; index < size; index += 1) {
        if (cursor[index] != value) return 0;
    }
    return 1;
}

/* FP-0006 case 18: the full document lifecycle and argument checks through the header. */
static void check_document_lifecycle(void) {
    static const char url[] = "https://example.test/c-smoke";
    static const char body[] = "<p>C smoke</p>";
    fp_engine_options options = {sizeof(fp_engine_options), 4, 1024};
    fp_engine *engine = NULL;
    fp_engine *untouched = (fp_engine *)&options;

    /* Null pointers and short structures return FP_STATUS_INVALID_ARGUMENT without writing output. */
    assert(fp_engine_create(NULL, &untouched) == FP_STATUS_INVALID_ARGUMENT);
    assert(fp_engine_create(&options, NULL) == FP_STATUS_INVALID_ARGUMENT);
    options.struct_size = sizeof(fp_engine_options) - 1;
    assert(fp_engine_create(&options, &untouched) == FP_STATUS_INVALID_ARGUMENT);
    assert(untouched == (fp_engine *)&options);
    options.struct_size = sizeof(fp_engine_options);
    assert(fp_engine_destroy(NULL) == FP_STATUS_INVALID_ARGUMENT);
    assert(fp_engine_create(&options, &engine) == FP_STATUS_OK);
    assert(engine != NULL);

    uint64_t document = 0;
    assert(fp_document_create(NULL, &document) == FP_STATUS_INVALID_ARGUMENT);
    assert(fp_document_create(engine, NULL) == FP_STATUS_INVALID_ARGUMENT);
    assert(document == 0);
    assert(fp_document_create(engine, &document) == FP_STATUS_OK);
    assert(document != 0);

    fp_document_info info;
    memset(&info, 0xA5, sizeof(info));
    assert(fp_document_get(engine, document, NULL, sizeof(info)) == FP_STATUS_INVALID_ARGUMENT);
    assert(fp_document_get(engine, document, &info, sizeof(info) - 1) == FP_STATUS_INVALID_ARGUMENT);
    assert(is_filled(&info, sizeof(info), 0xA5));
    assert(fp_document_get(engine, document, &info, sizeof(info)) == FP_STATUS_OK);
    assert(info.struct_size == sizeof(info) && info.state == FP_DOCUMENT_EMPTY);
    assert(info.body == NULL && info.body_len == 0);

    uint64_t request = 0;
    assert(fp_document_load(engine, document, NULL, 4, &request) == FP_STATUS_INVALID_ARGUMENT);
    assert(fp_document_load(engine, document, (const uint8_t *)url, strlen(url), NULL) == FP_STATUS_INVALID_ARGUMENT);
    assert(request == 0);
    assert(fp_document_load(engine, document, (const uint8_t *)url, strlen(url), &request) == FP_STATUS_OK);
    assert(request != 0 && request != document);

    fp_event event;
    memset(&event, 0x5A, sizeof(event));
    assert(fp_engine_next_event(engine, NULL, sizeof(event)) == FP_STATUS_INVALID_ARGUMENT);
    assert(fp_engine_next_event(engine, &event, sizeof(event) - 1) == FP_STATUS_INVALID_ARGUMENT);
    assert(is_filled(&event, sizeof(event), 0x5A));
    assert(fp_engine_next_event(engine, &event, sizeof(event)) == FP_STATUS_OK);
    assert(event.struct_size == sizeof(event) && event.kind == FP_EVENT_REQUEST_ISSUED);
    assert(event.document_id == document && event.request_id == request);
    assert(event.request_kind == FP_REQUEST_RESOURCE && event.request_version == FP_RESOURCE_REQUEST_VERSION);
    assert(event.url != NULL && event.url_len == strlen(url));
    assert(memcmp(event.url, url, event.url_len) == 0);
    const uint8_t *request_url = event.url;
    assert(fp_engine_next_event(engine, &event, sizeof(event)) == FP_STATUS_OK);
    assert(event.kind == FP_EVENT_DOCUMENT_STATE_CHANGED && event.document_state == FP_DOCUMENT_LOADING);
    assert(event.document_id == document && event.request_id == request);

    fp_response response = {sizeof(fp_response), 2, request, (const uint8_t *)body, strlen(body)};
    assert(fp_request_respond(engine, NULL) == FP_STATUS_INVALID_ARGUMENT);
    response.struct_size = sizeof(fp_response) - 1;
    assert(fp_request_respond(engine, &response) == FP_STATUS_INVALID_ARGUMENT);
    response.struct_size = sizeof(fp_response);
    response.body = NULL;
    assert(fp_request_respond(engine, &response) == FP_STATUS_INVALID_ARGUMENT);
    response.body = (const uint8_t *)body;
    assert(fp_request_respond(engine, &response) == FP_STATUS_UNSUPPORTED_VERSION);
    response.version = FP_RESOURCE_REQUEST_VERSION;
    assert(fp_request_respond(engine, &response) == FP_STATUS_OK);
    assert(fp_request_respond(engine, &response) == FP_STATUS_INVALID_STATE);
    assert(fp_request_reject(engine, request, 0) == FP_STATUS_INVALID_ARGUMENT);
    /* The URL stays readable until the step applies the response. */
    assert(memcmp(request_url, url, strlen(url)) == 0);
    assert(fp_document_get(engine, document, &info, sizeof(info)) == FP_STATUS_OK);
    assert(info.state == FP_DOCUMENT_LOADING);

    fp_step_outcome outcome;
    memset(&outcome, 0x3C, sizeof(outcome));
    assert(fp_engine_step(engine, 1, NULL, sizeof(outcome)) == FP_STATUS_INVALID_ARGUMENT);
    assert(fp_engine_step(engine, 1, &outcome, sizeof(outcome) - 1) == FP_STATUS_INVALID_ARGUMENT);
    assert(is_filled(&outcome, sizeof(outcome), 0x3C));
    assert(fp_engine_step(engine, 1, &outcome, sizeof(outcome)) == FP_STATUS_OK);
    assert(outcome.struct_size == sizeof(outcome) && outcome.applied == 1 && outcome.work_remaining == 0);
    assert(outcome.events_ready == 1 && outcome.next_deadline == FP_DEADLINE_NONE);

    assert(fp_document_get(engine, document, &info, sizeof(info)) == FP_STATUS_OK);
    assert(info.state == FP_DOCUMENT_LOADED && info.body_len == strlen(body));
    assert(memcmp(info.body, body, info.body_len) == 0);
    assert(fp_request_respond(engine, &response) == FP_STATUS_UNKNOWN_ID);

    assert(fp_engine_next_event(engine, &event, sizeof(event)) == FP_STATUS_OK);
    assert(event.kind == FP_EVENT_DOCUMENT_STATE_CHANGED && event.document_state == FP_DOCUMENT_LOADED);
    assert(event.request_id == request && event.reject_reason == 0 && event.url == NULL);
    assert(fp_engine_next_event(engine, &event, sizeof(event)) == FP_STATUS_OK);
    assert(event.kind == FP_EVENT_NONE);

    assert(fp_document_destroy(engine, document) == FP_STATUS_OK);
    assert(fp_document_get(engine, document, &info, sizeof(info)) == FP_STATUS_UNKNOWN_ID);
    assert(fp_engine_destroy(engine) == FP_STATUS_OK);
}

int main(void) {
    check_capabilities();
    check_document_lifecycle();
    return 0;
}
