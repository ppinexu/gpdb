-- Test AO XLogging
CREATE TABLE generate_ao_xlog_table(a INT, b INT) WITH (APPENDONLY=TRUE);

-- Store the location of xlog in a temporary table so that we can
-- use it to request walsender to start streaming from this point
CREATE TEMP TABLE tmp(dummy int, dbid int, startpoint TEXT) distributed by (dummy);
INSERT INTO tmp SELECT 1, gp_execution_segment(), pg_current_xlog_location()
FROM gp_dist_random('gp_id');

-- Generate some xlog records for AO
INSERT INTO generate_ao_xlog_table VALUES(1, 10), (2, 10), (8, 10), (3, 10);

-- Verify that the insert AO xlog record was received
SELECT gp_segment_id, relname, record_type, segment_filenum, recordlen, file_offset
  FROM test_xlog_ao_wrapper(
    (SELECT array_agg(startpoint) FROM 
       (SELECT startpoint from tmp order by dbid) t
    )
  ) 
WHERE spcNode = (SELECT oid FROM pg_tablespace WHERE spcname = 'pg_default')
AND dbNode = (SELECT oid FROM pg_database WHERE datname = current_database())
ORDER BY gp_segment_id, xrecoff;

-- Store the latest xlog offset
DELETE FROM tmp;
INSERT INTO tmp SELECT 1, gp_execution_segment(), pg_current_xlog_location()
FROM gp_dist_random('gp_id');

-- Generate a truncate XLOG entry for generate_ao_xlog_table.
BEGIN;
INSERT INTO generate_ao_xlog_table SELECT i,i FROM generate_series(1,10)i;
ABORT;
VACUUM generate_ao_xlog_table;

-- Verify that truncate AO xlog record was received
SELECT gp_segment_id, relname, record_type, segment_filenum, recordlen, file_offset
  FROM test_xlog_ao_wrapper(
    (SELECT array_agg(startpoint) FROM 
       (SELECT startpoint from tmp order by dbid) t
    )
  ) 
WHERE spcNode = (SELECT oid FROM pg_tablespace WHERE spcname = 'pg_default')
AND dbNode = (SELECT oid FROM pg_database WHERE datname = current_database())
ORDER BY gp_segment_id, xrecoff;
