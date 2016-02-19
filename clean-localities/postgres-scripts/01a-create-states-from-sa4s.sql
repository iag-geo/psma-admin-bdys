
-- create thinned, clean sa4s to represent a states table - 5 mins

DROP TABLE IF EXISTS admin_bdys.temp_sa4s;
CREATE UNLOGGED TABLE admin_bdys.temp_sa4s
(
  gid serial NOT NULL,
  state character varying(3) NOT NULL,
  geom geometry(MultiPolygon,4283) NOT NULL,
  area float NULL
)
WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.temp_sa4s OWNER TO postgres;

INSERT INTO admin_bdys.temp_sa4s (state, geom) -- 6811 -- 1 mins
SELECT ste.st_abbrev,
       bdy.geom
  FROM raw_admin_bdys.aus_sa4_2011_polygon AS bdy
  INNER JOIN raw_admin_bdys.aus_sa4_2011 AS sa4 ON bdy.sa4_11pid = sa4.sa4_11pid
  INNER JOIN raw_admin_bdys.aus_state AS ste ON sa4.state_pid = ste.state_pid;


-- dissolve polygons for each state -- 6735 -- 2 mins
DROP TABLE IF EXISTS admin_bdys.temp_sa4s_2;
CREATE UNLOGGED TABLE admin_bdys.temp_sa4s_2
(
  gid serial NOT NULL,
  state character varying(3) NOT NULL,
  geom geometry(MultiPolygon,4283) NOT NULL,
  area float NULL
)
WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.temp_sa4s_2 OWNER TO postgres;

INSERT INTO admin_bdys.temp_sa4s_2 (state, geom)
  SELECT sqt.state,
         --ST_Multi(St_SnapToGrid(ST_SimplifyPreserveTopology(geom, 0.0000001), 0.0000001))
         ST_Multi(St_SnapToGrid(geom, 0.0000001))
  FROM (
    SELECT state, ST_Union(ST_MakePolygon(geom)) As geom
    FROM (
        SELECT state, ST_ExteriorRing((ST_Dump(geom)).geom) As geom
        FROM admin_bdys.temp_sa4s
        ) s
    GROUP BY state
  ) AS sqt;


-- get rid of doughnut holes -- 
DROP TABLE IF EXISTS admin_bdys.temp_sa4_states;
CREATE TABLE admin_bdys.temp_sa4_states
(
  gid serial NOT NULL,
  state character varying(3) NOT NULL,
  geom geometry(Polygon,4283) NOT NULL,
  area float NULL
)
WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.temp_sa4_states OWNER TO postgres;

INSERT INTO admin_bdys.temp_sa4_states (state, geom) -- 6735 -- 2 mins
  SELECT sqt.state,
         (st_dump(sqt.geom)).geom
  FROM (
    SELECT state, ST_Union(ST_MakePolygon(geom)) As geom
    FROM (
        SELECT state, ST_ExteriorRing((ST_Dump(geom)).geom) As geom
        FROM admin_bdys.temp_sa4s_2
        ) s
    GROUP BY state
  ) AS sqt;

-- reinstate the hole in NSW where the ACT is
UPDATE admin_bdys.temp_sa4_states
  SET geom = st_difference(geom, (SELECT s1.geom FROM admin_bdys.temp_sa4_states AS s1
                                    INNER JOIN admin_bdys.temp_sa4_states AS s2 ON ST_Within(s1.geom, s2.geom)
                                    WHERE s1.state = 'ACT'
                                    AND s2.state = 'NSW'))
  WHERE state = 'NSW';


ALTER TABLE admin_bdys.temp_sa4_states ADD CONSTRAINT temp_sa4_states_pkey PRIMARY KEY(gid);
CREATE INDEX temp_sa4_states_geom_idx ON admin_bdys.temp_sa4_states USING gist (geom); ALTER TABLE admin_bdys.temp_sa4_states CLUSTER ON temp_sa4_states_geom_idx;

ANALYZE admin_bdys.temp_sa4_states;

DROP TABLE IF EXISTS admin_bdys.temp_sa4s_2;
DROP TABLE IF EXISTS admin_bdys.temp_sa4s;


-- create states as lines
DROP TABLE IF EXISTS admin_bdys.temp_sa4_state_lines;
CREATE TABLE admin_bdys.temp_sa4_state_lines(
  gid integer NOT NULL,
  state character varying(3) NOT NULL,
  geom geometry(Linestring,4283) NOT NULL
) WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.temp_sa4_state_lines OWNER TO postgres;

CREATE INDEX temp_sa4_state_lines_geom_idx ON admin_bdys.temp_sa4_state_lines USING gist (geom);
ALTER TABLE admin_bdys.temp_sa4_state_lines CLUSTER ON temp_sa4_state_lines_geom_idx;

INSERT INTO admin_bdys.temp_sa4_state_lines
SELECT gid,
       state,
       ST_SnapToGrid((ST_Dump(ST_Boundary(geom))).geom, 0.00001)
  FROM admin_bdys.temp_sa4_states;

ANALYZE admin_bdys.temp_sa4_state_lines;


-- create state borders as buffers -- 2 min

-- create buffered borders
DROP TABLE IF EXISTS admin_bdys.temp_borders;
SELECT ste1.state,
       (ST_Dump(ST_SnapToGrid(ST_Buffer(ST_SimplifyPreserveTopology(ste1.geom, 0.001), 0.01, 1), 0.0000001))).geom AS geom
  INTO admin_bdys.temp_borders
  FROM admin_bdys.temp_sa4_state_lines AS ste1
  WHERE state <> 'TAS';

-- merge where they overlap, ignore the coastlines
DROP TABLE IF EXISTS admin_bdys.temp_borders_2;
SELECT ste1.state || '-' || ste2.state AS state,
       (ST_Dump(ST_Intersection(ste1.geom, ste2.geom))).geom AS geom
  INTO admin_bdys.temp_borders_2
  FROM admin_bdys.temp_borders AS ste1
  INNER JOIN admin_bdys.temp_borders AS ste2
  ON (ST_Intersects(ste1.geom, ste2.geom)
    AND ste1.state <> ste2.state);

-- trim borders to the coastline
DROP TABLE IF EXISTS admin_bdys.temp_sa4_state_borders;
CREATE TABLE admin_bdys.temp_sa4_state_borders(
  gid serial NOT NULL,
  state character varying(7) NOT NULL,
  geom geometry(Polygon,4283) NOT NULL
) WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.temp_sa4_state_borders OWNER TO postgres;

CREATE INDEX temp_sa4_state_borders_geom_idx ON admin_bdys.temp_sa4_state_borders USING gist (geom);
ALTER TABLE admin_bdys.temp_sa4_state_borders CLUSTER ON temp_sa4_state_borders_geom_idx;

INSERT INTO admin_bdys.temp_sa4_state_borders (state, geom)
SELECT ste2.state,
       (ST_Dump(ST_Intersection(ste1.geom, ste2.geom))).geom
  FROM admin_bdys.temp_borders_2 AS ste1
  INNER JOIN admin_bdys.temp_sa4_states AS ste2
  ON ST_Intersects(ste1.geom, ste2.geom);

ANALYZE admin_bdys.temp_sa4_state_borders;

DROP TABLE IF EXISTS admin_bdys.temp_borders_2;
DROP TABLE IF EXISTS admin_bdys.temp_borders;
