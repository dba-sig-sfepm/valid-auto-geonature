-- DROP FUNCTION valid_auto.compute_validation_status(int8, text, text, text);

CREATE OR REPLACE FUNCTION valid_auto.compute_validation_status(p_id_synthese bigint, p_note_identification text, p_note_periode text, p_note_presence text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$
DECLARE
    -- Statut (libellé) et commentaire calculés à partir des notes
    v_valid_status   text;   -- Non réalisable, Invalide, Douteux, Probable, Certain - très probable
    v_valid_comment  text;

    -- Libellés des notes (ref_notes)
    v_lib_identification text;
    v_lib_presence       text;
    v_lib_periode        text;

    -- Id du statut de validation (nomenclature STATUT_VALID)
    v_id_nomenclature_valid_status integer;

    -- Données de la synthèse
    v_uuid                     uuid;
    v_synth_validator          text;
    v_synth_validation_comment text;
    v_synth_validation_date    timestamp;
    v_synth_id_nomenclature    integer;

    -- Lignes de t_validations
    v_auto_val        gn_commons.t_validations%ROWTYPE;  -- dernière auto SFEPM
    v_last_manual_val gn_commons.t_validations%ROWTYPE;  -- dernière manuelle non producteur

    v_has_auto            boolean := false;
    v_has_manual_non_prod boolean := false;

    -- Booleens pour savoir ce que reflète la synthèse
    v_synth_reflects_auto   boolean := false;
    v_synth_reflects_manual boolean := false;
BEGIN
    ------------------------------------------------------------------
    -- 1. Déterminer le statut (texte) à partir des notes (ref_valid_auto)
    ------------------------------------------------------------------
    SELECT r.valid_auto
      INTO v_valid_status
      FROM valid_auto.ref_valid_auto r
     WHERE r.note_identification = p_note_identification
       AND r.note_periode        = p_note_periode
       AND r.note_presence       = p_note_presence;

    IF v_valid_status IS NULL THEN
        RAISE EXCEPTION
            'Aucun statut trouvé dans ref_valid_auto pour les notes (ident=% , periode=% , presence=%)',
            p_note_identification, p_note_periode, p_note_presence;
    END IF;

    ------------------------------------------------------------------
    -- 2. Récupérer les libellés des notes (ref_notes)
    ------------------------------------------------------------------
    SELECT lib_note
      INTO v_lib_identification
      FROM valid_auto.ref_notes
     WHERE code_note = p_note_identification;

    IF v_lib_identification IS NULL THEN
        RAISE EXCEPTION
            'Impossible de trouver le libellé pour la note identification (%)',
            p_note_identification;
    END IF;

    SELECT lib_note
      INTO v_lib_presence
      FROM valid_auto.ref_notes
     WHERE code_note = p_note_presence;

    IF v_lib_presence IS NULL THEN
        RAISE EXCEPTION
            'Impossible de trouver le libellé pour la note présence (%)',
            p_note_presence;
    END IF;

    SELECT lib_note
      INTO v_lib_periode
      FROM valid_auto.ref_notes
     WHERE code_note = p_note_periode;

    IF v_lib_periode IS NULL THEN
        RAISE EXCEPTION
            'Impossible de trouver le libellé pour la note période (%)',
            p_note_periode;
    END IF;

    ------------------------------------------------------------------
    -- 3. Construire le commentaire de validation
    ------------------------------------------------------------------
    v_valid_comment :=
          'SFEPM - IDENTIFICATION : ' || v_lib_identification
       || ' - PRESENCE : '           || v_lib_presence
       || ' - PERIODE : '            || v_lib_periode;

    ------------------------------------------------------------------
    -- 4. Récupérer l'id_nomenclature_valid_status (STATUT_VALID)
    --    en comparant v_valid_status à label_default
    ------------------------------------------------------------------
    SELECT n.id_nomenclature
      INTO v_id_nomenclature_valid_status
      FROM ref_nomenclatures.t_nomenclatures n
      JOIN ref_nomenclatures.bib_nomenclatures_types t
        ON n.id_type = t.id_type
     WHERE t.mnemonique   = 'STATUT_VALID'
       AND n.label_default = v_valid_status;

    IF v_id_nomenclature_valid_status IS NULL THEN
        RAISE EXCEPTION
            'Impossible de trouver le code STATUT_VALID (label_default) pour le statut (%)',
            v_valid_status;
    END IF;

    ------------------------------------------------------------------
    -- 5. Récupérer la ligne de synthèse
    ------------------------------------------------------------------
    SELECT s.unique_id_sinp,
           s.validator,
           s.validation_comment,
           s.meta_validation_date,
           s.id_nomenclature_valid_status
      INTO v_uuid,
           v_synth_validator,
           v_synth_validation_comment,
           v_synth_validation_date,
           v_synth_id_nomenclature
      FROM gn_synthese.synthese s
     WHERE s.id_synthese = p_id_synthese;

    IF v_uuid IS NULL THEN
        RAISE EXCEPTION
            'Impossible de trouver la synthèse pour id_synthese = %',
            p_id_synthese;
    END IF;

    ------------------------------------------------------------------
    -- 6. Récupérer l’historique des validations
    ------------------------------------------------------------------

    -- 6.a. Dernière validation auto SFEPM (id_validator = 26)
    SELECT v.*
      INTO v_auto_val
      FROM gn_commons.t_validations v
     WHERE v.uuid_attached_row = v_uuid
       AND v.id_validator = 26
     ORDER BY v.validation_date DESC, v.id_validation DESC
     LIMIT 1;

    v_has_auto := FOUND;

    -- 6.b. Dernière validation manuelle non producteur
    --      (validation_auto = false, id_validator ≠ 4,5,6,26)
    SELECT v.*
      INTO v_last_manual_val
      FROM gn_commons.t_validations v
     WHERE v.uuid_attached_row = v_uuid
       AND v.validation_auto = false
       AND v.id_validator NOT IN (4,5,6,26)
     ORDER BY v.validation_date DESC, v.id_validation DESC
     LIMIT 1;

    v_has_manual_non_prod := FOUND;

    ------------------------------------------------------------------
    -- 7. Calculer ce que reflète la synthèse
    ------------------------------------------------------------------

    -- 7.a Synthèse reflète-t-elle l'auto SFEPM ?
    v_synth_reflects_auto :=
        v_has_auto
        AND v_synth_validator = 'Validation automatique SFEPM'
        AND v_synth_id_nomenclature = v_auto_val.id_nomenclature_valid_status
        AND v_synth_validation_comment IS NOT DISTINCT FROM v_auto_val.validation_comment
        AND v_synth_validation_date   IS NOT DISTINCT FROM v_auto_val.validation_date;

    -- 7.b Synthèse reflète-t-elle la dernière validation manuelle non producteur ?
    v_synth_reflects_manual :=
        v_has_manual_non_prod
        AND v_last_manual_val.validation_auto = false
        AND v_synth_validator NOT IN ('Validation automatique SFEPM',
                                      'Producteur','Régional','National')
        AND v_synth_id_nomenclature = v_last_manual_val.id_nomenclature_valid_status
        AND v_synth_validation_comment IS NOT DISTINCT FROM v_last_manual_val.validation_comment
        AND v_synth_validation_date   IS NOT DISTINCT FROM v_last_manual_val.validation_date;

    ------------------------------------------------------------------
    -- 8. CAS 1 : aucune validation auto SFEPM existante
    ------------------------------------------------------------------
    IF NOT v_has_auto THEN
        ------------------------------------------------------------------
        -- 1.b : la synthèse reflète une validation manuelle non producteur
        --       -> on ajoute l’auto uniquement dans l’historique
        ------------------------------------------------------------------
        IF v_synth_reflects_manual THEN
            PERFORM set_config('valid_auto.skip_synthese_update', 'true', true);

            INSERT INTO gn_commons.t_validations (
                uuid_attached_row,
                id_nomenclature_valid_status,
                validation_auto,
                id_validator,
                validation_comment,
                validation_date
            ) VALUES (
                v_uuid,
                v_id_nomenclature_valid_status,
                true,
                26,
                v_valid_comment,
                now()
            );

            PERFORM set_config('valid_auto.skip_synthese_update', 'false', true);

            RETURN;
        END IF;

        ------------------------------------------------------------------
        -- 1.a : pas de validation manuelle non producteur reflétée
        --       (aucune validation ou seulement des validations producteurs)
        --       -> on ajoute l’auto, le trigger met à jour la synthèse
        ------------------------------------------------------------------
        INSERT INTO gn_commons.t_validations (
            uuid_attached_row,
            id_nomenclature_valid_status,
            validation_auto,
            id_validator,
            validation_comment,
            validation_date
        ) VALUES (
            v_uuid,
            v_id_nomenclature_valid_status,
            true,
            26,
            v_valid_comment,
            now()
        );

        RETURN;
    END IF; -- fin CAS 1

    ------------------------------------------------------------------
    -- 9. CAS 2 : il existe déjà une validation auto SFEPM
    ------------------------------------------------------------------

    -- Sécurité : s’assurer que v_auto_val est bien renseigné
    IF v_auto_val.id_validation IS NULL THEN
        PERFORM valid_auto.log_warning(
            p_id_synthese,
            format(
                'Incohérence : v_has_auto = true mais aucune validation auto SFEPM trouvée dans t_validations (id_synthese=%s)',
                p_id_synthese
            )
        );
        RETURN;
    END IF;

    ------------------------------------------------------------------
    -- 2.a : la synthèse reflète la validation auto SFEPM
    ------------------------------------------------------------------
    IF v_synth_reflects_auto THEN

        -- 2.a.i : nouvelles notes + statut identiques à l’ancienne auto
        IF v_auto_val.id_nomenclature_valid_status = v_id_nomenclature_valid_status
           AND v_auto_val.validation_comment IS NOT DISTINCT FROM v_valid_comment
        THEN
            -- Rien à faire
            RETURN;
        END IF;

        -- 2.a.ii : nouvelles notes / statut différents
        --          => mise à jour de l’auto ET de la synthèse
        UPDATE gn_commons.t_validations
           SET id_nomenclature_valid_status = v_id_nomenclature_valid_status,
               validation_comment          = v_valid_comment,
               validation_date             = now()
         WHERE id_validation = v_auto_val.id_validation;

        UPDATE gn_synthese.synthese
           SET id_nomenclature_valid_status = v_id_nomenclature_valid_status,
               validation_comment          = v_valid_comment,
               validator                   = 'Validation automatique SFEPM',
               meta_validation_date        = now()
         WHERE id_synthese = p_id_synthese;

        RETURN;
    END IF;

    ------------------------------------------------------------------
    -- 2.b : la synthèse reflète une validation manuelle non producteur,
    --       même si une auto plus récente peut exister dans l’historique
    ------------------------------------------------------------------
    IF v_synth_reflects_manual THEN

        -- 2.b.i : nouvelles notes + statut identiques à l’ancienne auto
        IF v_auto_val.id_nomenclature_valid_status = v_id_nomenclature_valid_status
           AND v_auto_val.validation_comment IS NOT DISTINCT FROM v_valid_comment
        THEN
            -- On ne touche ni l’historique, ni la synthèse
            RETURN;
        END IF;

        -- 2.b.ii : nouvelles notes / statut différents
        --          => mise à jour uniquement de la validation auto
        UPDATE gn_commons.t_validations
           SET id_nomenclature_valid_status = v_id_nomenclature_valid_status,
               validation_comment          = v_valid_comment,
               validation_date             = now()
         WHERE id_validation = v_auto_val.id_validation;

        RETURN;
    END IF;

    ------------------------------------------------------------------
    -- 2.c Cas résiduel : la synthèse reflète autre chose (producteur,
    --     régional, national, valeur par défaut, ou incohérence)
    --     -> on met à jour uniquement l’auto + log warning
    ------------------------------------------------------------------
    PERFORM valid_auto.log_warning(
        p_id_synthese,
        format(
            'CAS2 résiduel : la synthèse ne reflète ni la dernière auto ni la dernière manuelle non producteur (validator=%s)',
            coalesce(v_synth_validator, '<NULL>')
        )
    );

    UPDATE gn_commons.t_validations
       SET id_nomenclature_valid_status = v_id_nomenclature_valid_status,
           validation_comment          = v_valid_comment,
           validation_date             = now()
     WHERE id_validation = v_auto_val.id_validation;

    RETURN;
END;
$function$
;
