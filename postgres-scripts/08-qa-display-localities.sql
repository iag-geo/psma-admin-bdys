-- QA - What's been lost? (add to GitHub readme.md each quarter
SELECT '| ' || loc.locality_pid || ' | ' || loc.locality_name || ' | ' || COALESCE(loc.postcode,'') || ' | ' || loc.state || ' | ' || loc.address_count || ' | ' || loc.street_count || ' |' AS locality
  FROM admin_bdys.locality_bdys AS loc
  LEFT OUTER JOIN admin_bdys.locality_bdys_display AS bdy
  ON loc.locality_pid = bdy.locality_pid
  WHERE bdy.locality_pid IS NULL
  ORDER BY loc.state,
           loc.locality_name,
           loc.postcode;


-- select Count(*) from admin_bdys.locality_bdys -- 15574
-- select Count(*) from admin_bdys.locality_bdys_display -- 15574



-- QA bad polygons

-- select ST_Area(ST_Transform(geom, 3577)) AS area, * from admin_bdys.temp_holes_distinct where match_type IS NULL;

--select * from admin_bdys.locality_bdys_display where ST_IsEmpty(geom); -- 0

-- select * from admin_bdys.locality_bdys_display_full_res where NOT ST_IsValid(geom); -- 0
-- select * from admin_bdys.locality_bdys_display where NOT ST_IsValid(geom); -- 0



-- 
-- 
-- -- QA - Geoscape changes
-- 
-- -- New locality_pids
-- SELECT loc.*
--   FROM admin_bdys.locality_bdys_display AS loc
--   LEFT OUTER JOIN public.locality_bdys_display_201511 AS bdy
--   ON loc.locality_pid = bdy.loc_pid
--   WHERE bdy.loc_pid IS NULL
--   ORDER BY loc.state,
--            loc.locality_name,
--            loc.postcode;
-- 
-- -- lost locality_pids
-- SELECT bdy.*
--   FROM admin_bdys.locality_bdys_display AS loc
--   RIGHT OUTER JOIN public.locality_bdys_display_201511 AS bdy
--   ON loc.locality_pid = bdy.loc_pid
--   WHERE loc.locality_pid IS NULL
--   ORDER BY loc.state,
--            loc.locality_name,
--            loc.postcode;