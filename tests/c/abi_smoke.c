/* The C smoke test. It runs every failure scenario of api/failure-scenarios.json that C can express.
 * Each scenario function names its identifier, and main runs every one.
 */
#if !defined(_WIN32)
#  define _POSIX_C_SOURCE 200809L
#endif
#include "fairpane.h"
#include <assert.h>
#include <stddef.h>
#include <string.h>
#if defined(_WIN32)
#  define WIN32_LEAN_AND_MEAN
#  include <windows.h>
#else
#  include <pthread.h>
#endif

#ifdef NDEBUG
#  error "The smoke test checks every call with assert."
#endif

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

static fp_engine *create_engine(uint32_t max_outstanding_requests, uint64_t max_response_body_bytes) {
    fp_engine_options options = {sizeof(fp_engine_options), max_outstanding_requests, max_response_body_bytes};
    fp_engine *engine = NULL;
    assert(fp_engine_create(&options, &engine) == FP_STATUS_OK);
    assert(engine != NULL);
    return engine;
}

static fp_document_id create_document(fp_engine *engine) {
    fp_document_id document = 0;
    assert(fp_document_create(engine, &document) == FP_STATUS_OK);
    return document;
}

static fp_request_id load(fp_engine *engine, fp_document_id document, const char *url) {
    fp_request_id request = 0;
    assert(fp_document_load(engine, document, (const uint8_t *)url, strlen(url), &request) == FP_STATUS_OK);
    return request;
}

static fp_response response(fp_request_id request, const char *body) {
    fp_response result = {sizeof(fp_response), FP_RESOURCE_REQUEST_VERSION, request, (const uint8_t *)body, strlen(body)};
    return result;
}

static void respond(fp_engine *engine, fp_request_id request, const char *body) {
    fp_response answer = response(request, body);
    assert(fp_request_respond(engine, &answer) == FP_STATUS_OK);
}

static fp_document_info document_info(fp_engine *engine, fp_document_id document) {
    fp_document_info info;
    assert(fp_document_get(engine, document, &info, sizeof(info)) == FP_STATUS_OK);
    return info;
}

static uint32_t document_state(fp_engine *engine, fp_document_id document) {
    return document_info(engine, document).state;
}

static fp_step_outcome step(fp_engine *engine, uint32_t budget) {
    fp_step_outcome outcome;
    assert(fp_engine_step(engine, budget, &outcome, sizeof(outcome)) == FP_STATUS_OK);
    return outcome;
}

/* A zero-budget step applies nothing and reports the ready events and whether input is queued. */
static void expect_queues(fp_engine *engine, uint64_t events_ready, uint32_t work_remaining) {
    fp_step_outcome outcome = step(engine, 0);
    assert(outcome.applied == 0 && outcome.events_ready == events_ready && outcome.work_remaining == work_remaining);
}

static fp_event next_event(fp_engine *engine) {
    fp_event event;
    assert(fp_engine_next_event(engine, &event, sizeof(event)) == FP_STATUS_OK);
    return event;
}

static fp_event expect_event(fp_engine *engine, uint32_t kind, fp_document_id document, fp_request_id request) {
    fp_event event = next_event(engine);
    assert(event.kind == kind && event.document_id == document && event.request_id == request);
    assert(event.request_kind == FP_REQUEST_RESOURCE && event.request_version == FP_RESOURCE_REQUEST_VERSION);
    return event;
}

static void expect_no_event(fp_engine *engine) {
    fp_event event = next_event(engine);
    assert(event.kind == FP_EVENT_NONE && event.document_id == 0 && event.url == NULL);
}

static void drain(fp_engine *engine) {
    while (next_event(engine).kind != FP_EVENT_NONE) {
    }
}

static void destroy_engine(fp_engine *engine) {
    assert(fp_engine_destroy(engine) == FP_STATUS_OK);
}

/* Every document call with an unknown document returns FP_STATUS_UNKNOWN_ID and writes no output. */
static void expect_unknown_document(fp_engine *engine, fp_document_id document) {
    fp_document_info info;
    memset(&info, 0xA5, sizeof(info));
    assert(fp_document_get(engine, document, &info, sizeof(info)) == FP_STATUS_UNKNOWN_ID);
    assert(is_filled(&info, sizeof(info), 0xA5));
    assert(fp_document_destroy(engine, document) == FP_STATUS_UNKNOWN_ID);
    fp_request_id request = 0x5E0;
    assert(fp_document_load(engine, document, (const uint8_t *)"u", 1, &request) == FP_STATUS_UNKNOWN_ID);
    assert(request == 0x5E0);
}

