
-- merge locality polygons --  mins --
DROP TABLE IF EXISTS admin_bdys_201708.postcode_bdys_display_full_res CASCADE;
CREATE TABLE admin_bdys_201708.postcode_bdys_display_full_res (
	gid serial PRIMARY KEY,
  postcode character(4),
  state text NOT NULL,
  geom geometry(MultiPolygon, 4283),
  area numeric(20,3)
) WITH (OIDS=FALSE);
ALTER TABLE admin_bdys_201708.postcode_bdys_display_full_res OWNER TO postgres;

INSERT INTO admin_bdys_201708.postcode_bdys_display_full_res (postcode, state, geom)
SELECT postcode,
       state,
       ST_Multi(ST_Buffer(ST_Buffer(ST_Union(ST_MakeValid(geom)), -0.00000001), 0.00000001))
  FROM admin_bdys_201708.locality_bdys_display_full_res
  GROUP BY postcode,
    state;

CREATE INDEX postcode_bdys_display_full_res_geom_idx ON admin_bdys_201708.postcode_bdys_display_full_res USING gist (geom);
ALTER TABLE admin_bdys_201708.postcode_bdys_display_full_res CLUSTER ON postcode_bdys_display_full_res_geom_idx;

ANALYZE admin_bdys_201708.postcode_bdys_display_full_res;


 -- simplify and clean up data, removing unwanted artifacts -- 1 min -- 17731  -- OLD METHOD
 DROP TABLE IF EXISTS admin_bdys.temp_final_postcodes;
 CREATE TABLE admin_bdys.temp_final_postcodes (
   postcode character(4),
   state text NOT NULL,
   geom geometry
 ) WITH (OIDS=FALSE);
 ALTER TABLE admin_bdys.temp_final_postcodes OWNER TO postgres;

 INSERT INTO admin_bdys.temp_final_postcodes (postcode, state, geom)
 SELECT postcode,
        state,
        (ST_Dump(ST_MakeValid(ST_Multi(ST_SnapToGrid(ST_SimplifyVW(geom, 9.208633852887194e-09), 0.00001))))).geom
   FROM admin_bdys_201708.postcode_bdys_display_full_res;

 DELETE FROM admin_bdys.temp_final_postcodes WHERE ST_GeometryType(geom) <> 'ST_Polygon'; -- 20


 -- insert grouped polygons into final table -- OLD METHOD
 DROP TABLE IF EXISTS admin_bdys_201708.postcode_bdys_display CASCADE;
 CREATE TABLE admin_bdys_201708.postcode_bdys_display
 (
   gid serial PRIMARY KEY,
   postcode character(4) NULL,
   state text NOT NULL,
   address_count integer NOT NULL,
   street_count integer NOT NULL,
   geom geometry(MultiPolygon,4283) NOT NULL
 ) WITH (OIDS=FALSE);
 ALTER TABLE admin_bdys_201708.postcode_bdys_display
   OWNER TO postgres;

-- ALTER TABLE admin_bdys_201708.postcode_bdys_display
--   OWNER TO rw;
-- GRANT ALL ON TABLE admin_bdys_201708.postcode_bdys_display TO rw;
-- GRANT SELECT ON TABLE admin_bdys_201708.postcode_bdys_display TO readonly;
-- GRANT SELECT ON TABLE admin_bdys_201708.postcode_bdys_display TO metacentre;
-- GRANT SELECT ON TABLE admin_bdys_201708.postcode_bdys_display TO ro;
-- GRANT ALL ON TABLE admin_bdys_201708.postcode_bdys_display TO update;


 INSERT INTO admin_bdys_201708.postcode_bdys_display(postcode, state, address_count, street_count, geom) -- 15565
 SELECT postcode,
        state,
        SUM(address_count),
        SUM(street_count),
        ST_Multi(ST_MakeValid(ST_Union(ST_MakeValid(ST_Buffer(geom, 0.000001))))) AS geom
--         ST_Multi(ST_MakeValid(ST_MakePolygon(ST_Boundary(ST_Union(ST_MakeValid(ST_Buffer(geom, 0.000001))))))) AS geom
   FROM admin_bdys_201708.locality_bdys_display AS loc
   WHERE postcode IS NOT NULL
   AND postcode <> 'NA'
	 GROUP by postcode,
		 state;

 CREATE INDEX postcode_bdys_display_geom_idx ON admin_bdys_201708.postcode_bdys_display USING gist (geom);
 ALTER TABLE admin_bdys_201708.postcode_bdys_display CLUSTER ON postcode_bdys_display_geom_idx;

 ANALYZE admin_bdys_201708.postcode_bdys_display;
-- 
-- WITH polygons AS (
-- 
-- )
-- 
-- 
-- ST_MakePolygon(ST_Boundary(


-- step 1 - merge localities into postcode and remove all slivers and islands (polygon islands that is, not Great Keppel Island)
DROP TABLE IF EXISTS admin_bdys_201708.test;
SELECT postcode,
       state,
       SUM(address_count) AS address_count,
       SUM(street_count) AS street_count,
       ST_MakePolygon(ST_ExteriorRing((ST_Dump(ST_MakeValid(ST_Union(ST_MakeValid(ST_Buffer(geom, 0.000001)))))).geom)) AS geom
	 INTO admin_bdys_201708.test
   FROM admin_bdys_201708.locality_bdys_display AS loc
   WHERE postcode IS NOT NULL
   AND postcode <> 'NA'
	 GROUP by postcode,
		 state;

-- step 2 remove areas within polygon covered by different postcodes (e.g. QLD 4712 is within QLD 4702)
DROP TABLE IF EXISTS admin_bdys_201708.test2;
SELECT ST_Multi(ST_Union(loc2.geom)) AS geom
	 INTO admin_bdys_201708.test2
   FROM admin_bdys_201708.test AS loc1
   INNER JOIN admin_bdys_201708.test AS loc2
   ON ST_Contains(loc1.geom, loc2.geom)
   AND loc1.postcode <> loc2.postcode
--    AND loc1.state <> loc2.state


-- WON'T WORK - too random!
-- step 3 - assign postcodes to NULL postcode loaclities based on the highest number of bordering localities with that postcode


-- step 3 add NULL postcode localites.




select Count(*) from admin_bdys_201708.postcode_bdys_display;


--  INSERT INTO admin_bdys_201708.postcode_bdys_display(postcode, state, address_count, street_count, geom) -- 15565
--  SELECT loc.postcode,
--         loc.state,
--         SUM(loc.address_count),
--         SUM(loc.street_count),
--         bdy.geom
--    FROM admin_bdys_201708.postcode_bdys AS loc
--    INNER JOIN (
--      SELECT postcode,
-- 						state,
--             ST_Multi(ST_Union(geom)) AS geom
--        FROM admin_bdys_201708.postcode_bdys_display
--        GROUP by postcode,
-- 			   state
--    ) AS bdy
--    ON loc.locality_pid = bdy.locality_pid;
-- 
--  CREATE INDEX localities_display_geom_idx ON admin_bdys_201708.postcode_bdys_display USING gist (geom);
--  ALTER TABLE admin_bdys_201708.postcode_bdys_display CLUSTER ON localities_display_geom_idx;
-- 
--  ANALYZE admin_bdys_201708.postcode_bdys_display;