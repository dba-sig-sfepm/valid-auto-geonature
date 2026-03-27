-- DROP FUNCTION valid_auto.fn_valid_auto_periode(int8, text, text, jsonb);

CREATE OR REPLACE FUNCTION valid_auto.fn_valid_auto_periode(p_id_synthese bigint, p_code_liste text, p_code_territoire text, p_params jsonb DEFAULT NULL::jsonb)
 RETURNS valid_auto.t_note_result
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_result         valid_auto.t_note_result;
    v_table_name     text;
    v_schema_name    text := 'valid_auto';  
BEGIN
    -- Construire dynamiquement le nom de la table de référence
    --    ex : ref_periode_chiro_metro, ref_identification_..., etc.
    v_table_name := format('ref_periode_%s', p_code_liste);
	v_result.code_type_rule = 'period';

    -- Calcul de la note temporelle
    BEGIN
EXECUTE format($sql$
    SELECT
        CASE
            ------------------------------------------------------------------
            -- D1 : Cas “année seule” (date_min = date_max = 01/01 00:00)
            --      uniquement si on a au moins une période dans le référentiel
            ------------------------------------------------------------------
            WHEN ref.nb_periods > 0
             AND s.date_min::date = s.date_max::date
             AND s.date_min::time = '00:00:00'
             AND EXTRACT(month FROM s.date_min) = 1
             AND EXTRACT(day   FROM s.date_min) = 1
            THEN 'D1'

            ------------------------------------------------------------------
            -- NULL : aucune période définie dans le référentiel
            --        => v_result.note restera NULL => exception en fin de fn
            ------------------------------------------------------------------
            WHEN ref.nb_periods = 0 THEN NULL

            ------------------------------------------------------------------
            -- D3 : intervalle entièrement dans au moins une période favorable
            ------------------------------------------------------------------
            WHEN ref.fully_inside_any THEN 'D3'

            ------------------------------------------------------------------
            -- D2 : intervalle complètement en dehors de TOUTES les périodes
            ------------------------------------------------------------------
            WHEN NOT ref.overlaps_any THEN 'D2'

            ------------------------------------------------------------------
            -- D1 : reste = chevauchement partiel avec au moins une période
            ------------------------------------------------------------------
            ELSE 'D1'
        END AS note_periode,

        jsonb_build_object(
            'cd_nom', s.cd_nom,
            'cd_ref_es', taxonomie.find_cdref_es(s.cd_nom),
            'territoire', $2,
            'groupe', $3,
            'date_min', s.date_min::date,
            'date_max', s.date_max::date
        ) AS details_json

    FROM gn_synthese.synthese s

    -- Agrégat LATERAL sur toutes les périodes de ref pour cette espèce/territoire
    LEFT JOIN LATERAL (
        SELECT
            COUNT(*) AS nb_periods,
            -- au moins une période qui contient entièrement l’intervalle obs
            bool_or(
                EXTRACT(doy FROM s.date_min) >= rt.date_obs_favorable_inf
            AND EXTRACT(doy FROM s.date_max) <= rt.date_obs_favorable_sup
            ) AS fully_inside_any,
            -- au moins une période qui chevauche l’intervalle obs
            bool_or(
                EXTRACT(doy FROM s.date_max) >= rt.date_obs_favorable_inf
            AND EXTRACT(doy FROM s.date_min) <= rt.date_obs_favorable_sup
            ) AS overlaps_any
        FROM %I.%I rt
        WHERE rt.cd_ref = taxonomie.find_cdref_es(s.cd_nom)
          AND rt.code_territoire = $2
    ) AS ref ON TRUE

    WHERE s.id_synthese = $1
      AND s.id_nomenclature_observation_status = 84
$sql$, v_schema_name, v_table_name)
INTO
    v_result.note,
    v_result.details
USING
    p_id_synthese,      -- $1
    p_code_territoire,  -- $2
    p_code_liste;       -- $3 (utilisé dans details_json)

    EXCEPTION
        WHEN undefined_table THEN
            RAISE EXCEPTION
                'La table de référence %.% n''existe pas (code_liste=%, code_territoire=%)',
                v_schema_name, v_table_name, p_code_liste, p_code_territoire;
    END;

    IF v_result.note IS NULL THEN
        RAISE EXCEPTION
            'Aucune période favorable trouvée pour id_synthese=% (id_area=%)', p_id_synthese, v_id_area;
    END IF;

    RETURN v_result;
END;
$function$
;
