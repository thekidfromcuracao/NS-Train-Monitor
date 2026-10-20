#include "CNDOV.h"
#include "zmq.h"
#include <errno.h>
#include <stdlib.h>
#include <string.h>
#include <zlib.h>

typedef struct {
    void *context;
    void *socket;
} ndov_client;

void *ndov_client_create(void) {
    ndov_client *client = calloc(1, sizeof(ndov_client));
    if (!client) return NULL;
    client->context = zmq_ctx_new();
    client->socket = client->context ? zmq_socket(client->context, ZMQ_SUB) : NULL;
    if (!client->socket) { ndov_client_destroy(client); return NULL; }

    const char *topic = "/RIG/InfoPlusDVSInterface4";
    int timeout = 1000;
    int linger = 0;
    zmq_setsockopt(client->socket, ZMQ_SUBSCRIBE, topic, strlen(topic));
    zmq_setsockopt(client->socket, ZMQ_RCVTIMEO, &timeout, sizeof(timeout));
    zmq_setsockopt(client->socket, ZMQ_LINGER, &linger, sizeof(linger));
    if (zmq_connect(client->socket, "tcp://pubsub.besteffort.ndovloket.nl:7664") != 0) {
        ndov_client_destroy(client);
        return NULL;
    }
    return client;
}

static int receive_frame(void *socket, zmq_msg_t *message) {
    if (zmq_msg_init(message) != 0) return -2;
    if (zmq_msg_recv(message, socket, 0) < 0) {
        int result = (errno == EAGAIN || errno == EINTR) ? -1 : -2;
        zmq_msg_close(message);
        return result;
    }
    return 0;
}

int ndov_client_receive(void *opaque, char *output, size_t capacity) {
    if (!opaque || !output || capacity < 2) return -2;
    ndov_client *client = opaque;
    zmq_msg_t topic;
    int result = receive_frame(client->socket, &topic);
    if (result != 0) return result;
    int more = zmq_msg_more(&topic);
    zmq_msg_close(&topic);
    if (!more) return -2;

    zmq_msg_t payload;
    result = receive_frame(client->socket, &payload);
    if (result != 0) return result;
    const unsigned char *bytes = zmq_msg_data(&payload);
    size_t size = zmq_msg_size(&payload);

    if (size >= 2 && bytes[0] == 0x1f && bytes[1] == 0x8b) {
        z_stream stream;
        memset(&stream, 0, sizeof(stream));
        stream.next_in = (Bytef *)bytes;
        stream.avail_in = (uInt)size;
        stream.next_out = (Bytef *)output;
        stream.avail_out = (uInt)(capacity - 1);
        if (inflateInit2(&stream, 16 + MAX_WBITS) != Z_OK) result = -2;
        else {
            int status = inflate(&stream, Z_FINISH);
            result = (status == Z_STREAM_END) ? (int)stream.total_out : -2;
            inflateEnd(&stream);
        }
    } else {
        size_t copied = size < capacity - 1 ? size : capacity - 1;
        memcpy(output, bytes, copied);
        result = (int)copied;
    }
    if (result >= 0) output[result] = '\0';
    zmq_msg_close(&payload);
    return result;
}

void ndov_client_destroy(void *opaque) {
    if (!opaque) return;
    ndov_client *client = opaque;
    if (client->socket) zmq_close(client->socket);
    if (client->context) zmq_ctx_term(client->context);
    free(client);
}

