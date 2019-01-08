
-- look for duplicates coordinates in the same record
WITH polys AS (
	SELECT row_number() OVER () AS gid, locality_pid, (ST_Dump(geom)).geom AS geom FROM admin_bdys_201811.locality_bdys_display
-- ), fixes AS (
-- 	SELECT gid, locality_pid, ST_MakeValid(ST_Buffer(geom, 0.0)) AS geom FROM polys
), points AS (
	SELECT gid, locality_pid, (ST_Dump(ST_Points(geom))).geom AS geom FROM polys
), coords AS (
	SELECT gid, locality_pid, ST_Y(geom)::numeric(7, 5) AS latitude, ST_X(geom)::numeric(8, 5) AS longitude FROM points
), dupes AS (
	SELECT gid,
	       locality_pid,
				 longitude,
				 latitude,
	       Count(*) as cnt
	FROM coords
	GROUP BY gid,
	         locality_pid,
					 longitude,
					 latitude
)
SELECT * FROM dupes WHERE cnt > 1 -- 18079
;


-- Total points
SELECT SUM(ST_NPoints(geom)) FROM admin_bdys_201811.locality_bdys;         -- 12,938,094
SELECT SUM(ST_NPoints(geom)) FROM admin_bdys_201811.locality_bdys_display; --  4,392,196


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
