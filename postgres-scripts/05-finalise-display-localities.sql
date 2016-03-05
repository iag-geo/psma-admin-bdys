
DROP TABLE IF EXISTS admin_bdys.temp_holes_distinct;
CREATE TABLE admin_bdys.temp_holes_distinct (
  hole_gid serial NOT NULL PRIMARY KEY,
  state character varying(3) NOT NULL,
  geom geometry(Polygon,4283) NOT NULL,
  locality_pid character varying(16),
  match_type character varying(16)
) WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.temp_holes_distinct OWNER TO postgres;
CREATE INDEX temp_holes_distinct_geom_idx ON admin_bdys.temp_holes_distinct USING gist (geom);
ALTER TABLE admin_bdys.temp_holes_distinct CLUSTER ON temp_holes_distinct_geom_idx;

INSERT INTO admin_bdys.temp_holes_distinct (state, geom) -- 13192 
SELECT state, ST_MakeValid(ST_Buffer((ST_Dump(ST_Union(ST_Buffer(ST_Buffer(geom, -0.00000001), 0.00000002)))).geom, 0.0)) FROM admin_bdys.temp_holes GROUP BY state;
--SELECT state, (ST_Dump(ST_MakeValid(ST_Buffer(ST_Buffer(ST_Union(geom), -0.00000001), 0.00000002)))).geom FROM admin_bdys.temp_holes GROUP BY state;

-- UPDATE admin_bdys.temp_holes_distinct -- 14888 
--   SET geom = (ST_Dump(ST_MakeValid(ST_Buffer(ST_Buffer(geom, -0.0000001), 0.0000002)))).geom;

ANALYZE admin_bdys.temp_holes_distinct;

-- -- reset 
-- DELETE FROM admin_bdys.temp_split_localities WHERE match_type IN ('GOOD BORDER', 'MESSY BORDER');
-- UPDATE admin_bdys.temp_split_localities SET match_type = 'SPLIT' WHERE match_type = 'MANUAL';


-- update locality/state border holes with locality PIDs when there is only one locality touching it (in the same state)

DROP TABLE IF EXISTS admin_bdys.temp_hole_localities; -- 1 min -- 20365  
SELECT DISTINCT loc.locality_pid, hol.hole_gid 
  INTO admin_bdys.temp_hole_localities
  FROM admin_bdys.temp_split_localities AS loc
  INNER JOIN admin_bdys.temp_holes_distinct AS hol
  ON (ST_Intersects(loc.geom, hol.geom)
    AND loc.loc_state = hol.state);


-- set good matches in temp table -- 17226 
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


-- Add good holes to split localities -- 17226 
INSERT INTO admin_bdys.temp_split_localities (gid, locality_pid, loc_state, ste_state, match_type, geom)
SELECT 900000000 + hole_gid,
       locality_pid,
       state AS loc_state,
       state AS ste_state,
       'GOOD BORDER' AS match_type, 
       geom
  FROM admin_bdys.temp_holes_distinct
  WHERE match_type = 'GOOD';

--turf the good records so we can focus on the rest -- 17226  
DELETE FROM admin_bdys.temp_hole_localities AS loc
  USING admin_bdys.temp_holes_distinct AS hol
  WHERE loc.hole_gid = hol.hole_gid
  AND hol.locality_pid IS NOT NULL;


-- Delete unmatched holes that have an area < 1m2 -- 8577 
DELETE FROM admin_bdys.temp_holes_distinct
  WHERE ST_Area(ST_Transform(geom, 3577)) < 1.0;


-- split remaining locality/state border holes at the point where 2 localities meet the hole and add to working localities table

-- get locality polygon points along shared edges of remaining holes -- 15499      
DROP TABLE IF EXISTS admin_bdys.temp_hole_points_temp;
SELECT DISTINCT *
  INTO admin_bdys.temp_hole_points_temp
  FROM (
    SELECT loc.locality_pid,
           hol.hole_gid,
           hol.state,
           (ST_DumpPoints(ST_Intersection(loc.geom, hol.geom))).geom::geometry(Point, 4283) AS geom
      FROM admin_bdys.temp_split_localities AS loc
      INNER JOIN admin_bdys.temp_holes_distinct AS hol ON (ST_Intersects(loc.geom, hol.geom) AND loc.loc_state = hol.state)
      INNER JOIN admin_bdys.temp_hole_localities AS lochol ON hol.hole_gid = lochol.hole_gid
) AS sqt;

