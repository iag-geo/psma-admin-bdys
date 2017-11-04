
-- add holes from subdivided border buffers that are entirely holes (and subsequently have been ignored) -- 280
INSERT INTO admin_bdys.temp_holes (state_gid, state, geom)
SELECT ste.new_gid,
       ste.state,
       ste.geom
  FROM admin_bdys.temp_state_border_buffers_subdivided AS ste
  INNER JOIN admin_bdys.temp_holes AS lne
  ON ST_Touches(ste.geom, lne.geom)
  LEFT OUTER JOIN admin_bdys.temp_holes AS hol 
  ON ste.new_gid = hol.state_gid
  WHERE hol.state_gid IS NULL;


-- create merged holes
DROP TABLE IF EXISTS admin_bdys.temp_holes_distinct;
CREATE TABLE admin_bdys.temp_holes_distinct (
  hole_gid serial NOT NULL PRIMARY KEY,
  state text NOT NULL,
  geom geometry(Polygon,4283) NOT NULL,
  locality_pid text,
  match_type text
) WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.temp_holes_distinct OWNER TO postgres;
CREATE INDEX temp_holes_distinct_geom_idx ON admin_bdys.temp_holes_distinct USING gist (geom);
ALTER TABLE admin_bdys.temp_holes_distinct CLUSTER ON temp_holes_distinct_geom_idx;

INSERT INTO admin_bdys.temp_holes_distinct (state, geom) -- 13192 -- 15458 
SELECT state, ST_MakeValid(ST_Buffer((ST_Dump(ST_Union(ST_Buffer(ST_Buffer(geom, -0.00000002), 0.00000002)))).geom, 0.0))
  FROM admin_bdys.temp_holes
  GROUP BY state;

ANALYZE admin_bdys.temp_holes_distinct;

-- -- reset 
-- DELETE FROM admin_bdys.temp_split_localities WHERE match_type IN ('GOOD BORDER', 'MESSY BORDER');
-- UPDATE admin_bdys.temp_split_localities SET match_type = 'SPLIT' WHERE match_type = 'MANUAL';


-- update locality/state border holes with locality PIDs when there is only one locality touching it (in the same state)

DROP TABLE IF EXISTS admin_bdys.temp_hole_localities; -- 1 min -- 20365 -- 15677 
SELECT DISTINCT loc.locality_pid, hol.hole_gid 
  INTO admin_bdys.temp_hole_localities
  FROM admin_bdys.temp_split_localities AS loc
  INNER JOIN admin_bdys.temp_holes_distinct AS hol
  ON (ST_Intersects(loc.geom, hol.geom)
    AND loc.loc_state = hol.state);


-- set good matches in temp table -- 17226 -- 15249 
UPDATE admin_bdys.temp_holes_distinct AS hol
  SET locality_pid = loc.locality_pid,
      match_type = 'GOOD'
  FROM (
    SELECT Count(*) AS cnt, hole_gid FROM admin_bdys.temp_hole_localities GROUP BY hole_gid
  ) AS sqt,
  admin_bdys.temp_hole_localities AS loc
  WHERE hol.hole_gid = sqt.hole_gid
  AND sqt.hole_gid = loc.hole_gid
  AND sqt.cnt = 1;


-- Add good holes to split localities -- 17226 -- 15249 
INSERT INTO admin_bdys.temp_split_localities (gid, locality_pid, loc_state, ste_state, match_type, geom)
SELECT 900000000 + hole_gid,
       locality_pid,
       state AS loc_state,
       state AS ste_state,
       'GOOD BORDER' AS match_type, 
       geom
  FROM admin_bdys.temp_holes_distinct
  WHERE match_type = 'GOOD';

--turf the good records so we can focus on the rest -- 17226 -- 15249 
DELETE FROM admin_bdys.temp_hole_localities AS loc
  USING admin_bdys.temp_holes_distinct AS hol
  WHERE loc.hole_gid = hol.hole_gid
  AND hol.locality_pid IS NOT NULL;


-- Delete unmatched holes that have an area < 1m2 -- 8577 -- 5171 
DELETE FROM admin_bdys.temp_holes_distinct
  WHERE ST_Area(ST_Transform(geom, 3577)) < 1.0;


-- split remaining locality/state border holes at the point where 2 localities meet the hole and add to working localities table

