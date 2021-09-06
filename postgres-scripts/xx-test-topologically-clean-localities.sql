
-- remove repeated points so you can focus on more serious issues
DROP TABLE IF EXISTS testing.locality_bdys_display;
CREATE TABLE testing.locality_bdys_display AS
  SELECT locality_pid, ST_RemoveRepeatedPoints(geom) AS geom FROM admin_bdys_202108.locality_bdys_display;

ANALYSE testing.locality_bdys_display;


-- look for duplicate coordinates in each polygon that aren't the first or last coordinate -- 26 rows
-- FYI - the first and last coords are always duplicated in a polygon
WITH polys AS (
	SELECT locality_pid,
				 (ST_Dump(geom)).geom AS geom
	FROM testing.locality_bdys_display
), dumps AS (
	SELECT locality_pid,
				 ST_Dumppoints(geom) AS point_dump
	FROM polys
), points AS (
	SELECT locality_pid,
				 (point_dump).path[1] AS ring_seq,
				 (point_dump).path[2] AS point_seq,
				 (point_dump).geom    AS geom
	FROM dumps
), coords AS (
	SELECT locality_pid,
				 ring_seq,
				 point_seq,
	       MAX(point_seq) OVER (PARTITION BY locality_pid, ring_seq) AS max_point_seq,
				 ST_Y(geom)::numeric(7, 5) AS latitude,
				 ST_X(geom)::numeric(8, 5) AS longitude
	FROM points
), filter AS (
	SELECT locality_pid,
				 ring_seq,
				 point_seq,
				 max_point_seq,
	       longitude,
				 latitude
  FROM coords
	WHERE point_seq > 1
    AND point_seq < max_point_seq
), dupes AS (
	SELECT locality_pid,
				 ring_seq,
	       longitude,
				 latitude,
				 Count(*) as cnt
	FROM filter
	GROUP BY locality_pid,
					 ring_seq,
	         longitude,
					 latitude
)
SELECT * FROM dupes WHERE cnt > 1
;


-- locality_pid	longitude	latitude
-- WA2051	117.98133, -34.98818

-- get duplicate point sequence numbers
WITH polys AS (
	SELECT locality_pid,
				 (ST_Dump(geom)).geom AS geom
	FROM testing.locality_bdys_display
  WHERE locality_pid = 'WA2051'
), dumps AS (
	SELECT locality_pid,
				 ST_Dumppoints(geom) AS point_dump
	FROM polys
), points AS (
	SELECT locality_pid,
				 (point_dump).path[1] AS ring_seq,
				 (point_dump).path[2] AS point_seq,
				 (point_dump).geom    AS geom
	FROM dumps
), coords AS (
	SELECT locality_pid,
				 ring_seq,
				 point_seq,
				 ST_Y(geom)::numeric(7, 5) AS latitude,
				 ST_X(geom)::numeric(8, 5) AS longitude
	FROM points
)
SELECT ring_seq, point_seq, locality_pid, longitude, latitude
FROM coords
WHERE longitude = 117.98038
  AND latitude = -34.98834
;



-- look at duplicated points by creating linestrings
DROP TABLE IF EXISTS testing.locality_bdys_display_lines;
CREATE TABLE testing.locality_bdys_display_lines AS
WITH points AS (
	SELECT locality_pid,
				 (ST_Dump(ST_Points(geom))).geom  AS geom
	FROM admin_bdys_202108.locality_bdys_display
  WHERE locality_pid = 'ACT110'
), coords AS (
	SELECT row_number() OVER (PARTITION BY locality_pid) AS point_seq,
	       locality_pid,
	       ST_Y(geom)::numeric(7, 5) AS latitude,
	       ST_X(geom)::numeric(8, 5) AS longitude,
	       geom
	FROM points
), part1 AS (
  SELECT 1 AS line_num,
         locality_pid,
         ST_Makeline(geom order by point_seq)
  FROM coords
  WHERE point_seq < 81
  GROUP BY locality_pid
), part2 AS (
	SELECT 1 AS line_num,
				 locality_pid,
				 ST_Makeline(geom order by point_seq)
	FROM coords
	WHERE point_seq >= 81
	GROUP BY locality_pid
)
SELECT * FROM part1
UNION ALL
SELECT * FROM part2
;

ANALYSE testing.locality_bdys_display_lines;



select postgis_version();


-- Total points
SELECT SUM(ST_NPoints(geom)) FROM admin_bdys_202108.locality_bdys;         -- 12,938,094
SELECT SUM(ST_NPoints(geom)) FROM admin_bdys_202108.locality_bdys_display; --  4,392,196 (66% reduction)


-- nothing below here works....

-- 
-- 
-- CREATE INDEX temp_final_localities_geom_idx ON admin_bdys.temp_final_localities USING gist (geom);
-- ALTER TABLE admin_bdys.temp_final_localities CLUSTER ON temp_final_localities_geom_idx;
-- 
-- 
-- 
-- -- create topologicaly correct 
-- 
-- with poly as (
--         select locality_pid, (st_dump(geom)).* 
--         from admin_bdys.temp_final_localities
-- ) select d.locality_pid, baz.geom 
--  from ( 
--         select (st_dump(st_polygonize(distinct geom))).geom as geom
--         from (
--                 select (st_dump(st_simplifyPreserveTopology(st_linemerge(st_union(geom)), 0.0001))).geom as geom
--                 from (
--                         select st_exteriorRing((st_dumpRings(geom)).geom) as geom
--                         from poly
--                 ) as foo
--         ) as bar
-- ) as baz,
-- poly d
-- where st_intersects(d.geom, baz.geom)
-- and st_area(st_intersection(d.geom, baz.geom))/st_area(baz.geom) > 0.5
-- and left(d.locality_pid, 3) = 'ACT';
-- 
-- 
-- 
-- 
-- 
-- --simplifyLayerPreserveTopology (schemaname text, tablename text, idcol text, geom_col text, tolerance float)
-- 
-- select simplifyLayerPreserveTopology ('admin_bdys', 'temp_final_localities', 'locality_pid', 'geom', 0.0001) 
--  from admin_bdys.temp_final_localities
--  where left(locality_pid, 3) = 'ACT';
-- 
-- 
-- 
--  
-- 
-- -- simplify and clean up data, removing unwanted artifacts -- 1 min -- 17751 
-- DROP TABLE IF EXISTS admin_bdys.temp_final_localities_topo_test;
-- CREATE TABLE admin_bdys.temp_final_localities_topo_test (
--   locality_pid character varying(16),
--   geom geometry
-- ) WITH (OIDS=FALSE);
-- ALTER TABLE admin_bdys.temp_final_localities_topo_test OWNER TO postgres;
-- 
-- INSERT INTO admin_bdys.temp_final_localities_topo_test (locality_pid, geom)
-- SELECT locality_pid,
--        (ST_Dump(ST_MakeValid(ST_Multi(ST_SnapToGrid(ST_SimplifyVW(geom, 0.000000003), 0.00001))))).geom
--   FROM admin_bdys.temp_final_localities;
--   --WHERE area > 0.05 OR locality_pid IN ('SA514', 'SA1015', 'SA1553', 'WA1705') --  preserve these locality polygons
-- 
-- 
-- DELETE FROM admin_bdys.temp_final_localities_topo_test WHERE ST_GeometryType(geom) <> 'ST_Polygon'; -- 38
-- 
-- 
-- 
-- 
-- 
-- 