/* Every request call with an unknown request returns FP_STATUS_UNKNOWN_ID. */
static void expect_unknown_request(fp_engine *engine, fp_request_id request) {
    fp_response answer = response(request, "body");
    assert(fp_request_respond(engine, &answer) == FP_STATUS_UNKNOWN_ID);
    assert(fp_request_reject(engine, request, FP_REJECT_UNSUPPORTED_VERSION) == FP_STATUS_UNKNOWN_ID);
    assert(fp_request_cancel(engine, request) == FP_STATUS_UNKNOWN_ID);
}

/* Scenario unknown-identifier: zero, never-issued, and other-family identifiers return FP_STATUS_UNKNOWN_ID. */
static void scenario_unknown_identifier(void) {
    fp_engine *engine = create_engine(4, 16);
    fp_document_id document = create_document(engine);
    fp_request_id request = load(engine, document, "https://example.test/unknown");
    drain(engine);
    const uint64_t unknown[] = {0, UINT64_MAX};
    for (size_t index = 0; index < sizeof(unknown) / sizeof(unknown[0]); index += 1) {
        expect_unknown_document(engine, unknown[index]);
        expect_unknown_request(engine, unknown[index]);
    }
    /* Document and request identifiers come from one sequence, so one family never names the other. */
    expect_unknown_document(engine, request);
    expect_unknown_request(engine, document);
    expect_queues(engine, 0, 0);
    assert(document_state(engine, document) == FP_DOCUMENT_LOADING);
    respond(engine, request, "known");
    destroy_engine(engine);
}

/* Scenario foreign-identifier: identifiers from another engine return FP_STATUS_UNKNOWN_ID. */
static void scenario_foreign_identifier(void) {
    fp_engine *a = create_engine(4, 16);
    fp_engine *b = create_engine(4, 16);
    fp_document_id document = create_document(a);
    fp_request_id request = load(a, document, "https://example.test/foreign");
    fp_document_id own = create_document(b);
    expect_unknown_document(b, document);
    expect_unknown_request(b, request);
    expect_queues(a, 2, 0);
    expect_queues(b, 0, 0);
    assert(document_state(a, document) == FP_DOCUMENT_LOADING);
    assert(document_state(b, own) == FP_DOCUMENT_EMPTY);
    respond(a, request, "home");
    destroy_engine(b);
    destroy_engine(a);
}

/* Scenario retired-identifier: a destroyed document and an ended request return FP_STATUS_UNKNOWN_ID. */
static void scenario_retired_identifier(void) {
    fp_engine *engine = create_engine(4, 16);
    fp_document_id destroyed = create_document(engine);
    fp_request_id orphaned = load(engine, destroyed, "https://example.test/destroyed");
    assert(fp_document_destroy(engine, destroyed) == FP_STATUS_OK);
    expect_unknown_document(engine, destroyed);
    expect_unknown_request(engine, orphaned);

    fp_document_id document = create_document(engine);
    fp_request_id replaced = load(engine, document, "https://example.test/first");
    fp_request_id answered = load(engine, document, "https://example.test/second");
    expect_unknown_request(engine, replaced);
    respond(engine, answered, "done");
    assert(step(engine, 8).applied == 1);
    expect_unknown_request(engine, answered);
    assert(document_state(engine, document) == FP_DOCUMENT_LOADED);
    destroy_engine(engine);
}

/* Every function called from a thread that does not own the engine. */
struct foreign_calls {
    fp_engine *engine;
    fp_document_id document;
    fp_request_id request;
    uint32_t statuses[10];
    uint32_t revision;
    uint32_t capabilities_status;
    fp_document_id document_out;
    fp_request_id request_out;
    fp_document_info info;
    fp_step_outcome outcome;
    fp_event event;
};

