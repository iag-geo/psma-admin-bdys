
DROP TABLE IF EXISTS admin_bdys.temp_holes_distinct;
CREATE TABLE admin_bdys.temp_holes_distinct (
  gid serial NOT NULL PRIMARY KEY,
  state character varying(3) NOT NULL,
  geom geometry(Polygon,4283) NOT NULL,
  locality_pid character varying(16),
  match_type character varying(16)
) WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.temp_holes_distinct OWNER TO postgres;
CREATE INDEX temp_holes_distinct_geom_idx ON admin_bdys.temp_holes_distinct USING gist (geom);
ALTER TABLE admin_bdys.temp_holes_distinct CLUSTER ON temp_holes_distinct_geom_idx;

INSERT INTO admin_bdys.temp_holes_distinct (state, geom) -- 16563 
SELECT state, ST_MakeValid(ST_Buffer((ST_Dump(ST_Union(geom))).geom, 0.0)) FROM admin_bdys.temp_holes GROUP BY state;

ANALYZE admin_bdys.temp_holes_distinct;


-- update locality/state border holes with locality PIDs when there is only one locality touching it (in the same state)

-- -- reset 
DELETE FROM admin_bdys.temp_split_localities WHERE match_type IN ('GOOD BORDER', 'MESSY BORDER');
-- UPDATE admin_bdys.temp_holes_distinct SET locality_pid = NULL;

DROP TABLE IF EXISTS admin_bdys.temp_hole_localities; -- 1 min -- 16799 
SELECT loc.locality_pid, ste.gid
  INTO admin_bdys.temp_hole_localities
  FROM admin_bdys.temp_split_localities AS loc
  INNER JOIN admin_bdys.temp_holes_distinct AS ste
  ON (ST_Touches(loc.geom, ste.geom)
    AND loc.loc_state = ste.state);

-- Manual fix for visual problem along NT border -- 137.999, -17.600
INSERT INTO admin_bdys.temp_hole_localities
SELECT 'NT212',
       (SELECT gid FROM admin_bdys.temp_holes_distinct WHERE ST_Intersects(St_SetSRID(ST_MakePoint(137.999, -17.600), 4283), geom));


UPDATE admin_bdys.temp_holes_distinct AS hol -- 16318  
  SET locality_pid = loc.locality_pid,
      match_type = 'GOOD'
  FROM (
    SELECT Count(*) AS cnt, gid FROM admin_bdys.temp_hole_localities GROUP BY gid
  ) AS sqt,
  admin_bdys.temp_hole_localities AS loc
  WHERE hol.gid = sqt.gid
  AND sqt.gid = loc.gid
  AND sqt.cnt = 1;

-- Add good holes to split localities -- 16318  
INSERT INTO admin_bdys.temp_split_localities (gid, locality_pid, loc_state, ste_state, match_type, geom)
SELECT 900000000 + gid,
       locality_pid,
       state AS loc_state,
       state AS ste_state,
       'GOOD BORDER' AS match_type, 
       geom
  FROM admin_bdys.temp_holes_distinct
  WHERE match_type = 'GOOD';

--turf the good records so we can focus on the rest -- 16319 
DELETE FROM admin_bdys.temp_hole_localities
  WHERE gid IN (SELECT gid FROM admin_bdys.temp_holes_distinct WHERE locality_pid IS NOT NULL);


-- split remaining locality/state border holes at the point where 2 localities meet the hole and add to working localities table

-- get locality polygon points along shared edges of remaining holes -- 13815    
DROP TABLE IF EXISTS admin_bdys.temp_hole_points_temp;
SELECT DISTINCT *
  INTO admin_bdys.temp_hole_points_temp
  FROM (
    SELECT loc.locality_pid,
           ste.gid,
           ste.state,
           (ST_DumpPoints(ST_Intersection(loc.geom, ste.geom))).geom::geometry(Point, 4283) AS geom
      FROM admin_bdys.temp_split_localities AS loc
      INNER JOIN admin_bdys.temp_holes_distinct AS ste ON (ST_Touches(loc.geom, ste.geom) AND loc.loc_state = ste.state)
      INNER JOIN admin_bdys.temp_hole_localities AS hol ON ste.gid = hol.gid
) AS sqt;


-- get unique points - 264
DROP TABLE IF EXISTS admin_bdys.temp_hole_points;
CREATE TABLE admin_bdys.temp_hole_points
(
  gid serial NOT NULL PRIMARY KEY,
  state_gid integer NOT NULL,
  state character varying(3) NOT NULL,
  geom geometry(Point,4283) NOT NULL
) WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.temp_hole_points OWNER TO postgres;

