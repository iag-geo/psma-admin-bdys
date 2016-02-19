
-- create thinned locality boundaries - 3 mins
DROP TABLE IF EXISTS admin_bdys.temp_localities;
CREATE UNLOGGED TABLE admin_bdys.temp_localities
(
  gid serial NOT NULL,
  locality_pid varchar(16),
  state character varying(3) NOT NULL,
  geom geometry(Polygon,4283) NOT NULL,
  area float NULL
)
WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.temp_localities OWNER TO postgres;

INSERT INTO admin_bdys.temp_localities (locality_pid, state, geom)
  SELECT locality_pid,
         state,
         (ST_Dump(ST_Multi(St_SnapToGrid(geom, 0.0000001)))).geom
  FROM admin_bdys.locality_boundaries;

ALTER TABLE admin_bdys.temp_localities ADD CONSTRAINT temp_localities_pkey PRIMARY KEY(gid);
CREATE INDEX temp_localities_geom_idx ON admin_bdys.temp_localities USING gist (geom);
ALTER TABLE admin_bdys.temp_localities CLUSTER ON temp_localities_geom_idx;

ANALYZE admin_bdys.temp_localities;


-- create display localities working table
DROP TABLE IF EXISTS admin_bdys.temp_split_localities;
CREATE TABLE admin_bdys.temp_split_localities (
  gid integer NOT NULL,
  locality_pid varchar(16) NOT NULL,
  loc_state varchar(3) NOT NULL,
  state_gid integer NULL,
  ste_state varchar(3) NOT NULL,
  match_type varchar(50),
  geom geometry(Polygon,4283) NOT NULL, area float NULL
)WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.temp_split_localities OWNER TO postgres;
CREATE INDEX temp_split_localities_geom_idx ON admin_bdys.temp_split_localities USING gist (geom);
ALTER TABLE admin_bdys.temp_split_localities CLUSTER ON temp_split_localities_geom_idx;


-- create state border locality gaps table
DROP TABLE IF EXISTS admin_bdys.temp_holes;
CREATE TABLE admin_bdys.temp_holes(
  gid serial NOT NULL,
  locality_pid varchar(16) NULL,
  state character varying(3) NOT NULL,
  geom geometry(Polygon,4283) NOT NULL
) WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.temp_holes OWNER TO postgres;

CREATE INDEX temp_holes_geom_idx ON admin_bdys.temp_holes USING gist (geom);
ALTER TABLE admin_bdys.temp_holes CLUSTER ON temp_holes_geom_idx;



-- 
-- 
-- DROP TABLE IF EXISTS admin_bdys.temp_good_localities;
-- CREATE TABLE admin_bdys.temp_good_localities (
--   gid integer NOT NULL,
--   locality_pid varchar(16) NOT NULL,
--   state varchar(3) NOT NULL,
--   state_gid integer NULL,
--   match_type varchar(50),
--   geom geometry(Polygon,4283) NOT NULL, area float NULL
-- )WITH (OIDS=FALSE);
-- ALTER TABLE admin_bdys.temp_good_localities OWNER TO postgres;
-- CREATE INDEX temp_good_localities_geom_idx ON admin_bdys.temp_good_localities USING gist (geom);
-- ALTER TABLE admin_bdys.temp_good_localities CLUSTER ON temp_good_localities_geom_idx;
-- 
-- -- create remaining localities table
-- DROP TABLE IF EXISTS admin_bdys.temp_localities_2;
-- CREATE UNLOGGED TABLE admin_bdys.temp_localities_2
-- (
--   gid serial NOT NULL,
--   loc_gid integer NOT NULL,
--   locality_pid varchar(16),
--   state varchar(3) NOT NULL,
--   geom geometry(Polygon,4283) NOT NULL,
--   area float NULL
-- )
-- WITH (OIDS=FALSE);
-- ALTER TABLE admin_bdys.temp_localities_2 OWNER TO postgres;
-- ALTER TABLE admin_bdys.temp_localities_2 ADD CONSTRAINT temp_localities_2_pkey PRIMARY KEY(gid);
-- CREATE INDEX temp_localities_2_geom_idx ON admin_bdys.temp_localities_2 USING gist (geom);
-- ALTER TABLE admin_bdys.temp_localities_2 CLUSTER ON temp_localities_2_geom_idx;
-- 
-- 
-- -- create messy localities table
-- DROP TABLE IF EXISTS admin_bdys.temp_messy_localities;
-- CREATE TABLE admin_bdys.temp_messy_localities (
--   gid serial NOT NULL,
--   loc_gid integer NOT NULL,
--   locality_pid varchar(16) NOT NULL,
--   loc_state varchar(3) NOT NULL,
--   state_gid integer NOT NULL,
--   ste_state varchar(3) NOT NULL,
--   geom geometry(Polygon,4283) NOT NULL,
--   area float NULL
-- ) WITH (OIDS=FALSE);
-- ALTER TABLE admin_bdys.temp_messy_localities OWNER TO postgres;
-- CREATE INDEX temp_messy_localities_geom_idx ON admin_bdys.temp_messy_localities USING gist (geom);
-- ALTER TABLE admin_bdys.temp_messy_localities CLUSTER ON temp_messy_localities_geom_idx;
-- 


-- 
-- -- add ACT, NSW, OT, SA, TAS, VIC directly to the good table
-- INSERT INTO admin_bdys.temp_good_localities (gid, locality_pid, state, match_type, geom)
-- SELECT gid,
--        locality_pid,
--        state,
--        'DIRECT',
--        geom
-- FROM admin_bdys.temp_localities;
-- --WHERE state IN ('ACT', 'NSW', 'OT', 'SA', 'TAS', 'VIC');
-- 
-- --ALTER TABLE admin_bdys.temp_good_localities ADD CONSTRAINT temp_good_localities_pkey PRIMARY KEY(gid);
-- CREATE INDEX temp_good_localities_geom_idx ON admin_bdys.temp_good_localities USING gist (geom); ALTER TABLE admin_bdys.temp_good_localities CLUSTER ON temp_good_localities_geom_idx;
-- 
-- ANALYZE admin_bdys.temp_good_localities;


-- -- delete good localities from working list
-- DELETE FROM admin_bdys.temp_localities
-- WHERE state IN ('ACT', 'NSW', 'OT', 'SA', 'TAS', 'VIC');
-- 
-- ANALYZE admin_bdys.temp_localities;


