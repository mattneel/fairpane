#ifndef FAIRPANE_H
#define FAIRPANE_H

#include <stddef.h>
#include <stdint.h>

#if defined(_WIN32) && defined(FAIRPANE_SHARED)
#  if defined(FAIRPANE_BUILD)
#    define FP_API __declspec(dllexport)
#  else
#    define FP_API __declspec(dllimport)
#  endif
#else
#  define FP_API
#endif

#ifdef __cplusplus
extern "C" {
#endif

/* Experimental ABI revision zero. No stability promise exists yet.
 * See api/README.md for ownership rules and lifetimes.
 */

/* Status codes. Every function except fp_abi_revision returns one. */
#define FP_STATUS_OK UINT32_C(0)
/* A null required pointer, a short structure or output size, or an unknown enumeration value. */
#define FP_STATUS_INVALID_ARGUMENT UINT32_C(1)
/* The identifier is not live in this engine. */
#define FP_STATUS_UNKNOWN_ID UINT32_C(2)
/* The request already has a queued answer. */
#define FP_STATUS_INVALID_STATE UINT32_C(3)
/* The response version differs from the request version. */
#define FP_STATUS_UNSUPPORTED_VERSION UINT32_C(4)
/* A request bound, a body bound, or an identifier space was exhausted. */
#define FP_STATUS_LIMIT_EXCEEDED UINT32_C(5)
#define FP_STATUS_OUT_OF_MEMORY UINT32_C(6)
/* The caller is not the thread that created the engine. */
#define FP_STATUS_WRONG_THREAD UINT32_C(7)

/* Document states. */
#define FP_DOCUMENT_EMPTY UINT32_C(1)
#define FP_DOCUMENT_LOADING UINT32_C(2)
#define FP_DOCUMENT_LOADED UINT32_C(3)
#define FP_DOCUMENT_FAILED UINT32_C(4)

/* Host request kinds and versions. */
#define FP_REQUEST_RESOURCE UINT32_C(1)
#define FP_RESOURCE_REQUEST_VERSION UINT32_C(1)

/* Rejection reasons. */
#define FP_REJECT_UNSUPPORTED_VERSION UINT32_C(1)

/* Event kinds. */
#define FP_EVENT_NONE UINT32_C(0)
#define FP_EVENT_REQUEST_ISSUED UINT32_C(1)
#define FP_EVENT_REQUEST_CANCELLED UINT32_C(2)
#define FP_EVENT_DOCUMENT_STATE_CHANGED UINT32_C(3)

/* The next deadline when no deadline exists. No timer exists yet, so every step reports it. */
#define FP_DEADLINE_NONE UINT64_C(0xFFFFFFFFFFFFFFFF)

typedef struct fp_capabilities {
    uint32_t struct_size;
    uint32_t abi_revision;
    uint64_t feature_bits;
} fp_capabilities;

/* An engine. It belongs to the thread that created it. */
typedef struct fp_engine fp_engine;

/* Input. struct_size must be at least sizeof(fp_engine_options). */
typedef struct fp_engine_options {
    uint32_t struct_size;
    /* The maximum number of requests that are outstanding at once. */
    uint32_t max_outstanding_requests;
    /* The maximum size of one response body in bytes. */
    uint64_t max_response_body_bytes;
} fp_engine_options;

/* Output of fp_document_get. */
typedef struct fp_document_info {
    uint32_t struct_size;
    uint32_t state;
    /* The loaded body, or NULL when body_len is zero.
     * The bytes stay readable until the document's next load or its destruction.
     */
    const uint8_t *body;
    size_t body_len;
} fp_document_info;

/* Input. struct_size must be at least sizeof(fp_response). */
typedef struct fp_response {
    uint32_t struct_size;
    /* Must equal the request version. */
    uint32_t version;
    uint64_t request_id;
    /* Borrowed for the call only. May be NULL when body_len is zero. */
    const uint8_t *body;
    size_t body_len;
} fp_response;

/* Output of fp_engine_step. */
typedef struct fp_step_outcome {
    uint32_t struct_size;
    /* One when queued input remains, otherwise zero. */
    uint32_t work_remaining;
    uint64_t applied;
    uint64_t events_ready;
    /* Always FP_DEADLINE_NONE. */
    uint64_t next_deadline;
} fp_step_outcome;

/* Output of fp_engine_next_event. Fields that do not apply to the kind are zero or NULL. */
typedef struct fp_event {
    uint32_t struct_size;
    uint32_t kind;
    uint64_t document_id;
    uint64_t request_id;
    uint32_t request_kind;
    uint32_t request_version;
    /* The new state for FP_EVENT_DOCUMENT_STATE_CHANGED. */
    uint32_t document_state;
    /* The rejection reason when an applied rejection failed the document. */
    uint32_t reject_reason;
    /* For FP_EVENT_REQUEST_ISSUED, the request URL while the request is live, otherwise NULL.
     * The bytes stay readable until the request ends.
     */
    const uint8_t *url;
    size_t url_len;
} fp_event;

FP_API uint32_t fp_abi_revision(void);

/* On success, this function initializes sizeof(fp_capabilities) bytes.
 * The feature mask is zero in the bootstrap.
 * A non-null output pointer must reference a writable, aligned object.
 * On invalid size or null output, no output bytes change.
 */
FP_API uint32_t fp_query_capabilities(fp_capabilities *out, size_t out_size);

/* Creates an engine on the calling thread and stores it in *out_engine. */
FP_API uint32_t fp_engine_create(const fp_engine_options *options, fp_engine **out_engine);

/* Releases the engine and everything it owns, including outstanding requests,
 * queued answers, undrained events, and every borrowed URL and body.
 */
FP_API uint32_t fp_engine_destroy(fp_engine *engine);

/* Creates an empty document and stores its identifier in *out_document. */
FP_API uint32_t fp_document_create(fp_engine *engine, uint64_t *out_document);

/* Releases the document. An outstanding request is cancelled and announced,
 * and its queued answer is discarded.
 */
FP_API uint32_t fp_document_destroy(fp_engine *engine, uint64_t document);

/* Initializes sizeof(fp_document_info) bytes with the document state and body. */
FP_API uint32_t fp_document_get(fp_engine *engine, uint64_t document, fp_document_info *out, size_t out_size);

/* Issues a version 1 resource request for a copy of url and stores its identifier in *out_request.
 * The url buffer is borrowed for the call only and must not be NULL.
 * A load while the document is loading cancels the earlier request.
 */
FP_API uint32_t fp_document_load(fp_engine *engine, uint64_t document, const uint8_t *url, size_t url_len, uint64_t *out_request);

/* Queues a response. The engine copies the body during the call. */
FP_API uint32_t fp_request_respond(fp_engine *engine, const fp_response *response);

/* Queues a rejection with an FP_REJECT_* reason. */
FP_API uint32_t fp_request_reject(fp_engine *engine, uint64_t request, uint32_t reason);

/* Queues the host's withdrawal of a request. */
FP_API uint32_t fp_request_cancel(fp_engine *engine, uint64_t request);

/* Applies up to budget queued answers in arrival order.
 * The budget is an engine scheduling boundary only. It creates no JavaScript task boundary.
 */
FP_API uint32_t fp_engine_step(fp_engine *engine, uint32_t budget, fp_step_outcome *out, size_t out_size);

/* Removes the oldest event and initializes sizeof(fp_event) bytes with it.
 * When no event is ready, the kind is FP_EVENT_NONE.
 */
FP_API uint32_t fp_engine_next_event(fp_engine *engine, fp_event *out, size_t out_size);

#ifdef __cplusplus
}
#endif
#endif
