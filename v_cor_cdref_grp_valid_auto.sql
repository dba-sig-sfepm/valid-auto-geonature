-- valid_auto.v_cor_cdref_grp_valid_auto source

CREATE OR REPLACE VIEW valid_auto.v_cor_cdref_grp_valid_auto
AS SELECT lower(replace(l.code_liste::text, ' '::text, '_'::text))::character varying(50) AS code_liste,
    c.cd_ref
   FROM taxonomie.bib_listes l
     CROSS JOIN LATERAL taxonomie.find_all_cdref_childs_liste(l.id_liste) c(cd_ref)
  WHERE l.code_liste::text ~~ 'valid_auto_%'::text;