INSERT INTO admin_bdys.temp_hole_points (state_gid, state, geom) -- 
SELECT gid, state, geom
    FROM (
    SELECT Count(*) AS cnt, gid, state, geom FROM admin_bdys.temp_hole_points_temp GROUP BY gid, state, geom
  ) AS sqt
  WHERE sqt.cnt > 1;


-- get points shared between 2 localities to the state border (to be used to split the remaining holes)
DROP TABLE IF EXISTS admin_bdys.temp_line_points; -- 1624     
SELECT DISTINCT pnt.gid,
       pnt.state_gid,
       pnt.state,
       pnt.geom AS geomA,
       ST_ClosestPoint(ST_Boundary(ste.geom), pnt.geom) AS geomB
       --ST_ClosestPoint(ste.geom, pnt.geom) AS geomB
  INTO admin_bdys.temp_line_points
  FROM admin_bdys.temp_hole_points AS pnt
  INNER JOIN admin_bdys.temp_sa4_state_borders AS ste ON pnt.state = ste.state;

-- calc values for extending a line beyond the 2 points were interested in
DROP TABLE IF EXISTS admin_bdys.temp_line_calcs; -- 1624     
SELECT gid,
       state_gid,
       state,
       geomA AS geom,
       ST_Azimuth(geomA, geomB) AS azimuth,
       ST_Distance(geomA, geomB) + 0.00001 AS dist
  INTO admin_bdys.temp_line_calcs
  FROM admin_bdys.temp_line_points;

-- get lines from points shared between 2 localities to the state border (to be used to split the remaining holes)
DROP TABLE IF EXISTS admin_bdys.temp_hole_lines; -- 1624     
SELECT DISTINCT pnt.gid,
       pnt.state_gid,
       pnt.state,
       pnt.dist,
       ST_MakeLine(pnt.geom, ST_Translate(pnt.geom, sin(azimuth) * pnt.dist, cos(azimuth) * pnt.dist))::geometry(Linestring, 4283) AS geom
  INTO admin_bdys.temp_hole_lines
  FROM admin_bdys.temp_line_calcs AS pnt
  INNER JOIN admin_bdys.temp_sa4_state_borders AS ste ON pnt.state = ste.state;


-- get the shortest splitter lines -- 187 -- 390
DROP TABLE IF EXISTS admin_bdys.temp_hole_splitter_lines;
SELECT ste.state_gid,
       ste.state,
       ST_Multi(ST_Union(ste.geom))::geometry(MultiLinestring, 4283) AS geom
  INTO admin_bdys.temp_hole_splitter_lines
  FROM (
    SELECT gid, state, MIN(dist) AS dist FROM admin_bdys.temp_hole_lines GROUP BY gid, state
  ) AS sqt
  INNER JOIN admin_bdys.temp_hole_lines AS ste ON (sqt.gid = ste.gid AND sqt.dist = ste.dist)
  INNER JOIN admin_bdys.temp_holes_distinct AS hol ON ST_Intersects(ste.geom, hol.geom)
  GROUP BY ste.state_gid,
       ste.state;

-- manual fix for NT/QLD border issue
INSERT INTO admin_bdys.temp_hole_splitter_lines
SELECT (SELECT gid FROM admin_bdys.temp_holes_distinct WHERE ST_Intersects(St_SetSRID(ST_MakePoint(137.999, -17.600), 4283), geom)),
       'NT',
       ST_Multi(ST_GeomFromText('LINESTRING(137.99519933848674214 -17.6113710627822293, 138.00147236831551822 -17.61135804369208557)', 4283));


-- spit the remaining holes -- 2 mins -- 403
DROP TABLE IF EXISTS admin_bdys.temp_holes_split;
CREATE TABLE admin_bdys.temp_holes_split
(
  gid serial NOT NULL PRIMARY KEY,
  state_gid integer NOT NULL,
  locality_pid character varying(16) NULL,
  state character varying(3) NOT NULL,
  type varchar(50) NOT NULL,
  geom geometry(Polygon,4283) NOT NULL
) WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.temp_holes_split OWNER TO postgres;

INSERT INTO admin_bdys.temp_holes_split (state_gid, state, type, geom)
SELECT hol.gid,
       hol.state,
       'SPLIT',
       (ST_Dump(ST_SplitPolygon(hol.gid, hol.geom, lne.geom))).geom::geometry(Polygon, 4283) AS geom
  FROM admin_bdys.temp_hole_splitter_lines AS lne
  INNER JOIN admin_bdys.temp_holes_distinct AS hol
  ON (ST_Intersects(hol.geom, lne.geom) AND hol.state = lne.state)
  WHERE hol.locality_pid IS NULL;