-- get locality polygon points along shared edges of remaining holes -- 15499 -- 15667 
DROP TABLE IF EXISTS admin_bdys.temp_hole_points_temp;
SELECT DISTINCT *
  INTO admin_bdys.temp_hole_points_temp
  FROM (
    SELECT loc.locality_pid,
           hol.hole_gid,
           hol.state,
           (ST_DumpPoints(PolygonalIntersection(loc.geom, hol.geom))).geom::geometry(Point, 4283) AS geom
      FROM admin_bdys.temp_split_localities AS loc
      INNER JOIN admin_bdys.temp_holes_distinct AS hol ON (ST_Intersects(loc.geom, hol.geom) AND loc.loc_state = hol.state)
      INNER JOIN admin_bdys.temp_hole_localities AS lochol ON hol.hole_gid = lochol.hole_gid
) AS sqt;

-- get unique points shared by more than 1 locality - 239 -- 226 
DROP TABLE IF EXISTS admin_bdys.temp_hole_points;
CREATE TABLE admin_bdys.temp_hole_points
(
  gid serial NOT NULL PRIMARY KEY,
  hole_gid integer NOT NULL,
  state text NOT NULL,
  geom geometry(Point,4283) NOT NULL
) WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.temp_hole_points OWNER TO postgres;

INSERT INTO admin_bdys.temp_hole_points (hole_gid, state, geom) 
SELECT hole_gid, state, geom
    FROM (
    SELECT Count(*) AS cnt, hole_gid, state, geom FROM admin_bdys.temp_hole_points_temp GROUP BY hole_gid, state, geom
  ) AS sqt
  WHERE sqt.cnt > 1;

DROP TABLE IF EXISTS admin_bdys.temp_hole_points_temp;


-- get points shared between 2 localities to the state border (to be used to split the remaining holes)
DROP TABLE IF EXISTS admin_bdys.temp_line_points; -- 1317 -- 1246
SELECT DISTINCT pnt.gid,
       pnt.hole_gid,
       pnt.state,
       pnt.geom AS geomA,
       ST_ClosestPoint(ST_Boundary(ste.geom), pnt.geom) AS geomB
  INTO admin_bdys.temp_line_points
  FROM admin_bdys.temp_hole_points AS pnt
  INNER JOIN admin_bdys.temp_state_border_buffers AS ste ON pnt.state = ste.state;

DROP TABLE IF EXISTS admin_bdys.temp_hole_points;

-- calc values for extending a line beyond the 2 points were interested in
DROP TABLE IF EXISTS admin_bdys.temp_line_calcs; -- 1317 -- 1246
SELECT gid,
       hole_gid,
       state,
       geomA AS geom,
       ST_Azimuth(geomA, geomB) AS azimuthAB,
       ST_Azimuth(geomB, geomA) AS azimuthBA,
       ST_Distance(geomA, geomB) + 0.00001 AS dist
  INTO admin_bdys.temp_line_calcs
  FROM admin_bdys.temp_line_points;

-- get lines from points shared between 2 localities to the state border (to be used to split the remaining holes)
DROP TABLE IF EXISTS admin_bdys.temp_hole_lines; -- 1317 -- 1246
SELECT DISTINCT pnt.gid,
       pnt.hole_gid,
       pnt.state,
       pnt.dist,
       ST_MakeLine(ST_Translate(pnt.geom, sin(azimuthBA) * 0.00001, cos(azimuthBA) * 0.00001), ST_Translate(pnt.geom, sin(azimuthAB) * pnt.dist, cos(azimuthAB) * pnt.dist))::geometry(Linestring, 4283) AS geom
  INTO admin_bdys.temp_hole_lines
  FROM admin_bdys.temp_line_calcs AS pnt
  INNER JOIN admin_bdys.temp_state_border_buffers AS ste ON pnt.state = ste.state;


-- get the shortest splitter lines -- 191 -- 188
DROP TABLE IF EXISTS admin_bdys.temp_hole_splitter_lines;
SELECT lne.hole_gid,
       lne.state,
       ST_Multi(ST_Union(lne.geom))::geometry(MultiLinestring, 4283) AS geom
  INTO admin_bdys.temp_hole_splitter_lines
  FROM (
    SELECT gid, state, MIN(dist) AS dist FROM admin_bdys.temp_hole_lines GROUP BY gid, state
  ) AS sqt
  INNER JOIN admin_bdys.temp_hole_lines AS lne ON (sqt.gid = lne.gid AND sqt.dist = lne.dist)
  INNER JOIN admin_bdys.temp_holes_distinct AS hol ON ST_Intersects(lne.geom, hol.geom)
  GROUP BY lne.hole_gid,
       lne.state;

