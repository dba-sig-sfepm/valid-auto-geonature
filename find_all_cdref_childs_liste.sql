-- DROP FUNCTION taxonomie.find_all_cdref_childs_liste(int4);

CREATE OR REPLACE FUNCTION taxonomie.find_all_cdref_childs_liste(fid_liste integer)
 RETURNS TABLE(cd_ref integer)
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
BEGIN
    RETURN QUERY
    WITH RECURSIVE descendants AS (
        -- Point de départ : cd_ref des taxons de la liste
        SELECT DISTINCT t.cd_ref
        FROM taxonomie.cor_nom_liste cnl
        JOIN taxonomie.taxref t ON t.cd_nom = cnl.cd_nom
        WHERE cnl.id_liste = (select l.id_liste from taxonomie.bib_listes l where l.id_liste = fid_liste)

        UNION ALL

        -- Descendants récursifs
        SELECT tx.cd_ref
        FROM taxonomie.taxref tx
        JOIN descendants d ON tx.cd_sup = d.cd_ref
    )
    SELECT DISTINCT d.cd_ref
    FROM descendants d
    JOIN taxonomie.taxref t ON t.cd_ref = d.cd_ref
    WHERE t.id_rang IN ('ES') and t.cd_nom = t.cd_ref;
END;
$function$
;
