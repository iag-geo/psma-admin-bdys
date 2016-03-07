
-- delete split locality polygons that are on the wrong side of a state border
DELETE FROM admin_bdys.temp_split_localities -- 16008
  WHERE loc_state <> ste_state;


-- insert non-border/coastline localities into working table -- 12786 
INSERT INTO admin_bdys.temp_split_localities (gid, locality_pid, loc_state, ste_state, match_type, geom)
SELECT gid,
       locality_pid,
       state AS loc_state,
       state AS ste_state,
       'GOOD' AS match_type, 
       geom
  FROM admin_bdys.temp_localities
  WHERE gid NOT IN (SELECT gid FROM admin_bdys.temp_split_localities);


-- update match_type for localities where state polygon is assigned to one locality only -- 2022  
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


-- create table of locality polygon centroids -- 2844  
DROP TABLE IF EXISTS admin_bdys.temp_locality_centroid;
SELECT gid,
       locality_pid,
       ST_PointOnSurface(geom)::geometry(Point, 4283) AS geom
  INTO admin_bdys.temp_locality_centroid
  FROM admin_bdys.temp_localities
  WHERE gid IN (SELECT gid FROM admin_bdys.temp_split_localities WHERE match_type = 'SPLIT');

CREATE INDEX temp_locality_centroid_geom_idx ON admin_bdys.temp_locality_centroid USING gist (geom);
ALTER TABLE admin_bdys.temp_locality_centroid CLUSTER ON temp_locality_centroid_geom_idx;

-- update localities where state polygon contains a locality centroid -- 2743  
UPDATE admin_bdys.temp_split_localities AS loc
  SET match_type = 'CENTROID'
  FROM admin_bdys.temp_locality_centroid AS cen
  WHERE ST_Within(cen.geom, loc.geom)
  AND cen.locality_pid = loc.locality_pid
  AND loc.match_type = 'SPLIT';

DROP TABLE IF EXISTS admin_bdys.temp_locality_centroid;


-- fix slivers on the borders that are valid parts of localities (albeit split localities due to overlaps with the other side of the border)
UPDATE admin_bdys.temp_split_Localities as loc -- 30
  SET match_type = 'BORDER SLIVER'
  FROM admin_bdys.temp_state_border_buffers as ste
  WHERE (st_intersects(loc.geom, ste.geom)
    AND loc.loc_state = ste.state)
  AND loc.match_type = 'SPLIT'
  AND loc.locality_pid <> 'NSW2046'; -- avoid Jervis Bay issue

-- fix slivers that aren't connected to the main locality due to the border -- 26
UPDATE admin_bdys.temp_split_localities AS loc1
SET locality_pid = loc2.locality_pid
  FROM admin_bdys.temp_split_localities AS loc2
  WHERE (ST_Touches(loc1.geom, loc2.geom)
    AND loc1.loc_state = loc2.loc_state
    AND loc1.locality_pid <> loc2.locality_pid)
  AND loc1.match_type = 'BORDER SLIVER';
