/**
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
 * implied.  See the License for the specific language governing
 * permissions and limitations under the License.
 */

package it.crs4.pydoop.mapreduce.pipes;

import java.util.Properties;
import java.io.IOException;
import java.io.OutputStream;

import org.apache.avro.Schema;
import org.apache.avro.generic.GenericRecord;
import org.apache.avro.file.CodecFactory;
import org.apache.avro.mapreduce.AvroOutputFormatBase;

import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.io.NullWritable;
import org.apache.hadoop.mapreduce.RecordWriter;
import org.apache.hadoop.mapreduce.TaskAttemptContext;


public class PydoopAvroValueOutputFormat
    extends AvroOutputFormatBase<NullWritable, GenericRecord> {

  // FIXME: do we need a factory?
  private final RecordWriterFactory mRecordWriterFactory;

  public PydoopAvroValueOutputFormat() {
    this(new RecordWriterFactory());
  }

  protected PydoopAvroValueOutputFormat(
      RecordWriterFactory recordWriterFactory) {
    mRecordWriterFactory = recordWriterFactory;
  }

  protected static class RecordWriterFactory<T> {
    protected RecordWriter<NullWritable, GenericRecord> create(
        Schema writerSchema, CodecFactory compressionCodec,
        OutputStream outputStream) throws IOException {
      return new PydoopAvroValueRecordWriter(
          writerSchema, compressionCodec, outputStream);
    }
  }

  @Override
  @SuppressWarnings("unchecked")
  public RecordWriter<NullWritable, GenericRecord> getRecordWriter(
      TaskAttemptContext context) throws IOException {
    // FIXME: do we need to get the schema again (already got it in bridge)?
    Configuration conf = context.getConfiguration();
    Properties props = Submitter.getPydoopProperties();
    Schema writerSchema = Schema.parse(conf.get(
        props.getProperty("AVRO_VALUE_OUTPUT_SCHEMA")));
    // can move the following check to the bridge
    if (null == writerSchema) {
      throw new IOException(
          "PydoopAvroValueOutputFormat requires an output schema");
    }
    return mRecordWriterFactory.create(
        writerSchema, getCompressionCodec(context),
        getAvroFileOutputStream(context));
  }
}
