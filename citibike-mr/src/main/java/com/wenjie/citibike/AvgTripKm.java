package com.wenjie.citibike;

import java.io.IOException;
import java.io.DataInput;
import java.io.DataOutput;
import java.util.ArrayList;
import java.util.List;

import org.apache.hadoop.conf.Configuration;
import org.apache.hadoop.fs.Path;
import org.apache.hadoop.io.*;
import org.apache.hadoop.mapreduce.*;
import org.apache.hadoop.mapreduce.lib.input.FileInputFormat;
import org.apache.hadoop.mapreduce.lib.output.FileOutputFormat;

/** Average distance (km) per route: route = start_station_name + end_station_name */
public class AvgTripKm {

    /** (sum, count) pair */
    public static class SumCountWritable implements Writable {
        private double sum;
        private long count;

        public SumCountWritable() {}

        public SumCountWritable(double sum, long count) {
            this.sum = sum;
            this.count = count;
        }

        public double getSum()   { return sum; }
        public long   getCount() { return count; }

        @Override
        public void write(DataOutput out) throws IOException {
            out.writeDouble(sum);
            out.writeLong(count);
        }

        @Override
        public void readFields(DataInput in) throws IOException {
            sum   = in.readDouble();
            count = in.readLong();
        }

        public void addInPlace(SumCountWritable other){
            this.sum   += other.sum;
            this.count += other.count;
        }
    }

    public static class RouteKmMapper extends Mapper<LongWritable, Text, Text, SumCountWritable> {
        private final Text outKey = new Text();

        private static final int IDX_START_NAME = 4;
        private static final int IDX_END_NAME   = 6;
        private static final int IDX_START_LAT  = 8;
        private static final int IDX_START_LNG  = 9;
        private static final int IDX_END_LAT    = 10;
        private static final int IDX_END_LNG    = 11;

        enum C {
            ROWS,
            HEADER_SKIPPED,
            COLS_LT_12,
            MISSING_ROUTE,
            HAVERSINE_MISSING_COORDS,
            EMITTED
        }

        @Override
        protected void map(LongWritable key, Text value, Context ctx)
                throws IOException, InterruptedException {
            ctx.getCounter(C.ROWS).increment(1);
            String line = value.toString();
            if (line.isEmpty()) return;

            // Skip header (first record of first split)
            if (key.get() == 0 &&
                line.regionMatches(true, 0, "ride_id,", 0, "ride_id,".length())) {
                ctx.getCounter(C.HEADER_SKIPPED).increment(1);
                return;
            }

            List<String> cols = parseCsv(line);
            if (cols.size() <= IDX_END_LNG) {
                ctx.getCounter(C.COLS_LT_12).increment(1);
                return;
            }

            String startName = safeTrim(cols.get(IDX_START_NAME));
            String endName   = safeTrim(cols.get(IDX_END_NAME));
            if (startName.isEmpty() || endName.isEmpty()) {
                ctx.getCounter(C.MISSING_ROUTE).increment(1);
                return;
            }
            String route = startName + " \u2192 " + endName; // "→"
            outKey.set(route);

            Double slat = parseNullableDouble(cols.get(IDX_START_LAT));
            Double slng = parseNullableDouble(cols.get(IDX_START_LNG));
            Double elat = parseNullableDouble(cols.get(IDX_END_LAT));
            Double elng = parseNullableDouble(cols.get(IDX_END_LNG));
            if (slat == null || slng == null || elat == null || elng == null) {
                ctx.getCounter(C.HAVERSINE_MISSING_COORDS).increment(1);
                return;
            }

            double km = haversineKm(slat, slng, elat, elng);
            if (Double.isFinite(km) && km >= 0.0) {
                ctx.write(outKey, new SumCountWritable(km, 1L));
                ctx.getCounter(C.EMITTED).increment(1);
            }
        }

        private static String safeTrim(String s) {
            return s == null ? "" : s.trim();
        }

        private static Double parseNullableDouble(String s){
            if (s == null) return null;
            s = s.trim();
            if (s.isEmpty()) return null;
            try {
                return Double.valueOf(s);
            } catch (Exception e){
                return null;
            }
        }

        private static double haversineKm(double slat, double slng,
                                          double elat, double elng) {
            final double R = 6371.0088; // Earth radius (km)
            double dLat = Math.toRadians(elat - slat);
            double dLng = Math.toRadians(elng - slng);
            double a = Math.sin(dLat/2) * Math.sin(dLat/2)
                    + Math.cos(Math.toRadians(slat))
                    * Math.cos(Math.toRadians(elat))
                    * Math.sin(dLng/2) * Math.sin(dLng/2);
            double c = 2 * Math.asin(Math.sqrt(a));
            return R * c;
        }

        private static List<String> parseCsv(String line){
            List<String> out = new ArrayList<>();
            StringBuilder sb = new StringBuilder();
            boolean inQuotes = false;
            for (int i = 0; i < line.length(); i++){
                char ch = line.charAt(i);
                if (ch == '"'){
                    if (inQuotes && i + 1 < line.length() && line.charAt(i + 1) == '"'){
                        sb.append('"');
                        i++;
                    } else {
                        inQuotes = !inQuotes;
                    }
                } else if (ch == ',' && !inQuotes){
                    out.add(sb.toString());
                    sb.setLength(0);
                } else {
                    sb.append(ch);
                }
            }
            out.add(sb.toString());
            return out;
        }
    }

    /** Combiner: partial sum/count */
    public static class SumCombiner
            extends Reducer<Text, SumCountWritable, Text, SumCountWritable> {

        @Override
        protected void reduce(Text key,
                              Iterable<SumCountWritable> values,
                              Context ctx)
                throws IOException, InterruptedException {
            double sum = 0.0;
            long count = 0L;
            for (SumCountWritable v : values) {
                sum   += v.getSum();
                count += v.getCount();
            }
            ctx.write(key, new SumCountWritable(sum, count));
        }
    }

    /** Reducer: output avg km per route */
    public static class AvgReducer
            extends Reducer<Text, SumCountWritable, Text, DoubleWritable> {

        @Override
        protected void reduce(Text route,
                              Iterable<SumCountWritable> values,
                              Context ctx)
                throws IOException, InterruptedException {
            double sum = 0.0;
            long count = 0L;
            for (SumCountWritable v : values) {
                sum   += v.getSum();
                count += v.getCount();
            }
            if (count <= 0) return;

            double avg = sum / count;
            ctx.write(route, new DoubleWritable(avg));
        }
    }

    /** Driver */
    public static void main(String[] args) throws Exception {
        if (args.length != 2) {
            System.err.println("Usage: AvgTripKm <input> <output>");
            System.exit(2);
        }

        Configuration conf = new Configuration();
        Job job = Job.getInstance(conf, "CitiBike Avg KM Per Route");
        job.setJarByClass(AvgTripKm.class);

        job.setMapperClass(RouteKmMapper.class);
        job.setCombinerClass(SumCombiner.class);
        job.setReducerClass(AvgReducer.class);

        // Allow multiple reducers if you like; each reducer will output
        // (route, avg_km) for its partition.
        // job.setNumReduceTasks(1);  // optional

        job.setMapOutputKeyClass(Text.class);
        job.setMapOutputValueClass(SumCountWritable.class);
        job.setOutputKeyClass(Text.class);
        job.setOutputValueClass(DoubleWritable.class);

        FileInputFormat.addInputPath(job, new Path(args[0]));
        FileOutputFormat.setOutputPath(job, new Path(args[1]));

        System.exit(job.waitForCompletion(true) ? 0 : 1);
    }
}


