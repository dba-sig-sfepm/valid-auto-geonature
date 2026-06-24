-- DROP FUNCTION valid_auto.log_warning(int8, text, text);

CREATE OR REPLACE FUNCTION valid_auto.log_warning(p_id_synthese bigint, p_message text, p_context text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    v_id_report bigint;
BEGIN
    BEGIN
        v_id_report := current_setting('valid_auto.current_report')::bigint;
    EXCEPTION WHEN OTHERS THEN
        -- Pas de rapport actif → on ignore le warning
        RETURN;
    END;

    INSERT INTO valid_auto.warning_validations(
        id_report, id_synthese, message, context
    ) VALUES (
        v_id_report, p_id_synthese, p_message, p_context
    );
END;
$function$
;
