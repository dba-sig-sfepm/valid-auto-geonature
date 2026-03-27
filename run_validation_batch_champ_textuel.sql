-- DROP FUNCTION valid_auto.run_validation_batch(text, text);

CREATE OR REPLACE FUNCTION valid_auto.run_validation_batch(p_filter_field text, p_filter_value text)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_sql            text;
    v_rec            record;
    v_total          int := 0;
    v_success        int := 0;
    v_errors         int := 0;
    v_warnings       int := 0;
    v_id_report      bigint;
    v_sqlstate       text;
    v_msg            text;
    v_detail         text;
    v_hint           text;
    v_context        text;
BEGIN
    ----------------------------------------------------------------------
    -- 1. Création du rapport global
    ----------------------------------------------------------------------
    INSERT INTO valid_auto.report_validations(
        filter_field, filter_value, total, success, errors, warnings
    ) VALUES (
        p_filter_field, p_filter_value, 0, 0, 0, 0
    )
    RETURNING id_report INTO v_id_report;

	PERFORM set_config('valid_auto.current_report', v_id_report::text, true);

    ----------------------------------------------------------------------
    -- 2. Construction dynamique de la requête de sélection
    ----------------------------------------------------------------------
    v_sql := format(
        'SELECT id_synthese FROM gn_synthese.synthese WHERE %I = $1 ORDER BY id_synthese',
        p_filter_field
    );

    ----------------------------------------------------------------------
    -- 3. Boucle principale
    ----------------------------------------------------------------------
    FOR v_rec IN EXECUTE v_sql USING p_filter_value LOOP
        v_total := v_total + 1;

        BEGIN
            ------------------------------------------------------------------
            -- Appel de la validation automatique
            ------------------------------------------------------------------
            PERFORM valid_auto.apply_valid_auto(v_rec.id_synthese);

            v_success := v_success + 1;

        EXCEPTION
            WHEN OTHERS THEN
                GET STACKED DIAGNOSTICS
                    v_sqlstate = RETURNED_SQLSTATE,
                    v_msg      = MESSAGE_TEXT,
                    v_detail   = PG_EXCEPTION_DETAIL,
                    v_hint     = PG_EXCEPTION_HINT,
                    v_context  = PG_EXCEPTION_CONTEXT;

                ----------------------------------------------------------------------
                -- Enregistrer l’erreur
                ----------------------------------------------------------------------
                INSERT INTO valid_auto.error_validations(
                    id_report, id_synthese, sqlstate, message, detail, hint, context
                ) VALUES (
                    v_id_report, v_rec.id_synthese,
                    v_sqlstate, v_msg, v_detail, v_hint, v_context
                );

                v_errors := v_errors + 1;
        END;
    END LOOP;

	RESET valid_auto.current_report;

    ----------------------------------------------------------------------
    -- 4. Compter les warnings associés à ce batch
    ----------------------------------------------------------------------
    SELECT COUNT(*)
    INTO v_warnings
    FROM valid_auto.warning_validations
    WHERE id_report = v_id_report;

    ----------------------------------------------------------------------
    -- 5. Mise à jour du rapport global
    ----------------------------------------------------------------------
    UPDATE valid_auto.report_validations
    SET total = v_total,
        success = v_success,
        errors = v_errors,
        warnings = v_warnings
    WHERE id_report = v_id_report;

    ----------------------------------------------------------------------
    -- Retourne l'identifiant du rapport pour consultation
    ----------------------------------------------------------------------
    RETURN v_id_report;
END;
$function$
;