static void run_foreign_calls(struct foreign_calls *calls) {
    fp_engine *engine = calls->engine;
    fp_response answer = response(calls->request, "foreign");
    fp_capabilities capabilities;
    calls->revision = fp_abi_revision();
    calls->capabilities_status = fp_query_capabilities(&capabilities, sizeof(capabilities));
    calls->statuses[0] = fp_document_create(engine, &calls->document_out);
    calls->statuses[1] = fp_document_destroy(engine, calls->document);
    calls->statuses[2] = fp_document_get(engine, calls->document, &calls->info, sizeof(calls->info));
    calls->statuses[3] = fp_document_load(engine, calls->document, (const uint8_t *)"u", 1, &calls->request_out);
    calls->statuses[4] = fp_request_respond(engine, &answer);
    calls->statuses[5] = fp_request_reject(engine, calls->request, FP_REJECT_UNSUPPORTED_VERSION);
    calls->statuses[6] = fp_request_cancel(engine, calls->request);
    calls->statuses[7] = fp_engine_step(engine, 8, &calls->outcome, sizeof(calls->outcome));
    calls->statuses[8] = fp_engine_next_event(engine, &calls->event, sizeof(calls->event));
    calls->statuses[9] = fp_engine_destroy(engine);
}

#if defined(_WIN32)
static DWORD WINAPI foreign_thread(LPVOID argument) {
    run_foreign_calls(argument);
    return 0;
}

static void run_on_other_thread(struct foreign_calls *calls) {
    HANDLE thread = CreateThread(NULL, 0, foreign_thread, calls, 0, NULL);
    assert(thread != NULL);
    assert(WaitForSingleObject(thread, INFINITE) == WAIT_OBJECT_0);
    assert(CloseHandle(thread));
}
#else
static void *foreign_thread(void *argument) {
    run_foreign_calls(argument);
    return NULL;
}

static void run_on_other_thread(struct foreign_calls *calls) {
    pthread_t thread;
    assert(pthread_create(&thread, NULL, foreign_thread, calls) == 0);
    assert(pthread_join(thread, NULL) == 0);
}
#endif

/* Scenario wrong-thread: every owner-thread function returns FP_STATUS_WRONG_THREAD from another thread. */
static void scenario_wrong_thread(void) {
    fp_engine *engine = create_engine(4, 16);
    fp_document_id document = create_document(engine);
    fp_request_id request = load(engine, document, "https://example.test/thread");
    struct foreign_calls calls;
    memset(&calls, 0xA5, sizeof(calls));
    calls.engine = engine;
    calls.document = document;
    calls.request = request;
    calls.document_out = 77;
    calls.request_out = 78;
    run_on_other_thread(&calls);

    for (size_t index = 0; index < sizeof(calls.statuses) / sizeof(calls.statuses[0]); index += 1) {
        assert(calls.statuses[index] == FP_STATUS_WRONG_THREAD);
    }
    assert(calls.revision == FP_ABI_REVISION && calls.capabilities_status == FP_STATUS_OK);
    assert(calls.document_out == 77 && calls.request_out == 78);
    assert(is_filled(&calls.info, sizeof(calls.info), 0xA5));
    assert(is_filled(&calls.outcome, sizeof(calls.outcome), 0xA5));
    assert(is_filled(&calls.event, sizeof(calls.event), 0xA5));
    expect_queues(engine, 2, 0);
    assert(document_state(engine, document) == FP_DOCUMENT_LOADING);
    respond(engine, request, "owner");
    destroy_engine(engine);
}

/* Scenario cancel-before-answer-queued: a host cancellation queues input, and the step fails the document. */
static void scenario_cancel_before_answer_queued(void) {
    fp_engine *engine = create_engine(4, 16);
    fp_document_id document = create_document(engine);
    fp_request_id request = load(engine, document, "https://example.test/cancel-before");
    drain(engine);

    assert(fp_request_cancel(engine, request) == FP_STATUS_OK);
    assert(document_state(engine, document) == FP_DOCUMENT_LOADING);
    fp_step_outcome outcome = step(engine, 8);
    assert(outcome.applied == 1 && outcome.work_remaining == 0 && outcome.events_ready == 2);
    assert(document_state(engine, document) == FP_DOCUMENT_FAILED);
    expect_event(engine, FP_EVENT_REQUEST_CANCELLED, document, request);
    fp_event change = expect_event(engine, FP_EVENT_DOCUMENT_STATE_CHANGED, document, request);
    assert(change.document_state == FP_DOCUMENT_FAILED && change.reject_reason == 0);
    expect_no_event(engine);
    expect_unknown_request(engine, request);
    destroy_engine(engine);
}

