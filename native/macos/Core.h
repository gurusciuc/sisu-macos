#include <stddef.h>
#include <stdint.h>
void *sisu_core_create(void);
char *sisu_core_command(void *core, const uint8_t *bytes, size_t length);
char *sisu_parse_cookie_export(const uint8_t *bytes, size_t length, int64_t now);
void sisu_core_free(char *response);
void sisu_core_destroy(void *core);
char *sisu_unpack_store_package(const uint8_t *bytes, size_t length, const char *id, const char *destination);
