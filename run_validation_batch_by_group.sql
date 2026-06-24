-- DROP FUNCTION valid_auto.run_validation_batch_by_group(text);

CREATE OR REPLACE FUNCTION valid_auto.run_validation_batch_by_group(p_code_liste text)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_rec       record;
    v_total     int := 0;
    v_success   int := 0;
    v_errors    int := 0;
    v_warnings  int := 0;
    v_id_report bigint;

    v_sqlstate  text;
    v_msg       text;
    v_detail    text;
    v_hint      text;
    v_context   text;
BEGIN

    ------------------------------------------------------------------
    -- Nettoyage tables temporaires
    ------------------------------------------------------------------
    PERFORM set_config('client_min_messages', 'warning', true);

    DROP TABLE IF EXISTS tmp_batch;
    DROP TABLE IF EXISTS tmp_auto;
    DROP TABLE IF EXISTS tmp_manual;
    DROP TABLE IF EXISTS tmp_new_validations;

    ------------------------------------------------------------------
    -- 1. Création du report
    ------------------------------------------------------------------
    INSERT INTO valid_auto.report_validations(
        filter_field, filter_value, total, success, errors, warnings
    ) VALUES (
        'code_liste',
        p_code_liste,
        0, 0, 0, 0
    )
    RETURNING id_report INTO v_id_report;

    ------------------------------------------------------------------
    -- 2. Contexte
    ------------------------------------------------------------------
    PERFORM set_config('valid_auto.current_report', v_id_report::text, true);

    ------------------------------------------------------------------
    -- 3. Batch observations (ADAPTÉ 🔥)
    ------------------------------------------------------------------
    CREATE TEMP TABLE tmp_batch AS
    SELECT s.id_synthese,
           s.unique_id_sinp
    FROM gn_synthese.synthese s
    JOIN valid_auto.v_cor_cdref_grp_valid_auto v
      ON v.cd_ref = taxonomie.find_cdref_es(s.cd_nom)
    WHERE v.code_liste = p_code_liste
      AND s.id_nomenclature_observation_status = 84;

    CREATE INDEX ON tmp_batch(id_synthese);
    CREATE INDEX ON tmp_batch(unique_id_sinp);

    ------------------------------------------------------------------
    -- 4. Table tracking (identique V2)
    ------------------------------------------------------------------
    CREATE TEMP TABLE tmp_new_validations (
        uuid_attached_row uuid,
        id_nomenclature_valid_status integer,
        validation_comment text,
        validation_date timestamp,
        id_validator integer,
        skip_synthese boolean
    );

    ------------------------------------------------------------------
    -- 5. Batch t_validations AUTO
    ------------------------------------------------------------------
    CREATE TEMP TABLE tmp_auto AS
    SELECT DISTINCT ON (v.uuid_attached_row)
           v.uuid_attached_row,
           v.id_validation,
           v.id_nomenclature_valid_status,
           v.validation_comment,
           v.validation_date
    FROM gn_commons.t_validations v
    JOIN tmp_batch b
      ON b.unique_id_sinp = v.uuid_attached_row
    WHERE v.id_validator = 26
    ORDER BY v.uuid_attached_row,
             v.validation_date DESC,
             v.id_validation DESC;

    CREATE INDEX ON tmp_auto(uuid_attached_row);

    ------------------------------------------------------------------
    -- 6. Batch t_validations MANUAL
    ------------------------------------------------------------------
    CREATE TEMP TABLE tmp_manual AS
    SELECT DISTINCT ON (v.uuid_attached_row)
           v.uuid_attached_row,
           v.id_validation,
           v.id_nomenclature_valid_status,
           v.validation_comment,
           v.validation_date
    FROM gn_commons.t_validations v
    JOIN tmp_batch b
      ON b.unique_id_sinp = v.uuid_attached_row
    WHERE v.validation_auto = false
      AND v.id_validator NOT IN (4,5,6,26)
    ORDER BY v.uuid_attached_row,
             v.validation_date DESC,
             v.id_validation DESC;

    CREATE INDEX ON tmp_manual(uuid_attached_row);

    ------------------------------------------------------------------
    -- 7. Boucle principale
    ------------------------------------------------------------------
    PERFORM set_config('valid_auto.skip_synthese_update', 'true', true);

    FOR v_rec IN
        SELECT id_synthese, unique_id_sinp
        FROM tmp_batch
        ORDER BY id_synthese
    LOOP
        v_total := v_total + 1;

        BEGIN
            PERFORM valid_auto.apply_valid_auto_v2(
                v_rec.id_synthese,
                v_rec.unique_id_sinp
            );

            v_success := v_success + 1;

        EXCEPTION
            WHEN OTHERS THEN
                GET STACKED DIAGNOSTICS
                    v_sqlstate = RETURNED_SQLSTATE,
                    v_msg      = MESSAGE_TEXT,
                    v_detail   = PG_EXCEPTION_DETAIL,
                    v_hint     = PG_EXCEPTION_HINT,
                    v_context  = PG_EXCEPTION_CONTEXT;

                INSERT INTO valid_auto.error_validations(
                    id_report, id_synthese, sqlstate, message, detail, hint, context
                ) VALUES (
                    v_id_report,
                    v_rec.id_synthese,
                    v_sqlstate,
                    v_msg,
                    v_detail,
                    v_hint,
                    v_context
                );

                v_errors := v_errors + 1;
        END;
    END LOOP;

    PERFORM set_config('valid_auto.skip_synthese_update', 'false', true);

    ------------------------------------------------------------------
    -- 8. Batch UPDATE synthese
    ------------------------------------------------------------------
    UPDATE gn_synthese.synthese s
    SET
        id_nomenclature_valid_status = v.id_nomenclature_valid_status,
        validation_comment          = v.validation_comment,
        meta_validation_date        = v.validation_date,
        meta_update_date            = v.validation_date,
        validator                   = 'Validation automatique SFEPM'
    FROM (
        SELECT DISTINCT ON (uuid_attached_row)
               uuid_attached_row,
               id_nomenclature_valid_status,
               validation_comment,
               validation_date
        FROM tmp_new_validations
        WHERE skip_synthese = false
        ORDER BY uuid_attached_row,
                 validation_date DESC
    ) v
    WHERE s.unique_id_sinp = v.uuid_attached_row
    AND (
        s.id_nomenclature_valid_status IS DISTINCT FROM v.id_nomenclature_valid_status
        OR s.validation_comment IS DISTINCT FROM v.validation_comment
        OR s.meta_validation_date IS DISTINCT FROM v.validation_date
    );

    ------------------------------------------------------------------
    -- 9. Warnings
    ------------------------------------------------------------------
    SELECT COUNT(*)
    INTO v_warnings
    FROM valid_auto.warning_validations
    WHERE id_report = v_id_report;

    ------------------------------------------------------------------
    -- 10. Report
    ------------------------------------------------------------------
    UPDATE valid_auto.report_validations
    SET total    = v_total,
        success  = v_success,
        errors   = v_errors,
        warnings = v_warnings
    WHERE id_report = v_id_report;

    ------------------------------------------------------------------
    -- Cleanup final
    ------------------------------------------------------------------
    DROP TABLE IF EXISTS tmp_batch;
    DROP TABLE IF EXISTS tmp_auto;
    DROP TABLE IF EXISTS tmp_manual;
    DROP TABLE IF EXISTS tmp_new_validations;

    RETURN v_id_report;
END;
$function$
;
