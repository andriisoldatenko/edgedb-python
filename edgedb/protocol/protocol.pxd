#
# This source file is part of the EdgeDB open source project.
#
# Copyright 2016-present MagicStack Inc. and the EdgeDB authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#


cimport cython
cimport cpython

from libc.stdint cimport int16_t, int32_t, uint16_t, \
                         uint32_t, int64_t, uint64_t

from edgedb.pgproto.pgproto cimport (
    WriteBuffer,
    ReadBuffer,
    FRBuffer,
)

from edgedb.pgproto cimport pgproto
from edgedb.pgproto.debug cimport PG_DEBUG


include "./lru.pxd"
include "./codecs/codecs.pxd"


ctypedef object (*decode_row_method)(BaseCodec, FRBuffer *buf)


cdef enum TransactionStatus:
    TRANS_IDLE = 0                 # connection idle
    TRANS_ACTIVE = 1               # command in progress
    TRANS_INTRANS = 2              # idle, within transaction block
    TRANS_INERROR = 3              # idle, within failed transaction
    TRANS_UNKNOWN = 4              # cannot determine status


cdef enum EdgeParseFlags:
    PARSE_HAS_RESULT = 1 << 0
    PARSE_SINGLETON_RESULT = 1 << 1


cdef enum AuthenticationStatuses:
    AUTH_OK = 0
    AUTH_SASL = 10
    AUTH_SASL_CONTINUE = 11
    AUTH_SASL_FINAL = 12


cdef class QueryCodecsCache:

    cdef:
        LRUMapping queries

    cdef get(self, str query, bint json_mode)
    cdef set(self, str query, bint json_mode,
             bint has_na_cardinality, BaseCodec in_type, BaseCodec out_type)


cdef class SansIOProtocol:

    cdef:
        ReadBuffer buffer

        readonly bint connected

        object con
        readonly object con_params

        object backend_secret

        TransactionStatus xact_status

        dict server_settings

        readonly bytes last_status
        readonly bytes last_details

    cdef encode_args(self, BaseCodec in_dc, WriteBuffer buf, args, kwargs)

    cdef parse_data_messages(self, BaseCodec out_dc, result)
    cdef parse_sync_message(self)
    cdef parse_command_complete_message(self)
    cdef parse_describe_type_message(self, CodecsRegistry reg)
    cdef amend_parse_error(self, exc, bint json_mode, bint expect_one)

    cdef inline reject_headers(self)
    cdef dict parse_headers(self)

    cdef parse_error_message(self)

    cdef write(self, WriteBuffer buf)
    cpdef abort(self)

    cdef reset_status(self)

    cdef fallthrough(self)
