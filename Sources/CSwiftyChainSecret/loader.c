#include "CSwiftyChainSecret.h"

#if defined(__linux__)

#include <dlfcn.h>
#include <pthread.h>
#include <stdint.h>

/*
 * Mirrors of the public libsecret and GLib ABI used here. libsecret-1.so.0 has kept
 * these layouts and signatures stable since 0.19, which added the binary and
 * SecretRetrievable APIs this file depends on.
 */

typedef int swiftychain_gboolean;
typedef uint32_t swiftychain_gquark;

struct swiftychain_secret_error {
    swiftychain_gquark domain;
    int code;
    char *message;
};

struct swiftychain_secret_list {
    void *data;
    struct swiftychain_secret_list *next;
    struct swiftychain_secret_list *prev;
};

typedef struct {
    const char *name;
    int type;
} swiftychain_schema_attribute;

typedef struct {
    const char *name;
    int flags;
    swiftychain_schema_attribute attributes[32];
    int reserved;
    void *reserved1;
    void *reserved2;
    void *reserved3;
    void *reserved4;
    void *reserved5;
    void *reserved6;
    void *reserved7;
} swiftychain_schema;

#if defined(__LP64__)
_Static_assert(sizeof(swiftychain_schema) == 592, "SecretSchema layout mismatch");
#endif

enum {
    SCHEMA_FLAGS_NONE = 0,
    ATTRIBUTE_STRING = 0,
    ATTRIBUTE_INTEGER = 1,
    SEARCH_ALL = 1 << 1,
    SEARCH_UNLOCK = 1 << 2,
    SEARCH_LOAD_SECRETS = 1 << 3,
    BUS_TYPE_SESSION = 2,
};

static const swiftychain_schema generic_password_schema = {
    "dev.manman.SwiftyChain.GenericPassword",
    SCHEMA_FLAGS_NONE,
    {
        {"service", ATTRIBUTE_STRING},
        {"account", ATTRIBUTE_STRING},
        {"accessGroup", ATTRIBUTE_STRING},
        {NULL, 0},
    },
};

static const swiftychain_schema internet_password_schema = {
    "dev.manman.SwiftyChain.InternetPassword",
    SCHEMA_FLAGS_NONE,
    {
        {"server", ATTRIBUTE_STRING},
        {"account", ATTRIBUTE_STRING},
        {"port", ATTRIBUTE_INTEGER},
        {"path", ATTRIBUTE_STRING},
        {"protocol", ATTRIBUTE_STRING},
        {"authenticationType", ATTRIBUTE_STRING},
        {"accessGroup", ATTRIBUTE_STRING},
        {NULL, 0},
    },
};

static struct {
    swiftychain_gboolean (*store)(
        const swiftychain_schema *,
        swiftychain_secret_attributes *,
        const char *,
        const char *,
        swiftychain_secret_value *,
        swiftychain_secret_cancellable *,
        swiftychain_secret_error **
    );
    swiftychain_secret_value *(*lookup)(
        const swiftychain_schema *,
        swiftychain_secret_attributes *,
        swiftychain_secret_cancellable *,
        swiftychain_secret_error **
    );
    swiftychain_gboolean (*clear)(
        const swiftychain_schema *,
        swiftychain_secret_attributes *,
        swiftychain_secret_cancellable *,
        swiftychain_secret_error **
    );
    swiftychain_secret_list *(*search)(
        const swiftychain_schema *,
        swiftychain_secret_attributes *,
        int,
        swiftychain_secret_cancellable *,
        swiftychain_secret_error **
    );
    swiftychain_secret_attributes *(*item_attributes)(void *);
    char *(*item_label)(void *);
    swiftychain_secret_value *(*item_secret)(void *, swiftychain_secret_cancellable *, swiftychain_secret_error **);
    swiftychain_secret_value *(*value_new)(const char *, ptrdiff_t, const char *);
    const char *(*value_get)(swiftychain_secret_value *, size_t *);
    void (*value_unref)(void *);
    swiftychain_secret_attributes *(*hash_table_new_full)(
        unsigned int (*)(const void *),
        swiftychain_gboolean (*)(const void *, const void *),
        void (*)(void *),
        void (*)(void *)
    );
    swiftychain_gboolean (*hash_table_insert)(swiftychain_secret_attributes *, void *, void *);
    void *(*hash_table_lookup)(swiftychain_secret_attributes *, const void *);
    void (*hash_table_unref)(swiftychain_secret_attributes *);
    unsigned int (*str_hash)(const void *);
    swiftychain_gboolean (*str_equal)(const void *, const void *);
    char *(*strdup)(const char *);
    void (*free)(void *);
    void (*list_free_full)(swiftychain_secret_list *, void (*)(void *));
    void (*object_unref)(void *);
    swiftychain_secret_cancellable *(*cancellable_new)(void);
    void (*cancellable_cancel)(swiftychain_secret_cancellable *);
    void *(*bus_get_sync)(int, swiftychain_secret_cancellable *, swiftychain_secret_error **);
    const char *(*quark_to_string)(swiftychain_gquark);
    void (*error_free)(swiftychain_secret_error *);
} fn;