DROP TABLE IF EXISTS admin_bdys.temp_line_points;
DROP TABLE IF EXISTS admin_bdys.temp_line_calcs;
DROP TABLE IF EXISTS admin_bdys.temp_hole_lines;


-- split the remaining holes -- -- 416
DROP TABLE IF EXISTS admin_bdys.temp_holes_split;
CREATE TABLE admin_bdys.temp_holes_split
(
  gid serial NOT NULL PRIMARY KEY,
  hole_gid integer NOT NULL,
  locality_pid text NULL,
  state text NOT NULL,
  type text NOT NULL,
  geom geometry(Polygon,4283) NOT NULL
) WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.temp_holes_split OWNER TO postgres;

INSERT INTO admin_bdys.temp_holes_split (hole_gid, state, type, geom)
SELECT hol.hole_gid,
       hol.state,
       'SPLIT',
       (ST_Dump(ST_SplitPolygon(hol.hole_gid, ST_Buffer(ST_Buffer(hol.geom, -0.00000001), 0.00000002), ST_Union(lne.geom)))).geom::geometry(Polygon, 4283) AS geom
  FROM admin_bdys.temp_hole_splitter_lines AS lne
  INNER JOIN admin_bdys.temp_holes_distinct AS hol
  ON (ST_Intersects(ST_Buffer(ST_Buffer(hol.geom, -0.00000001), 0.00000002), lne.geom) AND hol.state = lne.state)
  WHERE hol.locality_pid IS NULL
  GROUP BY hol.hole_gid,
       hol.state;

-- didn't split right - these are Ok!
-- NOTICE:  NOT ENOUGH POLYGONS! : id 15157 : blades 1 : num output polys 1
-- NOTICE:  NOT ENOUGH POLYGONS! : id 731 : blades 17 : num output polys 1

-- assign fixed holes to localities -- 760 -- 799
DROP TABLE IF EXISTS admin_bdys.temp_holes_split_locs;
SELECT hol.gid,
       loc.locality_pid,
       hol.state,
       ST_Length(ST_Boundary(PolygonalIntersection(hol.geom, loc.geom))) AS dist
  INTO admin_bdys.temp_holes_split_locs
  FROM admin_bdys.temp_holes_split AS hol
  INNER JOIN admin_bdys.temp_split_localities AS loc
  ON (ST_Intersects(hol.geom, loc.geom) AND hol.state = loc.loc_state);


-- get the locality pids with the most frontage to the split holes -- 423 -- 415
UPDATE admin_bdys.temp_holes_split as spl
  SET locality_pid = hol.locality_pid
  FROM (
    SELECT gid, MAX(dist) AS dist FROM admin_bdys.temp_holes_split_locs GROUP BY gid
  ) AS sqt,
  admin_bdys.temp_holes_split_locs AS hol
  WHERE spl.gid = sqt.gid
  AND (sqt.gid = hol.gid AND sqt.dist = hol.dist)
  AND hol.dist > 0;


--update holes distinct so we can see who hasn't been allocated -- 187 -- 188
UPDATE admin_bdys.temp_holes_distinct AS hol
  SET match_type = 'MESSY'
  FROM admin_bdys.temp_holes_split as spl
  WHERE hol.hole_gid = spl.hole_gid
  AND spl.locality_pid IS NOT NULL;


-- Add good holes to split localities -- 423 -- 415
INSERT INTO admin_bdys.temp_split_localities (gid, locality_pid, loc_state, ste_state, match_type, geom)
SELECT 900000000 + gid,
       locality_pid,
       state AS loc_state,
       state AS ste_state,
       'MESSY BORDER' AS match_type, 
       geom
  FROM admin_bdys.temp_holes_split
  WHERE locality_pid IS NOT NULL;


-- update locality polygons that have a manual fix point on them -- 160 -- 159
UPDATE admin_bdys.temp_split_localities AS loc
  SET match_type = 'MANUAL'
  FROM admin_bdys.temp_messy_centroids AS pnt
  WHERE (ST_Within(pnt.geom, loc.geom) OR loc.locality_pid = 'NSW4451') -- NSW4451 = Woronora
  AND loc.match_type = 'SPLIT';