-- get unique points shared by more than 1 locality - 239
DROP TABLE IF EXISTS admin_bdys.temp_hole_points;
CREATE TABLE admin_bdys.temp_hole_points
(
  gid serial NOT NULL PRIMARY KEY,
  hole_gid integer NOT NULL,
  state character varying(3) NOT NULL,
  geom geometry(Point,4283) NOT NULL
) WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.temp_hole_points OWNER TO postgres;

INSERT INTO admin_bdys.temp_hole_points (hole_gid, state, geom) 
SELECT hole_gid, state, geom
    FROM (
    SELECT Count(*) AS cnt, hole_gid, state, geom FROM admin_bdys.temp_hole_points_temp GROUP BY hole_gid, state, geom
--     SELECT Count(*) AS cnt, hole_gid, state, ST_Y(geom)::numeric(10,8) AS latitude, ST_X(geom)::numeric(11,8) AS longitude FROM admin_bdys.temp_hole_points_temp GROUP BY hole_gid, state, ST_Y(geom)::numeric(10,8), ST_X(geom)::numeric(11,8)
  ) AS sqt
  WHERE sqt.cnt > 1;

--DROP TABLE IF EXISTS admin_bdys.temp_hole_points_temp;


-- get points shared between 2 localities to the state border (to be used to split the remaining holes)
DROP TABLE IF EXISTS admin_bdys.temp_line_points; -- 1317       
SELECT DISTINCT pnt.gid,
       pnt.hole_gid,
       pnt.state,
       pnt.geom AS geomA,
       ST_ClosestPoint(ST_Boundary(ste.geom), pnt.geom) AS geomB
  INTO admin_bdys.temp_line_points
  FROM admin_bdys.temp_hole_points AS pnt
  INNER JOIN admin_bdys.temp_state_border_buffers AS ste ON pnt.state = ste.state;

--DROP TABLE IF EXISTS admin_bdys.temp_hole_points;

-- calc values for extending a line beyond the 2 points were interested in
DROP TABLE IF EXISTS admin_bdys.temp_line_calcs; -- 1317        
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
DROP TABLE IF EXISTS admin_bdys.temp_hole_lines; -- 1317       
SELECT DISTINCT pnt.gid,
       pnt.hole_gid,
       pnt.state,
       pnt.dist,
       ST_MakeLine(ST_Translate(pnt.geom, sin(azimuthBA) * 0.00001, cos(azimuthBA) * 0.00001), ST_Translate(pnt.geom, sin(azimuthAB) * pnt.dist, cos(azimuthAB) * pnt.dist))::geometry(Linestring, 4283) AS geom
--        ST_MakeLine(pnt.geom, ST_Translate(pnt.geom, sin(azimuthAB) * pnt.dist, cos(azimuthAB) * pnt.dist))::geometry(Linestring, 4283) AS geom
  INTO admin_bdys.temp_hole_lines
  FROM admin_bdys.temp_line_calcs AS pnt
  INNER JOIN admin_bdys.temp_state_border_buffers AS ste ON pnt.state = ste.state;


-- get the shortest splitter lines -- 191
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

-- DROP TABLE IF EXISTS admin_bdys.temp_line_points;
DROP TABLE IF EXISTS admin_bdys.temp_line_calcs;
DROP TABLE IF EXISTS admin_bdys.temp_hole_lines;


-- -- manual fix for NT/QLD border issue
-- INSERT INTO admin_bdys.temp_hole_splitter_lines
-- SELECT (SELECT gid FROM admin_bdys.temp_holes_distinct WHERE ST_Intersects(St_SetSRID(ST_MakePoint(137.999, -17.600), 4283), geom)),
--        'NT',
--        ST_Multi(ST_GeomFromText('LINESTRING(137.99519933848674214 -17.6113710627822293, 138.00147236831551822 -17.61135804369208557)', 4283));


-- spit the remaining holes -- -- 423
DROP TABLE IF EXISTS admin_bdys.temp_holes_split;
CREATE TABLE admin_bdys.temp_holes_split
(
  gid serial NOT NULL PRIMARY KEY,
  hole_gid integer NOT NULL,
  locality_pid character varying(16) NULL,
  state character varying(3) NOT NULL,
  type varchar(50) NOT NULL,
  geom geometry(Polygon,4283) NOT NULL
) WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.temp_holes_split OWNER TO postgres;