-- didn't split right
-- NOTICE:  NOT ENOUGH POLYGONS! : gid 1128 : blades 2 : num output polys 2
-- NOTICE:  NOT ENOUGH POLYGONS! : gid 1135 : blades 1 : num output polys 1
-- NOTICE:  NOT ENOUGH POLYGONS! : gid 1138 : blades 1 : num output polys 1
-- NOTICE:  NOT ENOUGH POLYGONS! : gid 1139 : blades 1 : num output polys 1
-- NOTICE:  NOT ENOUGH POLYGONS! : gid 1155 : blades 1 : num output polys 1
-- NOTICE:  NOT ENOUGH POLYGONS! : gid 1169 : blades 3 : num output polys 2
-- NOTICE:  NOT ENOUGH POLYGONS! : gid 3230 : blades 3 : num output polys 1
-- NOTICE:  NOT ENOUGH POLYGONS! : gid 4288 : blades 2 : num output polys 1
-- NOTICE:  NOT ENOUGH POLYGONS! : gid 10945 : blades 1 : num output polys 1
-- NOTICE:  NOT ENOUGH POLYGONS! : gid 16286 : blades 1 : num output polys 1
-- NOTICE:  NOT ENOUGH POLYGONS! : gid 16503 : blades 3 : num output polys 2

-- insert unsplit polygons





-- assign fixed holes to localities -- 407
DROP TABLE IF EXISTS admin_bdys.temp_holes_split_locs;
SELECT hol.gid,
       loc.locality_pid,
       hol.state,
       MAX(ST_Length(ST_Intersection(hol.geom, loc.geom))) AS dist
--       hol.geom
  INTO admin_bdys.temp_holes_split_locs
  FROM admin_bdys.temp_holes_split AS hol
  INNER JOIN admin_bdys.temp_split_localities AS loc
  ON (ST_Touches(hol.geom, loc.geom) AND hol.state = loc.loc_state)
  WHERE ST_Length(ST_Intersection(hol.geom, loc.geom)) > 0
  GROUP BY hol.gid,
       loc.locality_pid,
       hol.state
  ORDER BY gid;


-- get the locality pids with the most frontage to the split holes -- 393
UPDATE admin_bdys.temp_holes_split as spl
  SET locality_pid = hol.locality_pid
  FROM (
    SELECT gid, MIN(dist) AS dist FROM admin_bdys.temp_holes_split_locs GROUP BY gid
  ) AS sqt,
  admin_bdys.temp_holes_split_locs AS hol
  WHERE spl.gid = sqt.gid
  AND (sqt.gid = hol.gid AND sqt.dist = hol.dist);

-- manual fix for NT/QLD border issue
UPDATE admin_bdys.temp_holes_split as spl
  SET locality_pid = 'NT212'
  WHERE ST_Intersects(St_SetSRID(ST_MakePoint(137.999, -17.630), 4283), geom);

DROP TABLE IF EXISTS admin_bdys.temp_holes_split_locs;

--select * from admin_bdys.temp_holes_split where locality_pid IS NULL;
-- gid IN (55,56,113,179,234,299,328,356)

-- Add good holes to split localities -- 393
INSERT INTO admin_bdys.temp_split_localities (gid, locality_pid, loc_state, ste_state, match_type, geom)
SELECT 900000000 + gid,
       locality_pid,
       state AS loc_state,
       state AS ste_state,
       'MESSY BORDER' AS match_type, 
       geom
  FROM admin_bdys.temp_holes_split
  WHERE locality_pid IS NOT NULL;






-- update locality polygons that have a manual fix point on them -- 159
UPDATE admin_bdys.temp_split_localities AS loc
  SET match_type = 'MANUAL'
  FROM admin_bdys.temp_messy_centroids AS pnt
  WHERE (ST_Within(pnt.geom, loc.geom) OR loc.locality_pid = 'ACT912')
  AND loc.match_type = 'SPLIT';






--merge the results into a single table
DROP TABLE IF EXISTS admin_bdys.temp_sqt;
SELECT locality_pid,
       ST_Multi(ST_Union(geom)) AS geom
  INTO admin_bdys.temp_sqt
  FROM admin_bdys.temp_split_localities
  WHERE match_type <> 'SPLIT'
  GROUP BY locality_pid;

DROP TABLE IF EXISTS admin_bdys.temp_final_localities;
CREATE TABLE admin_bdys.temp_final_localities (
  locality_pid character varying(16),
  geom geometry(Polygon, 4283),
  area numeric(20,3)
) WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.temp_final_localities OWNER TO postgres;

INSERT INTO admin_bdys.temp_final_localities (locality_pid, geom)
SELECT locality_pid,
       ST_Buffer((ST_Dump(geom)).geom, 0.0)
  FROM admin_bdys.temp_sqt;

