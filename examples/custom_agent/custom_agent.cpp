/**
 * @file    main.c
 * @brief   Main function and RPMSG example application.
 * @date    2020.10.27
 * @author  Copyright (c) 2020, eForce Co., Ltd. All rights reserved.
 * @license SPDX-License-Identifier: BSD-3-Clause
 *
 ****************************************************************************
 * @par     History
 *          - rev 1.0 (2019.10.23) nozaki
 *            Initial version.
 *          - rev 1.1 (2020.01.28) Imada
 *            Modification for OpenAMP 2018.10.
 *          - rev 1.2 (2020.10.27) Imada
 *            Added the license description.
 ****************************************************************************
 */
#include <pthread.h>
#include <signal.h>

#include <cstring>
#include <iomanip>
#include <iostream>
#include <queue>
#include <uxr/agent/transport/custom/CustomAgent.hpp>
#include <uxr/agent/transport/endpoint/IPv4EndPoint.hpp>
#include <vector>

extern "C" {
#include "helper.h"
#include "metal/alloc.h"
#include "metal/utilities.h"
#include "openamp/open_amp.h"
#include "platform_info.h"
#include "rsc_table.h"
}

#define SHUTDOWN_MSG (0xEF56A55A)

// #define RPMSG_ADDR_AN  0xFFFFFFFE
#define LOCAL_EPT_ADDR 0x0
#define REMOTE_EPT_ADDR 0x0

#ifndef max
#define max(a, b)           \
  ({                        \
    __typeof__(a) _a = (a); \
    __typeof__(b) _b = (b); \
    (_a > _b) ? _a : _b;    \
  })
#endif

#ifndef ARRAY_SIZE
#define ARRAY_SIZE(x) (sizeof(x) / sizeof(x[0]))
#endif

/* Payload definition */
struct _payload
{
  unsigned long num;
  unsigned long size;
  unsigned char data[];
};

/* Payload information */
struct payload_info
{
  int minnum;
  int maxnum;
  int num;
};

/* Internal functions */
static void rpmsg_service_bind(struct rpmsg_device * rdev, const char * name, uint32_t dest);
static void rpmsg_service_unbind(struct rpmsg_endpoint * ept);
static int rpmsg_service_cb(
  struct rpmsg_endpoint * rp_ept, void * data, size_t len, uint32_t src, void * priv);
static void register_handler(int signum, void (*handler)(int));
static void stop_handler(int signum);
static void init_cond(void);

/* Globals */
static struct rpmsg_endpoint rp_ept = {0};
static struct rpmsg_endpoint global_ept = {0};
static struct rpmsg_device * rpdev = NULL;
static struct remoteproc * rproc = NULL;
static struct _payload * i_payload;
static int rnum = 0;
static int err_cnt = 0;
static const char * svc_name = NULL;
int force_stop = 0;
pthread_cond_t cond[MBX_CH_NUM];
pthread_mutex_t mutex, rsc_mutex;
pthread_key_t thkey;
bool valid_thread[MBX_CH_NUM] = {false};
std::queue<std::vector<uint8_t>> message_queue;
pthread_t poll_thread;
static volatile int stop_polling = 0;
int * thvalp = (int *)malloc(sizeof(int));

#define MESSAGE_LENGTH 1

/** for information */
pid_t g_tid_cm33 = 0;
pid_t g_tid_cr8_0 = 0;
pid_t g_tid_cr8_1 = 0;

struct comm_arg ids[] = {
  {NULL, 0, UIO_RECEIVER1}, {NULL, 1, UIO_RECEIVER1}, {NULL, 0, UIO_RECEIVER2},
  {NULL, 1, UIO_RECEIVER2}, {NULL, 0, UIO_RECEIVER3}, {NULL, 1, UIO_RECEIVER3},

};

int communicate_core = 3;  // 3 for cr8 chanel 0

/* External functions */
extern int init_system(void);
extern void cleanup_system(void);