INSERT INTO admin_bdys.temp_holes_split (hole_gid, state, type, geom)
SELECT hol.hole_gid,
       hol.state,
       'SPLIT',
       --(ST_Dump(ST_SplitPolygon(hol.gid, hol.geom, lne.geom))).geom::geometry(Polygon, 4283) AS geom
       (ST_Dump(ST_SplitPolygon(hol.hole_gid, ST_Buffer(ST_Buffer(hol.geom, -0.00000001), 0.00000002), ST_Union(lne.geom)))).geom::geometry(Polygon, 4283) AS geom
  FROM admin_bdys.temp_hole_splitter_lines AS lne
  INNER JOIN admin_bdys.temp_holes_distinct AS hol
  ON (ST_Intersects(ST_Buffer(ST_Buffer(hol.geom, -0.00000001), 0.00000002), lne.geom) AND hol.state = lne.state)
  WHERE hol.locality_pid IS NULL
  GROUP BY hol.hole_gid,
       hol.state;

-- didn't split right
-- NOTICE:  NOT ENOUGH POLYGONS! : id 16475 : blades 1 : num output polys 1


-- assign fixed holes to localities -- 760
DROP TABLE IF EXISTS admin_bdys.temp_holes_split_locs;
SELECT hol.gid,
       loc.locality_pid,
       hol.state,
       ST_Length(ST_Boundary(ST_Intersection(hol.geom, loc.geom))) AS dist
  INTO admin_bdys.temp_holes_split_locs
  FROM admin_bdys.temp_holes_split AS hol
  INNER JOIN admin_bdys.temp_split_localities AS loc
  ON (ST_Intersects(hol.geom, loc.geom) AND hol.state = loc.loc_state);

--select * from admin_bdys.temp_holes_split_locs where gid = 275;


-- get the locality pids with the most frontage to the split holes -- 423
UPDATE admin_bdys.temp_holes_split as spl
  SET locality_pid = hol.locality_pid
  FROM (
    SELECT gid, MAX(dist) AS dist FROM admin_bdys.temp_holes_split_locs GROUP BY gid
  ) AS sqt,
  admin_bdys.temp_holes_split_locs AS hol
  WHERE spl.gid = sqt.gid
  AND (sqt.gid = hol.gid AND sqt.dist = hol.dist)
  AND hol.dist > 0;


--update holes distinct so we can see who hasn't been allocated -- 187
UPDATE admin_bdys.temp_holes_distinct AS hol
  SET match_type = 'MESSY'
  FROM admin_bdys.temp_holes_split as spl
  WHERE hol.hole_gid = spl.hole_gid
  AND spl.locality_pid IS NOT NULL;


-- Add good holes to split localities -- 423
INSERT INTO admin_bdys.temp_split_localities (gid, locality_pid, loc_state, ste_state, match_type, geom)
SELECT 900000000 + gid,
       locality_pid,
       state AS loc_state,
       state AS ste_state,
       'MESSY BORDER' AS match_type, 
       geom
  FROM admin_bdys.temp_holes_split
  WHERE locality_pid IS NOT NULL;


-- update locality polygons that have a manual fix point on them -- 160
UPDATE admin_bdys.temp_split_localities AS loc
  SET match_type = 'MANUAL'
  FROM admin_bdys.temp_messy_centroids AS pnt
  WHERE (ST_Within(pnt.geom, loc.geom) OR loc.locality_pid = 'NSW4451') -- NSW4451 = Woronora
  AND loc.match_type = 'SPLIT';

-- manual fix to remove an unpopulated, oversized torres straight, QLD polygon
UPDATE admin_bdys.temp_split_localities
  SET match_type = 'SPLIT'
  WHERE ST_Intersects(ST_SetSRID(ST_MakePoint(144.227305683, -9.39107887741), 4283), geom);




-- --merge the results into a single table
-- DROP TABLE IF EXISTS admin_bdys.temp_sqt;
-- SELECT locality_pid,
--        ST_Multi(ST_Union(geom)) AS geom
--   INTO admin_bdys.temp_sqt
--   FROM admin_bdys.temp_split_localities
--   WHERE match_type <> 'SPLIT'
--   GROUP BY locality_pid;


-- merge final polygons -- 3 mins -- 15565 
DROP TABLE IF EXISTS admin_bdys.temp_final_localities;
CREATE TABLE admin_bdys.temp_final_localities (
  locality_pid character varying(16),
  geom geometry(MultiPolygon, 4283),
  area numeric(20,3)
) WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.temp_final_localities OWNER TO postgres;

