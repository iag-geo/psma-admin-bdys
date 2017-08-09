
-- create a state boundary table from sa4s (it looks visually better than the PSMA states table due to issues around bays e.g. Botany Bay, NSW) - 5 mins

-- dissolve polygons for each state -- 2 mins -- 6725
DROP TABLE IF EXISTS admin_bdys.temp_states;
CREATE UNLOGGED TABLE admin_bdys.temp_states
(
  gid serial NOT NULL,
  state text NOT NULL,
  geom geometry(Polygon,4283) NOT NULL,
  area float NULL
)
WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.temp_states OWNER TO postgres;

INSERT INTO admin_bdys.temp_states (state, geom)
  SELECT sqt.state,
         (ST_Dump(sqt.geom)).geom
  FROM (
    SELECT state, ST_Union(ST_MakePolygon(geom)) As geom
    FROM (
        SELECT state, ST_ExteriorRing((ST_Dump(geom)).geom) As geom
        FROM admin_bdys.sa4_boundary_table
        ) s
    GROUP BY state
  ) AS sqt;


ALTER TABLE admin_bdys.temp_states ADD CONSTRAINT temp_states_pkey PRIMARY KEY (gid);
CREATE INDEX temp_states_state_idx ON admin_bdys.temp_states USING btree (state);
CREATE INDEX temp_states_geom_idx ON admin_bdys.temp_states USING gist (geom);
ALTER TABLE admin_bdys.temp_states CLUSTER ON temp_states_geom_idx;

ANALYZE admin_bdys.temp_states;


-- create states as lines -- 6728
DROP TABLE IF EXISTS admin_bdys.temp_state_lines;
CREATE TABLE admin_bdys.temp_state_lines(
  gid SERIAL NOT NULL,
  state_gid integer NOT NULL,
  state text NOT NULL,
  geom geometry(Linestring,4283) NOT NULL
) WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.temp_state_lines OWNER TO postgres;

INSERT INTO admin_bdys.temp_state_lines (state, state_gid, geom)
SELECT state,
       gid,
       (ST_Dump(ST_Boundary(geom))).geom
  FROM admin_bdys.temp_states;

CREATE INDEX temp_state_lines_idx ON admin_bdys.temp_state_lines USING btree (state);
CREATE INDEX temp_state_lines_geom_idx ON admin_bdys.temp_state_lines USING gist (geom);
ALTER TABLE admin_bdys.temp_state_lines CLUSTER ON temp_state_lines_geom_idx;

ANALYZE admin_bdys.temp_state_lines;


-- create state borders as buffers -- 2 min

-- create buffered borders -- 4538
DROP TABLE IF EXISTS temp_borders;
SELECT state,
       (ST_Dump(ST_Buffer(ST_Simplify(geom, 0.001), 0.015, 1))).geom AS geom
  INTO TEMPORARY TABLE temp_borders
  FROM admin_bdys.temp_state_lines;

-- merge where they overlap, ignore the coastlines -- 22
DROP TABLE IF EXISTS admin_bdys.temp_borders_2;
SELECT ste1.state || '-' || ste2.state AS state,
       ST_Union(PolygonalIntersection(ste1.geom, ste2.geom)) AS geom
  INTO TEMPORARY TABLE temp_borders_2
  FROM temp_borders AS ste1
  INNER JOIN temp_borders AS ste2
  ON (ST_Intersects(ste1.geom, ste2.geom)
    AND ste1.state <> ste2.state)
  GROUP BY ste1.state,
           ste2.state;

-- trim borders to the coastline -- 82
DROP TABLE IF EXISTS admin_bdys.temp_state_border_buffers;
CREATE TABLE admin_bdys.temp_state_border_buffers(
  gid serial NOT NULL,
  state text NOT NULL,
  geom geometry(Polygon,4283) NOT NULL
) WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.temp_state_border_buffers OWNER TO postgres;

INSERT INTO admin_bdys.temp_state_border_buffers (state, geom)
SELECT ste2.state,
       (ST_Dump(PolygonalIntersection(ste1.geom, ste2.geom))).geom
  FROM temp_borders_2 AS ste1
  INNER JOIN admin_bdys.temp_states AS ste2
  ON ST_Intersects(ste1.geom, ste2.geom);

CREATE INDEX temp_state_border_buffers_idx ON admin_bdys.temp_state_border_buffers USING btree (state);
CREATE INDEX temp_state_border_buffers_geom_idx ON admin_bdys.temp_state_border_buffers USING gist (geom);
ALTER TABLE admin_bdys.temp_state_border_buffers CLUSTER ON temp_state_border_buffers_geom_idx;

ANALYZE admin_bdys.temp_state_border_buffers;

DROP TABLE IF EXISTS temp_borders_2;
DROP TABLE IF EXISTS temp_borders;


-- create subdivided buffered borders for performance
DROP TABLE IF EXISTS admin_bdys.temp_state_border_buffers_subdivided;
CREATE TABLE admin_bdys.temp_state_border_buffers_subdivided(
  new_gid serial NOT NULL,
  gid integer NOT NULL,
  state text NOT NULL,
  geom geometry(Polygon,4283) NOT NULL
) WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.temp_state_border_buffers_subdivided OWNER TO postgres;

INSERT INTO admin_bdys.temp_state_border_buffers_subdivided (gid, state, geom)
SELECT gid,
       state,
       ST_Subdivide(geom, 512)
  FROM admin_bdys.temp_state_border_buffers;

CREATE INDEX temp_state_border_buffers_subdivided_idx ON admin_bdys.temp_state_border_buffers_subdivided USING btree (state);
CREATE INDEX temp_state_border_buffers_subdivided_geom_idx ON admin_bdys.temp_state_border_buffers_subdivided USING gist (geom);
ALTER TABLE admin_bdys.temp_state_border_buffers_subdivided CLUSTER ON temp_state_border_buffers_subdivided_geom_idx;

ANALYZE admin_bdys.temp_state_border_buffers_subdivided;