static void rpmsg_service_bind(struct rpmsg_device * rdev, const char * name, uint32_t dest)
{
  LPRINTF("new endpoint notification is received.");
  if (strcmp(name, svc_name)) {
    LPERROR("Unexpected name service %s.", name);
  } else
    (void)rpmsg_create_ept(
      &rp_ept, rdev, svc_name, APP_EPT_ADDR, 0x0, rpmsg_service_cb, rpmsg_service_unbind);
  return;
}

static void rpmsg_service_unbind(struct rpmsg_endpoint * ept)
{
  (void)ept;
  /* service 0 */
  rpmsg_destroy_ept(&rp_ept);
  memset(&rp_ept, 0x0, sizeof(struct rpmsg_endpoint));
  return;
}

static int rpmsg_service_cb(
  struct rpmsg_endpoint * cb_rp_ept, void * data, size_t len, uint32_t src, void * priv)
{
  (void)rp_ept;
  (void)src;
  (void)priv;

  if (!data || len == 0) {
    LPRINTF("Error: Invalid data pointer or length is 0\n");
    return -1;
  }

  // LPRINTF("Received Data: ");
  uint8_t * byte_data = static_cast<uint8_t *>(data);

  pthread_mutex_lock(&rsc_mutex);

  try {
    std::vector<uint8_t> message;
    for (size_t i = 0; i < len; i++) {
      message.push_back(byte_data[i]);
      // temp = i;
    }
    // LPRINTF("message push to buffer %d\n",temp+1);
    message_queue.push(message);

  } catch (const std::exception & e) {
    LPRINTF("Exception occurred: %s\n", e.what());
  } catch (...) {
    LPRINTF("Unknown error occurred while processing message\n");
  }

  // Unlock the queue
  pthread_mutex_unlock(&rsc_mutex);

  return 0;
}

static void init_cond(void)
{
#ifdef __linux__
  int i;
  pthread_mutex_init(&mutex, NULL);
  pthread_mutex_init(&rsc_mutex, NULL);
  for (i = 0; i < MBX_CH_NUM; i++) {
    pthread_cond_init(&cond[i], NULL);
  }
  pthread_key_create(&thkey, free);
#endif
}

/**
 * @fn set_tid
 * @brief set thread information
 */
static void set_tid(int target)
{
  pid_t tid = syscall(SYS_gettid);
  if (target == UIO_RECEIVER1) {
    g_tid_cm33 = tid;
  } else if (target == UIO_RECEIVER2) {
    g_tid_cr8_0 = tid;
  } else if (target == UIO_RECEIVER3) {
    g_tid_cr8_1 = tid;
  }
}

/**
 * @fn clear_tid
 * @brief clear thread information
 */
static void clear_tid(void)
{
  pid_t tid = syscall(SYS_gettid);
  if (tid == g_tid_cm33) {
    g_tid_cm33 = 0;
  } else if (tid == g_tid_cr8_0) {
    g_tid_cr8_0 = 0;
  } else if (tid == g_tid_cr8_1) {
    g_tid_cr8_1 = 0;
  }
}

static void * polling_thread_func(void * arg)
{
  if (arg == NULL) {
    LPRINTF("Thread received NULL argument\n");
    pthread_exit(NULL);
  }

  struct comm_arg * p = (struct comm_arg *)arg;
  LPRINTF("Polling thread started for platform %p\n", p->platform);
  *thvalp = p->target;
  valid_thread[*thvalp] = true;
  pthread_setspecific(thkey, thvalp);
  // Start the polling loop
  while (!force_stop) {
    platform_poll(p->platform);  // Continuously process messages
    usleep(1000);                // Prevent tight CPU looping
  }

  pthread_exit(NULL);
}