static swiftychain_secret_load_status load_status = SWIFTYCHAIN_SECRET_LIBRARY_MISSING;
static pthread_once_t load_once = PTHREAD_ONCE_INIT;

#define RESOLVE(field, symbol)                               \
    do {                                                     \
        *(void **)(&fn.field) = dlsym(handle, symbol);       \
        if (fn.field == NULL) {                              \
            load_status = SWIFTYCHAIN_SECRET_SYMBOL_MISSING; \
            return;                                          \
        }                                                    \
    } while (0)

static void load_library(void) {
    void *handle = dlopen("libsecret-1.so.0", RTLD_NOW | RTLD_GLOBAL);
    if (handle == NULL) {
        load_status = SWIFTYCHAIN_SECRET_LIBRARY_MISSING;
        return;
    }
    RESOLVE(store, "secret_password_storev_binary_sync");
    RESOLVE(lookup, "secret_password_lookupv_binary_sync");
    RESOLVE(clear, "secret_password_clearv_sync");
    RESOLVE(search, "secret_password_searchv_sync");
    RESOLVE(item_attributes, "secret_retrievable_get_attributes");
    RESOLVE(item_label, "secret_retrievable_get_label");
    RESOLVE(item_secret, "secret_retrievable_retrieve_secret_sync");
    RESOLVE(value_new, "secret_value_new");
    RESOLVE(value_get, "secret_value_get");
    RESOLVE(value_unref, "secret_value_unref");
    RESOLVE(hash_table_new_full, "g_hash_table_new_full");
    RESOLVE(hash_table_insert, "g_hash_table_insert");
    RESOLVE(hash_table_lookup, "g_hash_table_lookup");
    RESOLVE(hash_table_unref, "g_hash_table_unref");
    RESOLVE(str_hash, "g_str_hash");
    RESOLVE(str_equal, "g_str_equal");
    RESOLVE(strdup, "g_strdup");
    RESOLVE(free, "g_free");
    RESOLVE(list_free_full, "g_list_free_full");
    RESOLVE(object_unref, "g_object_unref");
    RESOLVE(cancellable_new, "g_cancellable_new");
    RESOLVE(cancellable_cancel, "g_cancellable_cancel");
    RESOLVE(bus_get_sync, "g_bus_get_sync");
    RESOLVE(quark_to_string, "g_quark_to_string");
    RESOLVE(error_free, "g_error_free");
    load_status = SWIFTYCHAIN_SECRET_LOADED;
}

static const swiftychain_schema *schema_for(swiftychain_secret_schema_kind kind) {
    return kind == SWIFTYCHAIN_SECRET_INTERNET_PASSWORD ? &internet_password_schema : &generic_password_schema;
}

swiftychain_secret_load_status swiftychain_secret_load(void) {
    pthread_once(&load_once, load_library);
    return load_status;
}

const char *swiftychain_secret_schema_name(swiftychain_secret_schema_kind kind) {
    return schema_for(kind)->name;
}

const char *swiftychain_secret_schema_attribute_name(swiftychain_secret_schema_kind kind, int index) {
    if (index < 0 || index >= 32) {
        return NULL;
    }
    return schema_for(kind)->attributes[index].name;
}

int swiftychain_secret_session_bus_available(swiftychain_secret_error **error) {
    void *connection = fn.bus_get_sync(BUS_TYPE_SESSION, NULL, error);
    if (connection == NULL) {
        return 0;
    }
    fn.object_unref(connection);
    return 1;
}

