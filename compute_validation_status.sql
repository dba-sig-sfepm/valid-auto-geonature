-- DROP FUNCTION valid_auto.compute_validation_status(int8, uuid, text, text, text);

CREATE OR REPLACE FUNCTION valid_auto.compute_validation_status(p_id_synthese bigint, p_uuid uuid, p_note_identification text, p_note_periode text, p_note_presence text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE

    -- Statut
    v_valid_status   text;
    v_valid_comment  text;
	v_validation_date timestamp;
	v_id_validator	integer;

    -- Libellés
    v_lib_identification text;
    v_lib_presence       text;
    v_lib_periode        text;

    -- Nomenclature
    v_id_nomenclature_valid_status integer;

    -- Synthese
    v_synth_validator          text;
    v_synth_validation_comment text;
    v_synth_validation_date    timestamp;
    v_synth_id_nomenclature    integer;
	v_uuid					uuid;

    -- AUTO / MANUAL (chargés depuis cache)
    
	v_auto_val RECORD;
	v_manual_val RECORD;

    v_has_auto            boolean := false;
    v_has_manual_non_prod boolean := false;

    v_synth_reflects_auto   boolean := false;
    v_synth_reflects_manual boolean := false;
	v_skip_synthese boolean := false;

BEGIN

    ------------------------------------------------------------------
    -- 1. STATUT (inchangé)
    ------------------------------------------------------------------
    SELECT valid_auto
    INTO v_valid_status
    FROM valid_auto.ref_valid_auto
    WHERE note_identification = p_note_identification
      AND note_periode        = p_note_periode
      AND note_presence       = p_note_presence;

    IF v_valid_status IS NULL THEN
        RAISE EXCEPTION
            'Aucun statut trouvé (% % %)',
            p_note_identification, p_note_periode, p_note_presence;
    END IF;

    ------------------------------------------------------------------
    -- 2. LIBELLES (identiques, mais pourraient être cachés si besoin)
    ------------------------------------------------------------------
    SELECT lib_note INTO v_lib_identification
    FROM valid_auto.ref_notes
    WHERE code_note = p_note_identification;

    SELECT lib_note INTO v_lib_presence
    FROM valid_auto.ref_notes
    WHERE code_note = p_note_presence;

    SELECT lib_note INTO v_lib_periode
    FROM valid_auto.ref_notes
    WHERE code_note = p_note_periode;

    ------------------------------------------------------------------
    -- 3. COMMENTAIRE
    ------------------------------------------------------------------
    v_valid_comment :=
          'SFEPM - IDENTIFICATION : ' || v_lib_identification
       || ' - PRESENCE : '           || v_lib_presence
       || ' - PERIODE : '            || v_lib_periode;

    ------------------------------------------------------------------
    -- 4. NOMENCLATURE
    ------------------------------------------------------------------
    SELECT n.id_nomenclature
    INTO v_id_nomenclature_valid_status
    FROM ref_nomenclatures.t_nomenclatures n
    JOIN ref_nomenclatures.bib_nomenclatures_types t
      ON n.id_type = t.id_type
    WHERE t.mnemonique = 'STATUT_VALID'
      AND n.label_default = v_valid_status;

    IF v_id_nomenclature_valid_status IS NULL THEN
        RAISE EXCEPTION 'Nomenclature introuvable (%)', v_valid_status;
    END IF;

    ------------------------------------------------------------------
    -- 5. SYNTHÈSE
    ------------------------------------------------------------------
    SELECT validator,
           validation_comment,
           meta_validation_date,
           id_nomenclature_valid_status
    INTO v_synth_validator,
         v_synth_validation_comment,
         v_synth_validation_date,
         v_synth_id_nomenclature
    FROM gn_synthese.synthese
    WHERE id_synthese = p_id_synthese;

    ------------------------------------------------------------------
    -- 6. 🔥 AUTO / MANUAL depuis cache
    ------------------------------------------------------------------

    SELECT * INTO v_auto_val
    FROM tmp_auto
    WHERE uuid_attached_row = p_uuid;

    v_has_auto := FOUND;

    SELECT * INTO v_manual_val
    FROM tmp_manual
    WHERE uuid_attached_row = p_uuid;

    v_has_manual_non_prod := FOUND;

    ------------------------------------------------------------------
    -- 7. REFLEXION SYNTHÈSE (identique)
    ------------------------------------------------------------------
    v_synth_reflects_auto :=
        v_has_auto
        AND v_synth_validator = 'Validation automatique SFEPM'
        AND v_synth_id_nomenclature = v_auto_val.id_nomenclature_valid_status
        AND v_synth_validation_comment IS NOT DISTINCT FROM v_auto_val.validation_comment
        AND v_synth_validation_date   IS NOT DISTINCT FROM v_auto_val.validation_date;

    v_synth_reflects_manual :=
        v_has_manual_non_prod
        AND v_synth_validator NOT IN ('Validation automatique SFEPM','Producteur','Régional','National')
        AND v_synth_id_nomenclature = v_manual_val.id_nomenclature_valid_status
        AND v_synth_validation_comment IS NOT DISTINCT FROM v_manual_val.validation_comment
        AND v_synth_validation_date   IS NOT DISTINCT FROM v_manual_val.validation_date;

    ------------------------------------------------------------------
    -- CAS 1
    ------------------------------------------------------------------
    IF NOT v_has_auto THEN

		IF v_synth_reflects_manual THEN
		    v_skip_synthese := true;
		
		    INSERT INTO gn_commons.t_validations(
		        uuid_attached_row,
		        id_nomenclature_valid_status,
		        validation_auto,
		        id_validator,
		        validation_comment,
		        validation_date
		    )
		    VALUES (
		        p_uuid,
		        v_id_nomenclature_valid_status,
		        true,
		        26,
		        v_valid_comment,
		        now()
		    )
		    RETURNING uuid_attached_row,
		              id_nomenclature_valid_status,
		              validation_comment,
		              validation_date,
		              id_validator
		    INTO v_uuid,
		         v_id_nomenclature_valid_status,
		         v_valid_comment,
		         v_validation_date,
		         v_id_validator;
		
		    INSERT INTO tmp_new_validations
		    VALUES (
		        v_uuid,
		        v_id_nomenclature_valid_status,
		        v_valid_comment,
		        v_validation_date,
		        v_id_validator,
		        true
		    );
		
		    RETURN;
		END IF;

			v_skip_synthese := false;
			
			INSERT INTO gn_commons.t_validations(
		        uuid_attached_row,
		        id_nomenclature_valid_status,
		        validation_auto,
		        id_validator,
		        validation_comment,
		        validation_date
		    )
		    VALUES (
		        p_uuid,
		        v_id_nomenclature_valid_status,
		        true,
		        26,
		        v_valid_comment,
		        now()
		    )
			RETURNING uuid_attached_row,
			          id_nomenclature_valid_status,
			          validation_comment,
			          validation_date,
			          id_validator
			INTO v_uuid,
			     v_id_nomenclature_valid_status,
			     v_valid_comment,
			     v_validation_date,
			     v_id_validator;
			
			INSERT INTO tmp_new_validations
			VALUES (
			    v_uuid,
			    v_id_nomenclature_valid_status,
			    v_valid_comment,
			    v_validation_date,
			    v_id_validator,
			    v_skip_synthese
			);
        RETURN;
    END IF;

    ------------------------------------------------------------------
    -- CAS 2
    ------------------------------------------------------------------

    IF v_auto_val.id_validation IS NULL THEN
        PERFORM valid_auto.log_warning(p_id_synthese,format(
                'Incohérence : v_has_auto = true mais aucune validation auto SFEPM trouvée dans t_validations (id_synthese=%s)',
                p_id_synthese
            ));
        RETURN;
    END IF;

    -- 2.a
    IF v_synth_reflects_auto THEN

        IF v_auto_val.id_nomenclature_valid_status = v_id_nomenclature_valid_status
           AND v_auto_val.validation_comment IS NOT DISTINCT FROM v_valid_comment
        THEN
            RETURN;
        END IF;

        UPDATE gn_commons.t_validations
        SET id_nomenclature_valid_status = v_id_nomenclature_valid_status,
            validation_comment = v_valid_comment,
            validation_date = now()
        WHERE id_validation = v_auto_val.id_validation;

        UPDATE gn_synthese.synthese
        SET id_nomenclature_valid_status = v_id_nomenclature_valid_status,
            validation_comment = v_valid_comment,
            validator = 'Validation automatique SFEPM',
            meta_validation_date = now()
        WHERE id_synthese = p_id_synthese;

        RETURN;
    END IF;

    -- 2.b
    IF v_synth_reflects_manual THEN

        IF v_auto_val.id_nomenclature_valid_status = v_id_nomenclature_valid_status
           AND v_auto_val.validation_comment IS NOT DISTINCT FROM v_valid_comment
        THEN
            RETURN;
        END IF;

        UPDATE gn_commons.t_validations
        SET id_nomenclature_valid_status = v_id_nomenclature_valid_status,
            validation_comment = v_valid_comment,
            validation_date = now()
        WHERE id_validation = v_auto_val.id_validation;

        RETURN;
    END IF;

    ------------------------------------------------------------------
    -- 2.c
    ------------------------------------------------------------------
    PERFORM valid_auto.log_warning(
        p_id_synthese,
        format('CAS2 résiduel validator=%s', coalesce(v_synth_validator,'<NULL>'))
    );

    UPDATE gn_commons.t_validations
    SET id_nomenclature_valid_status = v_id_nomenclature_valid_status,
        validation_comment = v_valid_comment,
        validation_date = now()
    WHERE id_validation = v_auto_val.id_validation;

END;
$function$
;