INSERT INTO admin_bdys.temp_final_localities (locality_pid, geom) -- 34730 
SELECT locality_pid,
--       ST_Multi(ST_Union((ST_Dump(ST_Buffer(ST_Buffer(geom, -0.00000001), 0.00000001))).geom))
       ST_Multi(ST_Buffer(ST_Buffer(ST_Union(geom), -0.00000001), 0.00000001))
  FROM admin_bdys.temp_split_localities
  WHERE match_type <> 'SPLIT'
  GROUP BY locality_pid;
  --FROM admin_bdys.temp_sqt;

--DROP TABLE IF EXISTS admin_bdys.temp_sqt;

-- -- get areas
-- UPDATE admin_bdys.temp_final_localities
--   SET area = (ST_Area(ST_Transform(geom, 3577)) / 1000000)::numeric(20,3);


-- simplify and clean up data, removing unwanted artifacts -- 1 min -- 17751 
DROP TABLE IF EXISTS admin_bdys.temp_final_localities2;
CREATE TABLE admin_bdys.temp_final_localities2 (
  locality_pid character varying(16),
  geom geometry
) WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.temp_final_localities2 OWNER TO postgres;

INSERT INTO admin_bdys.temp_final_localities2 (locality_pid, geom)
SELECT locality_pid,
       (ST_Dump(ST_MakeValid(ST_Multi(ST_SnapToGrid(ST_Simplify(geom, 0.00002), 0.00001))))).geom
  FROM admin_bdys.temp_final_localities;

DELETE FROM admin_bdys.temp_final_localities2 WHERE ST_GeometryType(geom) <> 'ST_Polygon'; -- 38


-- insert grouped polygons into final table
DROP TABLE IF EXISTS admin_bdys.locality_bdys_display;
CREATE TABLE admin_bdys.locality_bdys_display
(
  gid serial NOT NULL,
  locality_pid character varying(16) NOT NULL,
  locality_name character varying(100) NOT NULL,
  postcode character(4) NULL,
  state character varying(3) NOT NULL,
  locality_class character varying(50) NOT NULL,
  address_count integer NOT NULL,
  street_count integer NOT NULL,
  geom geometry(MultiPolygon,4283) NOT NULL,
  CONSTRAINT localities_display_pk PRIMARY KEY (locality_pid)
) WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.locality_bdys_display OWNER TO postgres;
CREATE INDEX localities_display_geom_idx ON admin_bdys.locality_bdys_display USING gist (geom);
ALTER TABLE admin_bdys.locality_bdys_display CLUSTER ON localities_display_geom_idx;

INSERT INTO admin_bdys.locality_bdys_display(locality_pid, locality_name, postcode, state, locality_class, address_count, street_count, geom) -- 15561 
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
      FROM admin_bdys.temp_final_localities2
      GROUP by locality_pid
  ) AS bdy
  ON loc.locality_pid = bdy.locality_pid;

ANALYZE admin_bdys.locality_bdys_display;


-- clean up
--DROP TABLE IF EXISTS admin_bdys.temp_holes_split_locs;
--DROP TABLE IF EXISTS admin_bdys.temp_final_localities2;
--DROP TABLE IF EXISTS admin_bdys.temp_final_localities;
--DROP TABLE IF EXISTS admin_bdys.temp_hole_localities;
--DROP TABLE IF EXISTS admin_bdys.temp_holes_distinct;
--DROP TABLE IF EXISTS admin_bdys.temp_holes;
--DROP TABLE IF EXISTS admin_bdys.temp_split_localities;
--DROP TABLE IF EXISTS admin_bdys.temp_states;
--DROP TABLE IF EXISTS admin_bdys.temp_messy_centroids;
--DROP TABLE IF EXISTS admin_bdys.temp_hole_splitter_lines;
--DROP TABLE IF EXISTS admin_bdys.temp_holes_split;
--DROP TABLE IF EXISTS admin_bdys.temp_state_border_buffers;
--DROP TABLE IF EXISTS admin_bdys.temp_state_lines;
--DROP TABLE IF EXISTS admin_bdys.temp_localities;


select ST_Area(ST_Transform(geom, 3577)) AS area, * from admin_bdys.temp_holes_distinct where match_type IS NULL;



-- ST_Area(ST_Transform(loc1.geom, 3577)) < 3000
--   AND 

--select * from admin_bdys.locality_bdys_display where ST_IsEmpty(geom); -- 0

-- select * from admin_bdys.temp_final_localities where NOT ST_IsValid(geom); -- 0
-- select * from admin_bdys.locality_bdys_display where NOT ST_IsValid(geom); -- 0
