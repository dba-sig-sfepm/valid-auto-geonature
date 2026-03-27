-- DROP FUNCTION valid_auto.fn_valid_auto_presence(int8, text, text, jsonb);

CREATE OR REPLACE FUNCTION valid_auto.fn_valid_auto_presence(p_id_synthese bigint, p_code_liste text, p_code_territoire text, p_params jsonb DEFAULT NULL::jsonb)
 RETURNS valid_auto.t_note_result
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_result         valid_auto.t_note_result;
    v_table_name     text;
    v_schema_name    text := 'valid_auto';  
    v_area_type      integer;
BEGIN
    -- Construire dynamiquement le nom de la table de référence
    --    ex : ref_periode_chiro_metro, ref_identification_..., etc.
    v_table_name := format('ref_presence_%s', p_code_liste);
	v_result.code_type_rule = 'pres';

    v_area_type := COALESCE(
        NULLIF((p_params->>'id_type_area_presence')::integer, 0),
        27
    );

    -- Calcul de la note de présence
    BEGIN
        EXECUTE format($sql$
		    SELECT
		        CASE
		            WHEN count(DISTINCT rp.note_presence) = 1 THEN max(rp.note_presence)
		            WHEN count(DISTINCT rp.note_presence) > 1 THEN 'P2'::text
		            ELSE 'P1'::text
		        END AS note_presence,
		        jsonb_build_object(
		            'cd_nom', s.cd_nom,
		            'cd_ref_es', taxonomie.find_cdref_es(s.cd_nom),
		            'presence_values', jsonb_agg(DISTINCT rp.note_presence),
					'area_code', jsonb_agg(DISTINCT rp.area_code),
					'territoire', $3,
					'groupe', $4
		        ) AS details_json
		    FROM gn_synthese.synthese s
		    JOIN gn_synthese.cor_area_synthese c ON s.id_synthese = c.id_synthese
		    JOIN ref_geo.l_areas la ON la.id_area = c.id_area AND la.id_type = $2
		    JOIN %I.%I rp ON rp.area_code::text = la.area_code::text AND rp.cd_ref = taxonomie.find_cdref_es(s.cd_nom) and rp.code_territoire = $3
		    WHERE s.id_synthese = $1 AND s.id_nomenclature_observation_status = 84
			GROUP BY s.id_synthese, s.cd_nom
        $sql$, v_schema_name, v_table_name)
        INTO
            v_result.note,
            v_result.details
        USING
            p_id_synthese, v_area_type, p_code_territoire, p_code_liste;

    EXCEPTION
        WHEN undefined_table THEN
            RAISE EXCEPTION
                'La table de référence %.% n''existe pas (code_liste=%, code_territoire=%)',
                v_schema_name, v_table_name, p_code_liste, p_code_territoire;
    END;


    IF v_result.note IS NULL THEN
        RAISE EXCEPTION
            'Aucune note de présence trouvée pour id_synthese=% (id_type_area=%)', p_id_synthese, v_area_type;
    END IF;

    RETURN v_result;
END;
$function$
;
