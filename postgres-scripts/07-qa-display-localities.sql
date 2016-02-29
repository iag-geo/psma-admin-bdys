-- QA - What's been lost? (add to GitHub readme.md each quarter
SELECT '| ' || loc.locality_pid || ' | ' || loc.locality_name || ' | ' || COALESCE(loc.postcode,'') || ' | ' || loc.state || ' | ' || loc.address_count || ' | ' || loc.street_count || ' |' AS locality
  FROM admin_bdys.locality_bdys AS loc
  LEFT OUTER JOIN admin_bdys.locality_bdys_display AS bdy
  ON loc.locality_pid = bdy.locality_pid
  WHERE bdy.locality_pid IS NULL
  ORDER BY loc.state,
           loc.locality_name,
           loc.postcode;




-- 
-- 
-- -- QA - PSMA changes
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