swiftychain_secret_attributes *swiftychain_secret_attributes_new(void) {
    return fn.hash_table_new_full(fn.str_hash, fn.str_equal, fn.free, fn.free);
}

void swiftychain_secret_attributes_insert(swiftychain_secret_attributes *attributes, const char *key, const char *value) {
    fn.hash_table_insert(attributes, fn.strdup(key), fn.strdup(value));
}

const char *swiftychain_secret_attributes_lookup(swiftychain_secret_attributes *attributes, const char *key) {
    return fn.hash_table_lookup(attributes, key);
}

void swiftychain_secret_attributes_free(swiftychain_secret_attributes *attributes) {
    fn.hash_table_unref(attributes);
}

int swiftychain_secret_store(
    swiftychain_secret_schema_kind kind,
    swiftychain_secret_attributes *attributes,
    const char *label,
    const void *bytes,
    size_t length,
    swiftychain_secret_cancellable *cancellable,
    swiftychain_secret_error **error
) {
    swiftychain_secret_value *value = fn.value_new(bytes, (ptrdiff_t)length, "application/octet-stream");
    swiftychain_gboolean stored = fn.store(schema_for(kind), attributes, NULL, label, value, cancellable, error);
    fn.value_unref(value);
    return stored ? 1 : 0;
}

swiftychain_secret_value *swiftychain_secret_lookup(
    swiftychain_secret_schema_kind kind,
    swiftychain_secret_attributes *attributes,
    swiftychain_secret_cancellable *cancellable,
    swiftychain_secret_error **error
) {
    return fn.lookup(schema_for(kind), attributes, cancellable, error);
}

int swiftychain_secret_clear(
    swiftychain_secret_schema_kind kind,
    swiftychain_secret_attributes *attributes,
    swiftychain_secret_cancellable *cancellable,
    swiftychain_secret_error **error
) {
    return fn.clear(schema_for(kind), attributes, cancellable, error) ? 1 : 0;
}

swiftychain_secret_list *swiftychain_secret_search(
    swiftychain_secret_schema_kind kind,
    swiftychain_secret_attributes *attributes,
    int load_secrets,
    swiftychain_secret_cancellable *cancellable,
    swiftychain_secret_error **error
) {
    int flags = SEARCH_ALL | SEARCH_UNLOCK | (load_secrets ? SEARCH_LOAD_SECRETS : 0);
    return fn.search(schema_for(kind), attributes, flags, cancellable, error);
}

swiftychain_secret_list *swiftychain_secret_list_next(swiftychain_secret_list *list) {
    return list->next;
}

swiftychain_secret_item *swiftychain_secret_list_item(swiftychain_secret_list *list) {
    return list->data;
}

void swiftychain_secret_list_free(swiftychain_secret_list *list) {
    fn.list_free_full(list, fn.object_unref);
}

swiftychain_secret_attributes *swiftychain_secret_item_attributes(swiftychain_secret_item *item) {
    return fn.item_attributes(item);
}

char *swiftychain_secret_item_label(swiftychain_secret_item *item) {
    return fn.item_label(item);
}

swiftychain_secret_value *swiftychain_secret_item_secret(
    swiftychain_secret_item *item,
    swiftychain_secret_cancellable *cancellable,
    swiftychain_secret_error **error
) {
    return fn.item_secret(item, cancellable, error);
}

void swiftychain_secret_string_free(char *string) {
    fn.free(string);
}

const void *swiftychain_secret_value_bytes(swiftychain_secret_value *value, size_t *length) {
    return fn.value_get(value, length);
}

void swiftychain_secret_value_free(swiftychain_secret_value *value) {
    fn.value_unref(value);
}

swiftychain_secret_cancellable *swiftychain_secret_cancellable_new(void) {
    return fn.cancellable_new();
}

void swiftychain_secret_cancellable_cancel(swiftychain_secret_cancellable *cancellable) {
    fn.cancellable_cancel(cancellable);
}

void swiftychain_secret_cancellable_free(swiftychain_secret_cancellable *cancellable) {
    fn.object_unref(cancellable);
}

const char *swiftychain_secret_error_domain(const swiftychain_secret_error *error) {
    return fn.quark_to_string(error->domain);
}

int swiftychain_secret_error_code(const swiftychain_secret_error *error) {
    return error->code;
}

void swiftychain_secret_error_free(swiftychain_secret_error *error) {
    fn.error_free(error);
}

#endif
