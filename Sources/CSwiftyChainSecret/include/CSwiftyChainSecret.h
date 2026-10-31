#ifndef CSWIFTYCHAIN_SECRET_H
#define CSWIFTYCHAIN_SECRET_H

#include <stddef.h>

#if defined(__linux__)

/*
 * A minimal binding to libsecret that loads libsecret-1.so.0 at runtime with dlopen,
 * so SwiftyChain needs no libsecret headers or pkg-config at build time. Every type is
 * opaque to Swift; the loader declares only the libsecret and GLib symbols it uses.
 */

typedef struct swiftychain_secret_error swiftychain_secret_error;
typedef struct swiftychain_secret_attributes swiftychain_secret_attributes;
typedef struct swiftychain_secret_value swiftychain_secret_value;
typedef struct swiftychain_secret_list swiftychain_secret_list;
typedef struct swiftychain_secret_item swiftychain_secret_item;
typedef struct swiftychain_secret_cancellable swiftychain_secret_cancellable;

typedef enum {
    SWIFTYCHAIN_SECRET_LOADED = 0,
    SWIFTYCHAIN_SECRET_LIBRARY_MISSING = 1,
    SWIFTYCHAIN_SECRET_SYMBOL_MISSING = 2,
} swiftychain_secret_load_status;

typedef enum {
    SWIFTYCHAIN_SECRET_GENERIC_PASSWORD = 0,
    SWIFTYCHAIN_SECRET_INTERNET_PASSWORD = 1,
} swiftychain_secret_schema_kind;

/* Loads libsecret once per process. Safe to call from any thread. */
swiftychain_secret_load_status swiftychain_secret_load(void);

/* The schema name and its attribute names, for checking the Swift attribute mapping. */
const char *swiftychain_secret_schema_name(swiftychain_secret_schema_kind kind);
const char *swiftychain_secret_schema_attribute_name(swiftychain_secret_schema_kind kind, int index);

/* Returns 1 when a D-Bus session bus is reachable, otherwise 0 and sets error. */
int swiftychain_secret_session_bus_available(swiftychain_secret_error **error);

swiftychain_secret_attributes *swiftychain_secret_attributes_new(void);
void swiftychain_secret_attributes_insert(swiftychain_secret_attributes *attributes, const char *key, const char *value);
const char *swiftychain_secret_attributes_lookup(swiftychain_secret_attributes *attributes, const char *key);
void swiftychain_secret_attributes_free(swiftychain_secret_attributes *attributes);

int swiftychain_secret_store(
    swiftychain_secret_schema_kind kind,
    swiftychain_secret_attributes *attributes,
    const char *label,
    const void *bytes,
    size_t length,
    swiftychain_secret_cancellable *cancellable,
    swiftychain_secret_error **error
);

/* Returns NULL with no error when nothing matches. */
swiftychain_secret_value *swiftychain_secret_lookup(
    swiftychain_secret_schema_kind kind,
    swiftychain_secret_attributes *attributes,
    swiftychain_secret_cancellable *cancellable,
    swiftychain_secret_error **error
);

/* Returns 1 when items were removed, 0 when nothing matched or on error. */
int swiftychain_secret_clear(
    swiftychain_secret_schema_kind kind,
    swiftychain_secret_attributes *attributes,
    swiftychain_secret_cancellable *cancellable,
    swiftychain_secret_error **error
);

/* Returns every matching item, unlocking as needed. NULL with no error when nothing matches. */
swiftychain_secret_list *swiftychain_secret_search(
    swiftychain_secret_schema_kind kind,
    swiftychain_secret_attributes *attributes,
    int load_secrets,
    swiftychain_secret_cancellable *cancellable,
    swiftychain_secret_error **error
);
swiftychain_secret_list *swiftychain_secret_list_next(swiftychain_secret_list *list);
swiftychain_secret_item *swiftychain_secret_list_item(swiftychain_secret_list *list);
void swiftychain_secret_list_free(swiftychain_secret_list *list);

swiftychain_secret_attributes *swiftychain_secret_item_attributes(swiftychain_secret_item *item);
/* The returned string is owned by the caller; release it with swiftychain_secret_string_free. */
char *swiftychain_secret_item_label(swiftychain_secret_item *item);
swiftychain_secret_value *swiftychain_secret_item_secret(
    swiftychain_secret_item *item,
    swiftychain_secret_cancellable *cancellable,
    swiftychain_secret_error **error
);
void swiftychain_secret_string_free(char *string);

const void *swiftychain_secret_value_bytes(swiftychain_secret_value *value, size_t *length);
void swiftychain_secret_value_free(swiftychain_secret_value *value);

swiftychain_secret_cancellable *swiftychain_secret_cancellable_new(void);
void swiftychain_secret_cancellable_cancel(swiftychain_secret_cancellable *cancellable);
void swiftychain_secret_cancellable_free(swiftychain_secret_cancellable *cancellable);

const char *swiftychain_secret_error_domain(const swiftychain_secret_error *error);
int swiftychain_secret_error_code(const swiftychain_secret_error *error);
void swiftychain_secret_error_free(swiftychain_secret_error *error);

#endif

#endif
