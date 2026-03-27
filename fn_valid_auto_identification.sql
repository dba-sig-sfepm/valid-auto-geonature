-- DROP FUNCTION valid_auto.fn_valid_auto_identification(int8, text, text, jsonb);

CREATE OR REPLACE FUNCTION valid_auto.fn_valid_auto_identification(p_id_synthese bigint, p_code_liste text, p_code_territoire text, p_params jsonb DEFAULT NULL::jsonb)
 RETURNS valid_auto.t_note_result
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_result         valid_auto.t_note_result;
    v_table_name     text;
    v_schema_name    text := 'valid_auto';  
BEGIN
    -- Construire dynamiquement le nom de la table de référence
    --    ex : ref_identification_chiro_metro, ref_identification_..., etc.
    v_table_name := format('ref_identification_%s', p_code_liste);
	v_result.code_type_rule = 'ident';

    -- Calcul de la note d’identification
    BEGIN
        EXECUTE format($sql$
            SELECT
                ri.note_identification,
                jsonb_build_object(
                    'cd_nom', s.cd_nom,
                    'cd_ref_es', taxonomie.find_cdref_es(s.cd_nom),
                    'id_nomenclature_obs_technique', s.id_nomenclature_obs_technique,
					'territoire', $2,
					'groupe', $3
                )
            FROM gn_synthese.synthese s
            LEFT JOIN %I.%I ri ON ri.cd_ref = taxonomie.find_cdref_es(s.cd_nom) AND ri.id_nomenclature_obs_technique = coalesce(s.id_nomenclature_obs_technique,58) and ri.code_territoire = $2 
            WHERE s.id_synthese = $1 AND s.id_nomenclature_observation_status = 84 
        $sql$, v_schema_name, v_table_name)
        INTO
            v_result.note,
            v_result.details
        USING
            p_id_synthese, p_code_territoire, p_code_liste;

    EXCEPTION
        WHEN undefined_table THEN
            RAISE EXCEPTION
                'La table de référence %.% n''existe pas (code_liste=%, code_territoire=%)',
                v_schema_name, v_table_name, p_code_liste, p_code_territoire;
    END;

    -- Si rien trouvé, on peut soit retourner NULL, soit lever une erreur, soit mettre une note par défaut
    IF v_result.note IS NULL THEN
        -- Comportement à adapter à ton besoin :
        -- soit on laisse NULL, soit on fixe une note par défaut
        -- v_result.note := 'I0'; -- exemple éventuel
        RAISE EXCEPTION 
            'Aucune note d''identification trouvée pour id_synthese=%', p_id_synthese;
    END IF;

    RETURN v_result;
END;
$function$
;