DROP TABLE IF EXISTS admin_bdys.temp_sqt;

-- get areas
UPDATE admin_bdys.temp_final_localities
  SET area = (ST_Area(ST_Transform(geom, 3577)) / 1000000)::numeric(20,3);


--select * from admin_bdys.temp_final_localities where NOT ST_IsValid(geom); -- 31


-- simplify and clean up data, removing unwanted artifacts and small islands along the way! -- 8 mins -- 17725
DROP TABLE IF EXISTS admin_bdys.temp_final_localities2;
CREATE TABLE admin_bdys.temp_final_localities2 (
  locality_pid character varying(16),
  geom geometry
) WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.temp_final_localities2 OWNER TO postgres;

INSERT INTO admin_bdys.temp_final_localities2 (locality_pid, geom)
SELECT locality_pid,
       (ST_Dump(ST_MakeValid(ST_Multi(ST_SnapToGrid(ST_Simplify(ST_Buffer(ST_Union(ST_Buffer(geom, 0.0000001, 1)), -0.0000001, 1), 0.00002), 0.00001))))).geom
  FROM admin_bdys.temp_final_localities
  WHERE area > 0.05 OR locality_pid IN ('SA514', 'SA1015', 'SA1553', 'WA1705') --  preserve these locality polygons
  GROUP BY locality_pid;

DELETE FROM admin_bdys.temp_final_localities2 WHERE ST_GeometryType(geom) <> 'ST_Polygon'; -- 7

-- select ST_GeometryType(geom), * from admin_bdys.temp_final_localities2 where ST_GeometryType(geom) <> 'ST_Polygon'; -- 11
-- select * from admin_bdys.temp_final_localities2 where NOT ST_IsValid(geom); -- 0


-- insert grouped polygons into final table
DROP TABLE IF EXISTS admin_bdys.locality_boundaries_display;
CREATE TABLE admin_bdys.locality_boundaries_display
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
  CONSTRAINT locality_boundaries_display_pk PRIMARY KEY (locality_pid)
) WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.locality_boundaries_display OWNER TO postgres;
CREATE INDEX locality_boundaries_display_geom_idx ON admin_bdys.locality_boundaries_display USING gist (geom);
ALTER TABLE admin_bdys.locality_boundaries_display CLUSTER ON locality_boundaries_display_geom_idx;

INSERT INTO admin_bdys.locality_boundaries_display(locality_pid, locality_name, postcode, state, locality_class, address_count, street_count, geom) -- 15559
SELECT loc.locality_pid,
       loc.locality_name,
       loc.postcode,
       loc.state,
       loc.locality_class,
       loc.address_count,
       loc.street_count,
       bdy.geom
  FROM admin_bdys.locality_boundaries AS loc
  INNER JOIN (
    SELECT locality_pid,
           ST_Multi(ST_Union(geom)) AS geom
      FROM admin_bdys.temp_final_localities2
      GROUP by locality_pid
  ) AS bdy
  ON loc.locality_pid = bdy.locality_pid;

ANALYZE admin_bdys.locality_boundaries_display;

select * from admin_bdys.locality_boundaries_display where NOT ST_IsValid(geom); -- 0

-- select * from admin_bdys.locality_boundaries_display where ST_IsEmpty(geom); -- 0
 
-- -- QA - What's been lost?
-- SELECT *
--   FROM admin_bdys.locality_boundaries AS loc
--   LEFT OUTER JOIN admin_bdys.locality_boundaries_display AS bdy
--   ON loc.locality_pid = bdy.locality_pid
--   WHERE bdy.locality_pid IS NULL
--   ORDER BY loc.state,
--            loc.locality_name,
--            loc.postcode;

-- -- 'NSW524','BOTANY BAY','2019','NSW','GAZETTED LOCALITY',1,12
-- -- 'NSW2046','JERVIS BAY','<NULL>','NSW','GAZETTED LOCALITY',0,5
-- -- 'NSW2275','LAKE MACQUARIE','<NULL>','NSW','GAZETTED LOCALITY',1,67
-- -- 'NSW2627','MIDDLE HARBOUR','2087','NSW','GAZETTED LOCALITY',3,22
-- -- 'NSW3019','NORTH HARBOUR','<NULL>','NSW','GAZETTED LOCALITY',0,11
-- -- 'NSW3255','PITTWATER','2108','NSW','GAZETTED LOCALITY',5,31
-- -- 'NT26','BEAGLE GULF','<NULL>','NT','GAZETTED LOCALITY',0,0
-- -- 'NT75','DARWIN HARBOUR','<NULL>','NT','GAZETTED LOCALITY',0,0
-- -- 'QLD1351','HERVEY BAY','<NULL>','QLD','GAZETTED LOCALITY',0,2

 

