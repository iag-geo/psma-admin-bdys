
-- 
-- -- Get rid of the duplicates (caused by using state border lines that are split every 512 coords) -- 10700
-- INSERT INTO admin_bdys.temp_split_localities
-- SELECT DISTINCT * FROM admin_bdys.temp_split_localities_dupes;
-- 
-- --Fix Jervis Bay issue
-- UPDATE admin_bdys.temp_split_localities SET ste_state = 'OT'
--   WHERE locality_pid = 'OT4'
--   AND ste_state = 'NSW'
--   AND ST_Intersects(ST_SetSRID(ST_MakePoint(150.73105005, -35.1263496779), 4283), geom);

-- delete split locality polygons that are on the wrong side of a state border
DELETE FROM admin_bdys.temp_split_localities-- 235829
  WHERE loc_state <> ste_state;
--  AND locality_pid <> 'QLD2193'; -- special case -- taking this out ruins the Gulf QLD/NT border by 700m+


-- insert non-border/coastline localities into working table -- 13583
INSERT INTO admin_bdys.temp_split_localities (gid, locality_pid, loc_state, ste_state, match_type, geom)
SELECT gid,
       locality_pid,
       state AS loc_state,
       state AS ste_state,
       'GOOD' AS match_type, 
       geom
  FROM admin_bdys.temp_localities
  WHERE gid NOT IN (SELECT gid FROM admin_bdys.temp_split_localities);


-- update match_type for localities where state polygon is assigned to one locality only -- 3410 
UPDATE admin_bdys.temp_split_localities AS loc
  SET match_type = 'SINGLE'
  FROM (
    SELECT Count(*) AS cnt, state_gid FROM (
      SELECT DISTINCT locality_pid, state_gid
        FROM admin_bdys.temp_split_localities
      ) AS sqt
      GROUP BY state_gid
    ) AS sqt2
    WHERE sqt2.state_gid = loc.state_gid
    AND loc.match_type <> 'GOOD'
    AND sqt2.cnt = 1;


-- create table of locality polygon centroids -- 2043 
DROP TABLE IF EXISTS admin_bdys.temp_locality_centroid;
SELECT gid,
       locality_pid,
       ST_PointOnSurface(geom)::geometry(Point, 4283) AS geom
  INTO admin_bdys.temp_locality_centroid
  FROM admin_bdys.temp_localities
  WHERE gid IN (SELECT gid FROM admin_bdys.temp_split_localities WHERE match_type = 'SPLIT');

CREATE INDEX temp_locality_centroid_geom_idx ON admin_bdys.temp_locality_centroid USING gist (geom);
ALTER TABLE admin_bdys.temp_locality_centroid CLUSTER ON temp_locality_centroid_geom_idx;

-- update localities where state polygon contains a locality centroid -- 1960 
UPDATE admin_bdys.temp_split_localities AS loc
  SET match_type = 'CENTROID'
  FROM admin_bdys.temp_locality_centroid AS cen
  WHERE ST_Within(cen.geom, loc.geom)
  AND cen.locality_pid = loc.locality_pid
  AND loc.match_type = 'SPLIT';

DROP TABLE IF EXISTS admin_bdys.temp_locality_centroid;