/* Scenario cancel-after-answer-queued: a queued answer blocks a host cancellation, and an engine cancellation discards it. */
static void scenario_cancel_after_answer_queued(void) {
    fp_engine *engine = create_engine(4, 16);
    fp_document_id document = create_document(engine);
    fp_request_id first = load(engine, document, "https://example.test/cancel-after");
    drain(engine);

    respond(engine, first, "queued");
    fp_response again = response(first, "again");
    assert(fp_request_cancel(engine, first) == FP_STATUS_INVALID_STATE);
    assert(fp_request_reject(engine, first, FP_REJECT_UNSUPPORTED_VERSION) == FP_STATUS_INVALID_STATE);
    assert(fp_request_respond(engine, &again) == FP_STATUS_INVALID_STATE);

    fp_request_id second = load(engine, document, "https://example.test/cancel-after-reload");
    expect_event(engine, FP_EVENT_REQUEST_CANCELLED, document, first);
    expect_event(engine, FP_EVENT_REQUEST_ISSUED, document, second);
    expect_no_event(engine);
    fp_step_outcome outcome = step(engine, 8);
    assert(outcome.applied == 0 && outcome.work_remaining == 0);
    assert(document_state(engine, document) == FP_DOCUMENT_LOADING);
    expect_unknown_request(engine, first);

    respond(engine, second, "second");
    assert(step(engine, 8).applied == 1);
    fp_document_info info = document_info(engine, document);
    assert(info.state == FP_DOCUMENT_LOADED && info.body_len == 6 && memcmp(info.body, "second", 6) == 0);
    destroy_engine(engine);
}

/* Scenario document-teardown-outstanding: destroying a document cancels its request and discards its answer. */
static void scenario_document_teardown_outstanding(void) {
    fp_engine *engine = create_engine(4, 16);
    fp_document_id doomed = create_document(engine);
    fp_request_id doomed_request = load(engine, doomed, "https://example.test/doomed");
    respond(engine, doomed_request, "discarded");
    fp_document_id kept = create_document(engine);
    fp_request_id kept_request = load(engine, kept, "https://example.test/kept");

    assert(fp_document_destroy(engine, doomed) == FP_STATUS_OK);
    fp_event issued = expect_event(engine, FP_EVENT_REQUEST_ISSUED, doomed, doomed_request);
    assert(issued.url == NULL && issued.url_len == 0);
    expect_event(engine, FP_EVENT_DOCUMENT_STATE_CHANGED, doomed, doomed_request);
    expect_event(engine, FP_EVENT_REQUEST_ISSUED, kept, kept_request);
    expect_event(engine, FP_EVENT_DOCUMENT_STATE_CHANGED, kept, kept_request);
    expect_event(engine, FP_EVENT_REQUEST_CANCELLED, doomed, doomed_request);
    expect_no_event(engine);

    fp_step_outcome outcome = step(engine, 8);
    assert(outcome.applied == 0 && outcome.work_remaining == 0);
    expect_unknown_document(engine, doomed);
    expect_unknown_request(engine, doomed_request);
    assert(document_state(engine, kept) == FP_DOCUMENT_LOADING);
    respond(engine, kept_request, "kept");
    destroy_engine(engine);
}

/* Scenario engine-teardown-outstanding: destroying an engine with requests, answers, bodies, and events succeeds. */
static void scenario_engine_teardown_outstanding(void) {
    fp_engine *engine = create_engine(4, 16);
    fp_document_id answered = create_document(engine);
    respond(engine, load(engine, answered, "https://example.test/answered"), "queued");
    fp_document_id outstanding = create_document(engine);
    load(engine, outstanding, "https://example.test/outstanding");
    fp_document_id loaded = create_document(engine);
    respond(engine, load(engine, loaded, "https://example.test/loaded"), "body");
    assert(step(engine, 8).applied == 2);
    respond(engine, load(engine, answered, "https://example.test/requeued"), "pending");
    fp_step_outcome outcome = step(engine, 0);
    assert(outcome.work_remaining == 1 && outcome.events_ready > 0);
    assert(fp_engine_destroy(engine) == FP_STATUS_OK);
}

