/*
 * Telvm certified lab: C + libmicrohttpd. GET / -> JSON 200 on port 3333.
 */

#include <microhttpd.h>
#include <stdio.h>
#include <string.h>
#include <unistd.h>

#define RESPONSE "{\"status\":\"ok\",\"service\":\"telvm-lab\",\"probe\":\"/\"}"

static enum MHD_Result answer(void *cls, struct MHD_Connection *connection,
                              const char *url, const char *method,
                              const char *version,
                              const char *upload_data, size_t *upload_data_size,
                              void **con_cls) {
  (void)cls;
  (void)url;
  (void)version;
  (void)upload_data;
  (void)upload_data_size;
  (void)con_cls;

  if (strcmp(method, "GET") != 0)
    return MHD_NO;

  struct MHD_Response *response =
      MHD_create_response_from_buffer(strlen(RESPONSE), (void *)RESPONSE,
                                      MHD_RESPMEM_PERSISTENT);

  if (response == NULL)
    return MHD_NO;

  MHD_add_response_header(response, "Content-Type", "application/json");
  enum MHD_Result ret =
      MHD_queue_response(connection, MHD_HTTP_OK, response);
  MHD_destroy_response(response);
  return ret;
}

int main(void) {
  struct MHD_Daemon *d =
      MHD_start_daemon(MHD_USE_INTERNAL_POLLING_THREAD, 3333, NULL, NULL,
                       &answer, NULL, MHD_OPTION_END);

  if (d == NULL) {
    fprintf(stderr, "MHD_start_daemon failed\n");
    return 1;
  }

  for (;;)
    pause();

  return 0;
}