-- manual fix to remove an unpopulated, oversized torres straight, QLD polygon -- 1
UPDATE admin_bdys.temp_split_localities
  SET match_type = 'SPLIT'
  WHERE ST_Intersects(ST_SetSRID(ST_MakePoint(144.227305683, -9.39107887741), 4283), geom);


-- merge final polygons -- 26 mins -- 15565
DROP TABLE IF EXISTS admin_bdys.locality_bdys_display_full_res CASCADE;
CREATE TABLE admin_bdys.locality_bdys_display_full_res (
  locality_pid text PRIMARY KEY,
  locality_name text,
  postcode character(4),
  state text,
  geom geometry(MultiPolygon, 4283),
  area numeric(20,3)
) WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.locality_bdys_display_full_res OWNER TO postgres;

INSERT INTO admin_bdys.locality_bdys_display_full_res (locality_pid, locality_name, postcode, state, geom)
SELECT tmp.locality_pid,
       loc.locality_name,
       loc.postcode,
       loc.state,
       ST_Multi(ST_MakeValid(ST_Buffer(ST_Buffer(ST_Union(ST_MakeValid(tmp.geom)), -0.00000001), 0.00000001)))
  FROM admin_bdys.temp_split_localities AS tmp
  INNER JOIN admin_bdys.locality_bdys AS loc
  ON tmp.locality_pid = loc.locality_pid
  WHERE tmp.match_type <> 'SPLIT'
  GROUP BY tmp.locality_pid,
		loc.locality_name,
	  loc.postcode,
    loc.state;

CREATE INDEX localities_display_full_res_geom_idx ON admin_bdys.locality_bdys_display_full_res USING gist (geom);
ALTER TABLE admin_bdys.locality_bdys_display_full_res CLUSTER ON localities_display_full_res_geom_idx;

ANALYZE admin_bdys.locality_bdys_display_full_res;


 -- simplify and clean up data, removing unwanted artifacts -- 1 min -- 17731  -- OLD METHOD
 DROP TABLE IF EXISTS admin_bdys.temp_final_localities;
 CREATE TABLE admin_bdys.temp_final_localities (
   locality_pid text,
   geom geometry
 ) WITH (OIDS=FALSE);
 ALTER TABLE admin_bdys.temp_final_localities OWNER TO postgres;

 INSERT INTO admin_bdys.temp_final_localities (locality_pid, geom)
 SELECT locality_pid,
        (ST_Dump(ST_MakeValid(ST_Multi(ST_SnapToGrid(ST_SimplifyVW(geom, 9.208633852887194e-09), 0.00001))))).geom
   FROM admin_bdys.locality_bdys_display_full_res;

 DELETE FROM admin_bdys.temp_final_localities WHERE ST_GeometryType(geom) <> 'ST_Polygon'; -- 20


 -- insert grouped polygons into final table -- OLD METHOD
 DROP TABLE IF EXISTS admin_bdys.locality_bdys_display CASCADE;
 CREATE TABLE admin_bdys.locality_bdys_display
 (
   gid serial NOT NULL,
   locality_pid text NOT NULL,
   locality_name text NOT NULL,
   postcode text NULL,
   state text NOT NULL,
   locality_class text NOT NULL,
   address_count integer NOT NULL,
   street_count integer NOT NULL,
   geom geometry(MultiPolygon,4283) NOT NULL,
   CONSTRAINT locality_bdys_display_pk PRIMARY KEY (locality_pid)
 ) WITH (OIDS=FALSE);
 ALTER TABLE admin_bdys.locality_bdys_display
   OWNER TO postgres;

-- ALTER TABLE admin_bdys.locality_bdys_display
--   OWNER TO rw;
-- GRANT ALL ON TABLE admin_bdys.locality_bdys_display TO rw;
-- GRANT SELECT ON TABLE admin_bdys.locality_bdys_display TO readonly;
-- GRANT SELECT ON TABLE admin_bdys.locality_bdys_display TO metacentre;
-- GRANT SELECT ON TABLE admin_bdys.locality_bdys_display TO ro;
-- GRANT ALL ON TABLE admin_bdys.locality_bdys_display TO update;


 INSERT INTO admin_bdys.locality_bdys_display(locality_pid, locality_name, postcode, state, locality_class, address_count, street_count, geom) -- 15565
 SELECT loc.locality_pid,
        loc.locality_name,
        loc.postcode,
        loc.state,
        loc.locality_class,
        loc.address_count,
        loc.street_count,
        bdy.geom
   FROM admin_bdys.locality_bdys AS loc
   INNER JOIN (
     SELECT locality_pid,
            ST_Multi(ST_Union(geom)) AS geom
       FROM admin_bdys.temp_final_localities
       GROUP by locality_pid
   ) AS bdy
   ON loc.locality_pid = bdy.locality_pid;

 CREATE INDEX localities_display_geom_idx ON admin_bdys.locality_bdys_display USING gist (geom);
 ALTER TABLE admin_bdys.locality_bdys_display CLUSTER ON localities_display_geom_idx;

 ANALYZE admin_bdys.locality_bdys_display;


