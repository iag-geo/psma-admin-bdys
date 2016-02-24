-- QA - What's been lost? (add to GitHub readme.md each quarter
SELECT '| ' || loc.locality_pid || ' | ' || loc.locality_name || ' | ' || COALESCE(loc.postcode,'') || ' | ' || loc.state || ' | ' || loc.address_count || ' | ' || loc.street_count || ' |' AS locality
  FROM admin_bdys.locality_bdys AS loc
  LEFT OUTER JOIN admin_bdys.locality_bdys_display AS bdy
  ON loc.locality_pid = bdy.locality_pid
  WHERE bdy.locality_pid IS NULL
  ORDER BY loc.state,
           loc.locality_name,
           loc.postcode;