/* Scenario null-required-pointer: a null required pointer returns FP_STATUS_INVALID_ARGUMENT and writes nothing. */
static void scenario_null_required_pointer(void) {
    fp_engine_options options = {sizeof(fp_engine_options), 4, 16};
    fp_engine *untouched = (fp_engine *)&options;
    assert(fp_query_capabilities(NULL, sizeof(fp_capabilities)) == FP_STATUS_INVALID_ARGUMENT);
    assert(fp_engine_create(NULL, &untouched) == FP_STATUS_INVALID_ARGUMENT);
    assert(untouched == (fp_engine *)&options);
    assert(fp_engine_create(&options, NULL) == FP_STATUS_INVALID_ARGUMENT);

    fp_engine *engine = create_engine(4, 16);
    fp_document_id document = create_document(engine);
    fp_request_id request = load(engine, document, "https://example.test/null");
    respond(engine, load(engine, create_document(engine), "https://example.test/queued"), "queued");

    fp_document_id document_out = 0xD0C;
    fp_request_id request_out = 0x5E0;
    fp_document_info info;
    fp_step_outcome outcome;
    fp_event event;
    memset(&info, 0xA5, sizeof(info));
    memset(&outcome, 0xA5, sizeof(outcome));
    memset(&event, 0xA5, sizeof(event));
    fp_response answer = response(request, "null");
    fp_response null_body = response(request, "x");
    null_body.body = NULL;
    const uint32_t statuses[] = {
        fp_engine_destroy(NULL),
        fp_document_create(NULL, &document_out),
        fp_document_destroy(NULL, document),
        fp_document_get(NULL, document, &info, sizeof(info)),
        fp_document_load(NULL, document, (const uint8_t *)"u", 1, &request_out),
        fp_request_respond(NULL, &answer),
        fp_request_reject(NULL, request, FP_REJECT_UNSUPPORTED_VERSION),
        fp_request_cancel(NULL, request),
        fp_engine_step(NULL, 8, &outcome, sizeof(outcome)),
        fp_engine_next_event(NULL, &event, sizeof(event)),
        fp_document_create(engine, NULL),
        fp_document_get(engine, document, NULL, sizeof(info)),
        fp_document_load(engine, document, NULL, 0, &request_out),
        fp_document_load(engine, document, (const uint8_t *)"u", 1, NULL),
        fp_request_respond(engine, NULL),
        fp_request_respond(engine, &null_body),
        fp_engine_step(engine, 8, NULL, sizeof(outcome)),
        fp_engine_next_event(engine, NULL, sizeof(event)),
    };
    for (size_t index = 0; index < sizeof(statuses) / sizeof(statuses[0]); index += 1) {
        assert(statuses[index] == FP_STATUS_INVALID_ARGUMENT);
    }

    assert(document_out == 0xD0C && request_out == 0x5E0);
    assert(is_filled(&info, sizeof(info), 0xA5));
    assert(is_filled(&outcome, sizeof(outcome), 0xA5));
    assert(is_filled(&event, sizeof(event), 0xA5));
    expect_queues(engine, 4, 1);
    assert(document_state(engine, document) == FP_DOCUMENT_LOADING);
    respond(engine, request, "valid");
    destroy_engine(engine);
}

