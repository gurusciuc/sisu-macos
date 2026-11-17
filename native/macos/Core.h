#include <stddef.h>
#include <stdint.h>
void *sisu_core_create(void);
char *sisu_core_command(void *core, const uint8_t *bytes, size_t length);
void sisu_core_free(char *response);
void sisu_core_destroy(void *core);
