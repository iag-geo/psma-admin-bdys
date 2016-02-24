
DROP TABLE IF EXISTS admin_bdys.temp_states;
CREATE TABLE admin_bdys.temp_states(
  gid SERIAL NOT NULL,
  state character varying(3) NOT NULL,
  geom geometry(Polygon,4283) NOT NULL
) WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.temp_states OWNER TO postgres;

INSERT INTO admin_bdys.temp_states (state, geom)
SELECT state,
       (ST_Dump(geom)).geom
  FROM admin_bdys.state_bdys;


-- create states as lines
DROP TABLE IF EXISTS admin_bdys.temp_state_lines;
CREATE TABLE admin_bdys.temp_state_lines(
  gid SERIAL NOT NULL,
  state_gid integer NOT NULL,
  state character varying(3) NOT NULL,
  geom geometry(Linestring,4283) NOT NULL
) WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.temp_state_lines OWNER TO postgres;

INSERT INTO admin_bdys.temp_state_lines (state, state_gid, geom)
SELECT state,
       gid,
       (ST_Dump(ST_Boundary(geom))).geom
       --ST_Subdivide((ST_Dump(ST_Boundary(geom))).geom, 512)
  FROM admin_bdys.temp_states
  WHERE state <> 'TAS';

CREATE INDEX temp_state_lines_geom_idx ON admin_bdys.temp_state_lines USING gist (geom);
ALTER TABLE admin_bdys.temp_state_lines CLUSTER ON temp_state_lines_geom_idx;

ANALYZE admin_bdys.temp_state_lines;

-- create state borders as buffers -- 2 min

-- create buffered borders
DROP TABLE IF EXISTS admin_bdys.temp_borders;
SELECT state,
       (ST_Dump(ST_Buffer(ST_Simplify(geom, 0.001), 0.02, 1))).geom AS geom
  INTO admin_bdys.temp_borders
  FROM admin_bdys.temp_state_lines;
  --WHERE state IN ('NSW', 'SA', 'NT'); 

-- merge where they overlap, ignore the coastlines
DROP TABLE IF EXISTS admin_bdys.temp_borders_2;
SELECT ste1.state || '-' || ste2.state AS state,
       ST_Union(ST_Intersection(ste1.geom, ste2.geom)) AS geom
  INTO admin_bdys.temp_borders_2
  FROM admin_bdys.temp_borders AS ste1
  INNER JOIN admin_bdys.temp_borders AS ste2
  ON (ST_Intersects(ste1.geom, ste2.geom)
    AND ste1.state <> ste2.state)
  GROUP BY ste1.state,
           ste2.state;

-- trim borders to the coastline
DROP TABLE IF EXISTS admin_bdys.temp_state_border_buffers;
CREATE TABLE admin_bdys.temp_state_border_buffers(
  gid serial NOT NULL,
  state character varying(7) NOT NULL,
  geom geometry(Polygon,4283) NOT NULL
) WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.temp_state_border_buffers OWNER TO postgres;

INSERT INTO admin_bdys.temp_state_border_buffers (state, geom)
SELECT ste2.state,
       (ST_Dump(ST_Intersection(ste1.geom, ste2.geom))).geom
  FROM admin_bdys.temp_borders_2 AS ste1
  INNER JOIN admin_bdys.temp_states AS ste2
  ON ST_Intersects(ste1.geom, ste2.geom);

CREATE INDEX temp_state_border_buffers_geom_idx ON admin_bdys.temp_state_border_buffers USING gist (geom);
ALTER TABLE admin_bdys.temp_state_border_buffers CLUSTER ON temp_state_border_buffers_geom_idx;

ANALYZE admin_bdys.temp_state_border_buffers;

DROP TABLE IF EXISTS admin_bdys.temp_borders_2;
DROP TABLE IF EXISTS admin_bdys.temp_borders;
