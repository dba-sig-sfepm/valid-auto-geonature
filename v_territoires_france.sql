-- valid_auto.v_territoires_france source

CREATE OR REPLACE VIEW valid_auto.v_territoires_france
AS SELECT la.id_area,
    la.id_type,
    la.area_name,
    lower(la.area_code::text) AS area_code,
    la.geom,
    la.centroid,
    la.source,
    la.comment,
    la.enable,
    la.additional_data,
    la.meta_create_date,
    la.meta_update_date,
    la.geom_4326,
    la.description
   FROM ref_geo.l_areas la
  WHERE la.id_type = 24;