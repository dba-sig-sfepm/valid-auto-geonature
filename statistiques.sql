-- statistiques de calculs des notes de validations automatiques

select tn.label_default, count(*) from valid_auto.calculated_notes cn
join gn_synthese.synthese s using (id_synthese)
join gn_commons.t_validations tv on uuid_attached_row = s.unique_id_sinp and id_validator = 26
join ref_nomenclatures.t_nomenclatures tn on tn.id_nomenclature = tv.id_nomenclature_valid_status
where code_type_rule= 'ident' and cn.date_calc::date = date '2026-06-22'
group by tn.label_default order by count desc

-- statistiques de validations en tenant compte des validations manuelles déjà effectuées

select tn.label_default, count(*) from valid_auto.calculated_notes cn
join gn_synthese.synthese s using (id_synthese)
join ref_nomenclatures.t_nomenclatures tn on tn.id_nomenclature = s.id_nomenclature_valid_status
where code_type_rule= 'ident' and cn.date_calc::date = date '2026-06-22'
group by tn.label_default order by count desc

-- statistiques des erreurs 

select left(message,37), count(*) from valid_auto.error_validations ev
where ev.id_report =35
group by left(message,37) order by count desc

--issues du sinp  -- technique inconnue

with a as (select id_synthese from valid_auto.calculated_notes cn
where code_type_rule= 'ident' and cn.date_calc::date = date '2026-06-22'
--union 
--select id_synthese from valid_auto.error_validations ev where id_report = 35
)
select count(*)
from a
join gn_synthese.synthese s using (id_synthese)
where s.id_dataset = 21 and coalesce(s.id_nomenclature_obs_technique,58) = 58

-- par espèce

select t.nom_valide, tn.label_default, count(*) from valid_auto.calculated_notes cn
join gn_synthese.synthese s using (id_synthese)
join gn_commons.t_validations tv on uuid_attached_row = s.unique_id_sinp and id_validator = 26
join ref_nomenclatures.t_nomenclatures tn on tn.id_nomenclature = tv.id_nomenclature_valid_status
join taxonomie.taxref t using (cd_nom)
where code_type_rule= 'ident' and cn.date_calc::date = date '2026-06-22'
group by t.nom_valide, tn.label_default order by t.nom_valide, count desc


