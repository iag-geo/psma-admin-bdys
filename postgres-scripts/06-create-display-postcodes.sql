
-- step 1 - merge localities into postcode and remove all slivers and islands (polygon islands that is, not Great Keppel Island)
DROP TABLE IF EXISTS admin_bdys.temp_postcodes;
SELECT postcode,
       state,
       ST_MakePolygon(ST_ExteriorRing((ST_Dump(ST_MakeValid(ST_Union(ST_MakeValid(ST_Buffer(geom, 0.000001)))))).geom)) AS geom
	 INTO admin_bdys.temp_postcodes
   FROM admin_bdys.locality_bdys_display AS loc
   WHERE postcode IS NOT NULL
   AND postcode NOT IN ('NA', '9999')
	 GROUP by postcode,
		 state;

ANALYZE admin_bdys.temp_postcodes;


-- step 2 - get all postcodes within other postcodes
DROP TABLE IF EXISTS admin_bdys.temp_postcode_cookies;
SELECT loc1.postcode,
       ST_Multi(ST_Union(loc2.geom)) as geom
	 INTO admin_bdys.temp_postcode_cookies
   FROM admin_bdys.temp_postcodes AS loc1
   INNER JOIN admin_bdys.temp_postcodes AS loc2
   ON ST_Contains(loc1.geom, loc2.geom)
   AND loc1.postcode <> loc2.postcode
   GROUP BY loc1.postcode;

ANALYZE admin_bdys.temp_postcode_cookies;


-- step 3 - remove areas within postcodes covered by different postcodes (e.g. QLD 4712 is within QLD 4702)
UPDATE admin_bdys.temp_postcodes AS pc
	SET geom = ST_Difference(pc.geom, ck.geom)
	FROM admin_bdys.temp_postcode_cookies AS ck
  WHERE ST_Intersects(pc.geom, ck.geom)
  AND pc.postcode = ck.postcode;


-- step 4 - create merged NULLS
DROP TABLE IF EXISTS admin_bdys.temp_null_postcodes;
SELECT state,
--        SUM(address_count) AS address_count,
--        SUM(street_count) AS street_count,
       ST_MakePolygon(ST_ExteriorRing((ST_Dump(ST_MakeValid(ST_Union(ST_MakeValid(ST_Buffer(geom, 0.000001)))))).geom)) AS geom
	 INTO admin_bdys.temp_null_postcodes
   FROM admin_bdys.locality_bdys_display AS loc
   WHERE postcode IS NULL
   OR postcode IN ('NA', '9999')
	 GROUP BY state;

ANALYZE admin_bdys.temp_null_postcodes;


-- step 5 - get all postcodes within NULL areas
DROP TABLE IF EXISTS admin_bdys.temp_null_postcode_cookies;
SELECT loc2.state,
       ST_Multi(ST_Union(loc1.geom)) as geom
	 INTO admin_bdys.temp_null_postcode_cookies
   FROM admin_bdys.temp_postcodes AS loc1
   INNER JOIN admin_bdys.temp_null_postcodes AS loc2
   ON ST_Within(loc1.geom, loc2.geom)
   GROUP BY loc2.state;

ANALYZE admin_bdys.temp_null_postcode_cookies;


-- step 6 - remove areas within NULL areas covered by postcodes
UPDATE admin_bdys.temp_null_postcodes AS pc
	SET geom = ST_Difference(pc.geom, ck.geom)
	FROM admin_bdys.temp_null_postcode_cookies AS ck
  WHERE ST_Intersects(pc.geom, ck.geom);


-- step 7 - remove NULL areas within postcodes
DELETE FROM admin_bdys.temp_null_postcodes AS nl
  USING admin_bdys.temp_postcodes AS pc
  WHERE ST_Contains(pc.geom, nl.geom);


-- step 8 insert into one table and remove unwanted artifacts
DROP TABLE IF EXISTS admin_bdys.temp_final_postcodes;
CREATE TABLE admin_bdys.temp_final_postcodes (
  postcode character(4) NULL,
  state text NOT NULL,
  geom geometry
) WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.temp_final_postcodes OWNER TO postgres;

INSERT INTO admin_bdys.temp_final_postcodes (postcode, state, geom)
SELECT postcode,
  state,
  (ST_Dump(ST_MakeValid(ST_Multi(geom)))).geom AS geom
FROM admin_bdys.temp_postcodes;

INSERT INTO admin_bdys.temp_final_postcodes (postcode, state, geom)
  SELECT NULL,
    state,
    (ST_Dump(ST_MakeValid(ST_Multi(geom)))).geom AS geom
  FROM admin_bdys.temp_null_postcodes;

DELETE FROM admin_bdys.temp_final_postcodes WHERE ST_GeometryType(geom) <> 'ST_Polygon'; -- 20


-- step 9 - insert grouped polygons into final table --
DROP TABLE IF EXISTS admin_bdys.postcode_bdys_display;
CREATE TABLE admin_bdys.postcode_bdys_display
(
  gid serial PRIMARY KEY,
  postcode text NULL,
  state text NOT NULL,
  geom geometry(MultiPolygon,{0}) NOT NULL
) WITH (OIDS=FALSE);
ALTER TABLE admin_bdys.postcode_bdys_display
  OWNER TO postgres;

INSERT INTO admin_bdys.postcode_bdys_display(postcode, state, geom) -- 15565
SELECT postcode,
       state,
       ST_Multi(ST_Union(geom)) AS geom
  FROM admin_bdys.temp_final_postcodes
  WHERE postcode IS NOT NULL
  AND postcode NOT IN ('NA', '9999')
	GROUP by postcode,
		state;

-- insert NULL postcode areas, ungrouped
INSERT INTO admin_bdys.postcode_bdys_display(state, geom) -- 15565
SELECT state,
       ST_Multi(geom) AS geoms
  FROM admin_bdys.temp_final_postcodes
  WHERE postcode IS NULL
  OR postcode IN ('NA', '9999');

CREATE INDEX postcode_bdys_display_geom_idx ON admin_bdys.postcode_bdys_display USING gist (geom);
ALTER TABLE admin_bdys.postcode_bdys_display CLUSTER ON postcode_bdys_display_geom_idx;

ANALYZE admin_bdys.postcode_bdys_display;

--select Count(*) from admin_bdys.postcode_bdys_display;


-- clean up temp tables
DROP TABLE IF EXISTS admin_bdys.temp_postcodes;
DROP TABLE IF EXISTS admin_bdys.temp_postcode_cookies;
DROP TABLE IF EXISTS admin_bdys.temp_null_postcodes;
DROP TABLE IF EXISTS admin_bdys.temp_null_postcode_cookies;
DROP TABLE IF EXISTS admin_bdys.temp_final_postcodes;
