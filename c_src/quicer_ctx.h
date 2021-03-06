/*--------------------------------------------------------------------
Copyright (c) 2021 EMQ Technologies Co., Ltd. All Rights Reserved.

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
-------------------------------------------------------------------*/

#ifndef __QUICER_CTX_H_
#define __QUICER_CTX_H_

#include "quicer_nif.h"
#include "quicer_queue.h"

#define _CTX_CALLBACK_WRITE_
#define _CTX_CALLBACK_READ_
#define _CTX_NIF_WRITE_
#define _CTX_NIF_READ_

typedef struct
{
  HQUIC Configuration;
  HQUIC Listener;
  HQUIC Connection;
  QUICER_ACCEPTOR_QUEUE *acceptor_queue;
  ErlNifPid listenerPid;
  ErlNifEnv *env;
  ErlNifMutex *lock;
  void *reserved1;
  void *reserved2;
  void *reserved3;
} QuicerListenerCTX;

typedef struct
{
  HQUIC Configuration;
  HQUIC Connection;
  QuicerListenerCTX *l_ctx;
  QUICER_ACCEPTOR_QUEUE *acceptor_queue;
  ACCEPTOR *owner;
  ErlNifMonitor *owner_mon;
  ErlNifEnv *env;
  ErlNifMutex *lock;
  BOOLEAN is_closed;
  void *reserved1;
  void *reserved2;
  void *reserved3;
} QuicerConnCTX;

typedef struct
{
  QuicerListenerCTX *l_ctx;
  QuicerConnCTX *c_ctx;
  HQUIC Stream;
  ACCEPTOR *owner;
  ErlNifMonitor *owner_mon;
  ErlNifEnv *env; //@todo destruct env
  ErlNifMutex *lock;
  BOOLEAN is_closed;
  _CTX_CALLBACK_WRITE_ _CTX_NIF_READ_ uint8_t *Buffer;
  _CTX_CALLBACK_WRITE_ _CTX_NIF_READ_ uint64_t BufferLen;
  _CTX_CALLBACK_READ_ BOOLEAN is_wait_for_data;
  _CTX_CALLBACK_WRITE_ BOOLEAN is_buff_ready;
  void *reserved1;
  void *reserved2;
  void *reserved3;
} QuicerStreamCTX;

QuicerListenerCTX *init_l_ctx();
void destroy_l_ctx(QuicerListenerCTX *l_ctx);

QuicerConnCTX *init_c_ctx();
void destroy_c_ctx(QuicerConnCTX *c_ctx);

QuicerStreamCTX *init_s_ctx();
void destroy_s_ctx(QuicerStreamCTX *s_ctx);

#endif // __QUICER_CTX_H_