/* Scenario short-structure: a structure or output size below the declared size returns FP_STATUS_INVALID_ARGUMENT. */
static void scenario_short_structure(void) {
    fp_engine_options options = {sizeof(fp_engine_options) - 1, 4, 16};
    fp_engine *untouched = (fp_engine *)&options;
    assert(fp_engine_create(&options, &untouched) == FP_STATUS_INVALID_ARGUMENT);
    assert(untouched == (fp_engine *)&options);
    fp_capabilities capabilities;
    memset(&capabilities, 0xA5, sizeof(capabilities));
    assert(fp_query_capabilities(&capabilities, sizeof(capabilities) - 1) == FP_STATUS_INVALID_ARGUMENT);
    assert(fp_query_capabilities(&capabilities, 0) == FP_STATUS_INVALID_ARGUMENT);
    assert(is_filled(&capabilities, sizeof(capabilities), 0xA5));

    fp_engine *engine = create_engine(4, 16);
    fp_document_id document = create_document(engine);
    fp_request_id request = load(engine, document, "https://example.test/short");
    respond(engine, load(engine, create_document(engine), "https://example.test/short-queued"), "queued");

    fp_response short_answer = response(request, "short");
    short_answer.struct_size = sizeof(fp_response) - 1;
    assert(fp_request_respond(engine, &short_answer) == FP_STATUS_INVALID_ARGUMENT);
    fp_document_info info;
    fp_step_outcome outcome;
    fp_event event;
    memset(&info, 0xA5, sizeof(info));
    memset(&outcome, 0xA5, sizeof(outcome));
    memset(&event, 0xA5, sizeof(event));
    assert(fp_document_get(engine, document, &info, sizeof(info) - 1) == FP_STATUS_INVALID_ARGUMENT);
    assert(fp_engine_step(engine, 8, &outcome, sizeof(outcome) - 1) == FP_STATUS_INVALID_ARGUMENT);
    assert(fp_engine_next_event(engine, &event, sizeof(event) - 1) == FP_STATUS_INVALID_ARGUMENT);
    assert(fp_engine_next_event(engine, &event, 0) == FP_STATUS_INVALID_ARGUMENT);
    assert(is_filled(&info, sizeof(info), 0xA5));
    assert(is_filled(&outcome, sizeof(outcome), 0xA5));
    assert(is_filled(&event, sizeof(event), 0xA5));

    expect_queues(engine, 4, 1);
    assert(document_state(engine, document) == FP_DOCUMENT_LOADING);
    respond(engine, request, "full");
    destroy_engine(engine);
}

/* Scenario response-body-bound: a body beyond max_response_body_bytes returns FP_STATUS_LIMIT_EXCEEDED. */
static void scenario_response_body_bound(void) {
    fp_engine *engine = create_engine(4, 16);
    fp_document_id document = create_document(engine);
    fp_request_id request = load(engine, document, "https://example.test/body");
    fp_response oversized = response(request, "seventeen bytes!!");
    assert(oversized.body_len == 17);
    assert(fp_request_respond(engine, &oversized) == FP_STATUS_LIMIT_EXCEEDED);
    expect_queues(engine, 2, 0);

    respond(engine, request, "sixteen bytes!!!");
    assert(step(engine, 8).applied == 1);
    fp_document_info info = document_info(engine, document);
    assert(info.state == FP_DOCUMENT_LOADED && info.body_len == 16);
    assert(memcmp(info.body, "sixteen bytes!!!", 16) == 0);
    destroy_engine(engine);
}

/* Scenario load-bound: a load beyond max_outstanding_requests returns FP_STATUS_LIMIT_EXCEEDED. */
static void scenario_load_bound(void) {
    static const char url[] = "https://example.test/c";
    fp_engine *engine = create_engine(2, 16);
    fp_document_id a = create_document(engine);
    fp_document_id b = create_document(engine);
    fp_document_id c = create_document(engine);
    load(engine, a, "https://example.test/a");
    fp_request_id b_request = load(engine, b, "https://example.test/b");

    fp_request_id out = 0x5E0;
    assert(fp_document_load(engine, c, (const uint8_t *)url, strlen(url), &out) == FP_STATUS_LIMIT_EXCEEDED);
    assert(out == 0x5E0);
    expect_queues(engine, 4, 0);
    assert(document_state(engine, c) == FP_DOCUMENT_EMPTY);

    load(engine, a, "https://example.test/a-again");
    respond(engine, b_request, "b");
    assert(step(engine, 8).applied == 1);
    load(engine, c, url);
    assert(document_state(engine, c) == FP_DOCUMENT_LOADING);
    destroy_engine(engine);
}

int main(void) {
    check_capabilities();
    check_document_lifecycle();
    scenario_unknown_identifier();
    scenario_foreign_identifier();
    scenario_retired_identifier();
    scenario_wrong_thread();
    scenario_cancel_before_answer_queued();
    scenario_cancel_after_answer_queued();
    scenario_document_teardown_outstanding();
    scenario_engine_teardown_outstanding();
    scenario_null_required_pointer();
    scenario_short_structure();
    scenario_response_body_bound();
    scenario_load_bound();
    return 0;
}
