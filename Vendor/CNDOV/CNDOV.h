#pragma once

#include <stddef.h>

void *ndov_client_create(void);
int ndov_client_receive(void *client, char *output, size_t capacity);
void ndov_client_destroy(void *client);