int main(int argc, char * argv[])
{
  static int sighandled = 0;
  eprosima::uxr::Middleware::Kind mw_kind(eprosima::uxr::Middleware::Kind::FASTDDS);

  /**
     * @brief Agent's initialization behaviour description.
     */
  eprosima::uxr::CustomAgent::InitFunction init_function = [&]() -> bool {
    int pattern;
    unsigned long proc_id;
    unsigned long rsc_id;
    unsigned long mbx_id;
    int i;
    int ret = 0;

    /* Initialize HW system components */
    init_system();
    init_cond();

    /* Initialize platform */

    for (i = 0; i < ARRAY_SIZE(ids); i++) {
      proc_id = rsc_id = ids[i].channel;
      mbx_id = ids[i].target;
      ret = platform_init(proc_id, rsc_id, mbx_id, &ids[i].platform);
      if (ret) {
        LPERROR("Failed to initialize platform.");
        ret = 1;
        return false;
      }
    }

    set_tid(ids[communicate_core].target);

    pthread_mutex_lock(&rsc_mutex);
    rpdev = platform_create_rpmsg_vdev(
      ids[communicate_core].platform, 0, VIRTIO_DEV_MASTER, NULL, rpmsg_service_bind);
    pthread_mutex_unlock(&rsc_mutex);
    if (!rpdev) {
      LPERROR("Failed to create rpmsg virtio device.");
    } else {
      svc_name = (const char *)CFG_RPMSG_SVC_NAME0;
      pthread_mutex_lock(&rsc_mutex);
      ret = rpmsg_create_ept(
        &rp_ept, rpdev, svc_name, APP_EPT_ADDR, 0x0, rpmsg_service_cb, rpmsg_service_unbind);
      pthread_mutex_unlock(&rsc_mutex);
    }
    while (!force_stop && !is_rpmsg_ept_ready(&rp_ept))
      platform_poll(ids[communicate_core].platform);
    LPRINTF("Done create endpoint\n");

    pthread_create(&poll_thread, NULL, polling_thread_func, &ids[communicate_core]);
    // pthread_join(poll_thread, NULL);
    return true;
  };

  /**
     * @brief Agent's destruction actions.
     */
  eprosima::uxr::CustomAgent::FiniFunction fini_function = [&]() -> bool {
    int shutdown_msg = SHUTDOWN_MSG;
    uint8_t buffer_t[MESSAGE_LENGTH];
    int i;

    pthread_join(poll_thread, NULL);
    force_stop = 1;

    // LPRINTF("start send shutdown_msg\n");
    rpmsg_send(&rp_ept, &shutdown_msg, sizeof(int));
    sleep(1);
    platform_release_rpmsg_vdev(ids[communicate_core].platform, rpdev);
    valid_thread[*thvalp] = false;
    pthread_key_delete(thkey);
    free(thvalp);
    clear_tid();

    for (i = 0; i < ARRAY_SIZE(ids); i++) {
      platform_cleanup(ids[i].platform);
      ids[i].platform = NULL;
    }
    cleanup_system();

    return true;
  };

  /**
     * @brief Agent's outcoming data flow definition.
     */
  eprosima::uxr::CustomAgent::SendMsgFunction send_msg_function =
    [&](
      const eprosima::uxr::CustomEndPoint * destination_endpoint, uint8_t * buffer,
      size_t message_length, eprosima::uxr::TransportRc & transport_rc) -> ssize_t {
    int ret;
    // LPRINTF("Start send message with lenght %d \n",message_length);
    // LPRINTF("test send message %d \n",message_length);
    ret = rpmsg_send(&rp_ept, buffer, message_length);

    if (ret >= 0) {
      transport_rc = eprosima::uxr::TransportRc::ok;
      // LPRINTF("sent message len: %d \n",message_length);
      return message_length;
    } else {
      transport_rc = eprosima::uxr::TransportRc::server_error;
      return -1;
    }
  };

  eprosima::uxr::CustomAgent::RecvMsgFunction recv_msg_function =
    [&](
      eprosima::uxr::CustomEndPoint * source_endpoint, uint8_t * buffer, size_t buffer_length,
      int timeout, eprosima::uxr::TransportRc & transport_rc) -> ssize_t {
    ssize_t bytes_received = -1;
    struct timespec ts;
    int ret;

    // UXR_AGENT_LOG_INFO(
    //     UXR_DECORATE_GREEN("recv_msg_function start"),
    //     "", "");

    pthread_mutex_lock(&rsc_mutex);

    // Wait for message or timeout
    while (message_queue.empty() && !force_stop) {
      if (timeout >= 0) {
        clock_gettime(CLOCK_REALTIME, &ts);
        ts.tv_sec += timeout / 1000;
        ts.tv_nsec += (timeout % 1000) * 1000000;
        if (ts.tv_nsec >= 1000000000) {
          ts.tv_sec++;
          ts.tv_nsec -= 1000000000;
        }
        ret = pthread_cond_timedwait(&cond[2], &rsc_mutex, &ts);  // cond[2] for cr8
        if (ret == ETIMEDOUT) {
          break;
        }
      } else {
        pthread_cond_wait(&cond[2], &rsc_mutex);  //cond[2] for cr8
      }
    }

    if (!message_queue.empty()) {
      // UXR_AGENT_LOG_INFO(
      //     UXR_DECORATE_GREEN("Message received"),
      //     "", "");
      std::vector<uint8_t> & message = message_queue.front();
      bytes_received = std::min(message.size(), buffer_length);
      memcpy(buffer, message.data(), bytes_received);
      message_queue.pop();

      transport_rc = eprosima::uxr::TransportRc::ok;
    } else if (force_stop) {
      // UXR_AGENT_LOG_INFO(
      //     UXR_DECORATE_GREEN("Force stop received"),
      //     "", "");
      transport_rc = eprosima::uxr::TransportRc::server_error;
      bytes_received = -1;
    } else {
      // UXR_AGENT_LOG_INFO(
      //     UXR_DECORATE_GREEN("timeout_error"),
      //     "", "");
      transport_rc = eprosima::uxr::TransportRc::timeout_error;
      bytes_received = 0;
    }

    pthread_mutex_unlock(&rsc_mutex);
    // UXR_AGENT_LOG_INFO(
    //     UXR_DECORATE_GREEN("recv_msg_function end"),
    //     "", "");
    return bytes_received;
  };

  /**
     * Run the main application.
     */
  try {
    // Define the custom endpoint
    // LPRINTF("start define custom endpoint \n");
    eprosima::uxr::CustomEndPoint custom_endpoint;

    // custom_endpoint.add_member<uint32_t>("addr");

    // Create a custom agent instance
    // LPRINTF("Start add custom_agent \n");
    eprosima::uxr::CustomAgent custom_agent(
      "RPMSG_CUSTOM", &custom_endpoint, mw_kind, false, init_function, fini_function,
      send_msg_function, recv_msg_function);

    // Set verbosity level
    // LPRINTF("Done add custom_agent \n");
    custom_agent.set_verbose_level(4);

    // Run agent and wait until receiving a stop signal
    custom_agent.start();

    uint8_t num = 1;
    rpmsg_send(&rp_ept, &num, sizeof(num));
    sleep(1);
    rpmsg_send(&rp_ept, &num, sizeof(num));

    if (!sighandled) {
      sighandled = 1;
      register_handler(SIGINT, stop_handler);
      register_handler(SIGTERM, stop_handler);
    }
    while (!force_stop) {
      sleep(1);
    }

    // LPRINTF("Done sighandled \n");

    // Stop agent, and exit
    custom_agent.stop();
    return 0;
  } catch (const std::exception & e) {
    // LPRINTF("jump into exception \n");
    // std::cout << e.what() << std::endl;
    std::cout << "errorr here: " << e.what() << std::endl;
    return 1;
  }
}

static void register_handler(int signum, void (*handler)(int))
{
  if (signal(signum, handler) == SIG_ERR) {
    LPRINTF("register sig:%d failed.", signum);
  } else {
    LPRINTF("register sig:%d succeeded.", signum);
  }
}

static void stop_handler(int signum)
{
  int i;
  force_stop = 1;
  (void)signum;

  pthread_mutex_lock(&mutex);
  for (i = 0; i < MBX_CH_NUM; i++) {
    pthread_cond_signal(&cond[i]);
  }
  pthread_mutex_unlock(&mutex);
}
