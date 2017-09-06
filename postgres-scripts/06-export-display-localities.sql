SELECT gid, locality_pid AS loc_pid,
  locality_name AS name,
  COALESCE(postcode, '') AS postcode,
  state,
  locality_class AS loc_class,
  address_count AS adr_count,
  street_count AS str_count,
  geom
FROM admin_bdys.locality_bdys_display_vw;
