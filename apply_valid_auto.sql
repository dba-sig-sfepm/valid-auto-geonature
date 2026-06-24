-- DROP FUNCTION valid_auto.apply_valid_auto(int8, uuid);

CREATE OR REPLACE FUNCTION valid_auto.apply_valid_auto(p_id_synthese bigint, p_uuid uuid)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_code_liste    text;
    v_code_area     text;

    v_res_ident  valid_auto.t_note_result;
    v_res_per    valid_auto.t_note_result;
    v_res_pres   valid_auto.t_note_result;

    v_note_identification text;
    v_note_periode        text;
    v_note_presence       text;

BEGIN
    ------------------------------------------------------------------
    -- 1. Récupérer EN UNE SEULE FOIS liste + territoire ✅
    ------------------------------------------------------------------
   WITH base AS (
    SELECT id_synthese,
           cd_nom,
           taxonomie.find_cdref_es(cd_nom) AS cd_ref
    FROM gn_synthese.synthese
    WHERE id_synthese = p_id_synthese
	)
	SELECT cnl.code_liste,
	       vt.area_code
    INTO v_code_liste,
         v_code_area
	FROM base s
	JOIN valid_auto.v_cor_cdref_grp_valid_auto cnl  ON cnl.cd_ref = s.cd_ref
	JOIN gn_synthese.cor_area_synthese cas  ON cas.id_synthese = s.id_synthese
	JOIN ref_geo.l_areas la  ON la.id_area = cas.id_area AND la.id_type = 24
	JOIN valid_auto.v_territoires_france vt  ON vt.id_area = la.id_area
	limit 1;

    IF v_code_liste IS NULL THEN
        RAISE EXCEPTION 'Aucune liste trouvée pour id_synthese = %', p_id_synthese;
    END IF;

    IF v_code_area IS NULL THEN
        RAISE EXCEPTION 'Aucun territoire trouvé pour id_synthese = %', p_id_synthese;
    END IF;

    ------------------------------------------------------------------
    -- 2. Appels directs (plus rapide que EXECUTE) ✅
    ------------------------------------------------------------------
    SELECT * INTO v_res_ident
    FROM valid_auto.fn_valid_auto_identification(
        p_id_synthese, v_code_liste, v_code_area
    );

    SELECT * INTO v_res_per
    FROM valid_auto.fn_valid_auto_periode(
        p_id_synthese, v_code_liste, v_code_area
    );

    SELECT * INTO v_res_pres
    FROM valid_auto.fn_valid_auto_presence(
        p_id_synthese, v_code_liste, v_code_area
    );

    ------------------------------------------------------------------
    -- 3. Stocker les notes en variables
    ------------------------------------------------------------------
    v_note_identification := v_res_ident.note;
    v_note_periode        := v_res_per.note;
    v_note_presence       := v_res_pres.note;

    ------------------------------------------------------------------
    -- 4. INSERT groupé (moins de coûts IO) ✅
    ------------------------------------------------------------------
    INSERT INTO valid_auto.calculated_notes AS cn (
        id_synthese, code_type_rule, note, details
    )
    VALUES
    (
        p_id_synthese,
        v_res_ident.code_type_rule,
        v_res_ident.note,
        v_res_ident.details
    ),
    (
        p_id_synthese,
        v_res_per.code_type_rule,
        v_res_per.note,
        v_res_per.details
    ),
    (
        p_id_synthese,
        v_res_pres.code_type_rule,
        v_res_pres.note,
        v_res_pres.details
    )
    ON CONFLICT (id_synthese, code_type_rule) DO UPDATE
    SET note    = EXCLUDED.note,
        details = EXCLUDED.details,
        date_calc = now();

    ------------------------------------------------------------------
    -- 5. Validation (inchangé ✅)
    ------------------------------------------------------------------
    PERFORM valid_auto.compute_validation_status_v2(
        p_id_synthese,
		p_uuid,
        v_note_identification,
        v_note_periode,
        v_note_presence
    );

END;
$function$
;
