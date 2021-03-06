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


import codecs


cdef uint64_t RECORD_ENCODER_CHECKED = 1 << 0
cdef uint64_t RECORD_ENCODER_INVALID = 1 << 1

cdef bytes NULL_CODEC_ID = b'\x00' * 16
cdef bytes EMPTY_TUPLE_CODEC_ID = TYPE_IDS.get('empty-tuple').bytes


cdef class BaseCodec:

    def __init__(self):
        raise RuntimeError(
            'codecs are not supposed to be instantiated directly')

    def __cinit__(self):
        self.tid = None
        self.name = None

    cdef encode(self, WriteBuffer buf, object obj):
        raise NotImplementedError

    cdef decode(self, FRBuffer *buf):
        raise NotImplementedError

    cdef dump(self, int level = 0):
        return f'{level * " "}{self.name}'


cdef class EmptyTupleCodec(BaseCodec):

    def __cinit__(self):
        self.tid = EMPTY_TUPLE_CODEC_ID
        self.name = 'no-input'
        self.empty_tup = None

    cdef encode(self, WriteBuffer buf, object obj):
        if type(obj) is not tuple:
            raise RuntimeError(
                f'cannot encode empty Tuple: expected a tuple, '
                f'got {type(obj).__name__}')
        if len(obj) != 0:
            raise RuntimeError(
                f'cannot encode empty Tuple: expected 0 elements, '
                f'got {len(obj)}')
        buf.write_bytes(b'\x00\x00\x00\x04\x00\x00\x00\x00')

    cdef decode(self, FRBuffer *buf):
        elem_count = <Py_ssize_t><uint32_t>hton.unpack_int32(frb_read(buf, 4))
        if elem_count != 0:
            raise RuntimeError(
                f'cannot decode empty Tuple: expected 0 elements, '
                f'got {elem_count}')

        if self.empty_tup is None:
            self.empty_tup = datatypes.tuple_new(0)
        return self.empty_tup


cdef class NullCodec(BaseCodec):

    def __cinit__(self):
        self.tid = NULL_CODEC_ID
        self.name = 'null-codec'


cdef class BaseRecordCodec(BaseCodec):

    def __cinit__(self):
        self.fields_codecs = ()
        self.encoder_flags = 0

    cdef _check_encoder(self):
        if not (self.encoder_flags & RECORD_ENCODER_CHECKED):
            for codec in self.fields_codecs:
                if not isinstance(codec, (ScalarCodec, ArrayCodec)):
                    self.encoder_flags |= RECORD_ENCODER_INVALID
                    break
            self.encoder_flags |= RECORD_ENCODER_CHECKED

        if self.encoder_flags & RECORD_ENCODER_INVALID:
            raise TypeError(
                'argument tuples only support scalars and arrays of scalars')

    cdef encode(self, WriteBuffer buf, object obj):
        cdef:
            WriteBuffer elem_data
            Py_ssize_t objlen
            Py_ssize_t i
            BaseCodec sub_codec

        self._check_encoder()

        if not _is_array_iterable(obj):
            raise TypeError(
                'a sized iterable container expected (got type {!r})'.format(
                    type(obj).__name__))

        objlen = len(obj)
        if objlen == 0:
            buf.write_bytes(b'\x00\x00\x00\x04\x00\x00\x00\x00')
            return

        if objlen > _MAXINT32:
            raise ValueError('too many elements for a tuple')

        if objlen != len(self.fields_codecs):
            raise ValueError(
                f'expected {len(self.fields_codecs)} elements in the tuple, '
                f'got {objlen}')

        elem_data = WriteBuffer.new()
        for i in range(objlen):
            item = obj[i]
            if item is None:
                elem_data.write_int32(-1)
            else:
                sub_codec = <BaseCodec>(self.fields_codecs[i])
                try:
                    sub_codec.encode(elem_data, item)
                except TypeError as e:
                    raise ValueError(
                        'invalid tuple element: {}'.format(
                            e.args[0])) from None

        buf.write_int32(4 + elem_data.len())  # buffer length
        buf.write_int32(<int32_t><uint32_t>objlen)
        buf.write_buffer(elem_data)


cdef class BaseNamedRecordCodec(BaseRecordCodec):

    def __cinit__(self):
        self.descriptor = None

    cdef dump(self, int level = 0):
        buf = [f'{level * " "}{self.name}']
        for pos, codec in enumerate(self.fields_codecs):
            name = datatypes.record_desc_pointer_name(self.descriptor, pos)
            buf.append('{}{} := {}'.format(
                (level + 1) * " ",
                name,
                (<BaseCodec>codec).dump(level + 1).strip()))
        return '\n'.join(buf)


@cython.final
cdef class EdegDBCodecContext(pgproto.CodecContext):

    def __cinit__(self):
        self._codec = codecs.lookup('utf-8')

    cpdef get_text_codec(self):
        return self._codec

    cdef is_encoding_utf8(self):
        return True


cdef EdegDBCodecContext DEFAULT_CODEC_CONTEXT = EdegDBCodecContext()