-- set role postgres;

---- insert grouped polygons into final table - using VW simplification instead!
--DROP TABLE IF EXISTS admin_bdys.locality_bdys_display CASCADE;
--CREATE TABLE admin_bdys.locality_bdys_display
--(
--  gid serial NOT NULL,
--  locality_pid text NOT NULL,
--  locality_name text NOT NULL,
--  postcode text NULL,
--  state text NOT NULL,
--  locality_class text NOT NULL,
--  address_count integer NOT NULL,
--  street_count integer NOT NULL,
--  geom geometry(MultiPolygon,4283) NOT NULL,
--  CONSTRAINT locality_bdys_display_pk PRIMARY KEY (locality_pid)
--) WITH (OIDS=FALSE);
--ALTER TABLE admin_bdys.locality_bdys_display
--  OWNER TO postgres;
--
----ALTER TABLE admin_bdys.locality_bdys_display
----  OWNER TO rw;
----GRANT ALL ON TABLE admin_bdys.locality_bdys_display TO rw;
----GRANT SELECT ON TABLE admin_bdys.locality_bdys_display TO readonly;
----GRANT SELECT ON TABLE admin_bdys.locality_bdys_display TO metacentre;
----GRANT SELECT ON TABLE admin_bdys.locality_bdys_display TO ro;
----GRANT ALL ON TABLE admin_bdys.locality_bdys_display TO update;
--
--INSERT INTO admin_bdys.locality_bdys_display(locality_pid, locality_name, postcode, state, locality_class, address_count, street_count, geom) -- 15565
--  SELECT loc.locality_pid,
--    loc.locality_name,
--    loc.postcode,
--    loc.state,
--    loc.locality_class,
--    loc.address_count,
--    loc.street_count,
--    bdy.geom
--  FROM admin_bdys.locality_bdys AS loc
--    INNER JOIN (
--                 SELECT locality_pid,
--                   ST_Multi(ST_Union(ST_MakeValid(ST_SnapToGid(ST_SimplifyVW(geom, 9.2e-09)))) AS geom
--                 FROM admin_bdys.locality_bdys_display_full_res
--                 GROUP by locality_pid
--               ) AS bdy
--      ON loc.locality_pid = bdy.locality_pid;
--
--CREATE INDEX locality_bdys_display_geom_idx ON admin_bdys.locality_bdys_display USING gist (geom);
--ALTER TABLE admin_bdys.locality_bdys_display CLUSTER ON locality_bdys_display_geom_idx;
--
--ANALYZE admin_bdys.locality_bdys_display;

-- clean up
DROP TABLE IF EXISTS admin_bdys.temp_holes_split_locs;
DROP TABLE IF EXISTS admin_bdys.temp_final_localities;
DROP TABLE IF EXISTS admin_bdys.temp_hole_localities;
DROP TABLE IF EXISTS admin_bdys.temp_holes_distinct;
DROP TABLE IF EXISTS admin_bdys.temp_holes;
DROP TABLE IF EXISTS admin_bdys.temp_split_localities;
DROP TABLE IF EXISTS admin_bdys.temp_states;
DROP TABLE IF EXISTS admin_bdys.temp_messy_centroids;
DROP TABLE IF EXISTS admin_bdys.temp_hole_splitter_lines;
DROP TABLE IF EXISTS admin_bdys.temp_holes_split;
DROP TABLE IF EXISTS admin_bdys.temp_state_border_buffers_subdivided;
DROP TABLE IF EXISTS admin_bdys.temp_state_border_buffers;
DROP TABLE IF EXISTS admin_bdys.temp_state_lines;
DROP TABLE IF EXISTS admin_bdys.temp_localities;
