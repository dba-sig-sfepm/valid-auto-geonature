-- DROP FUNCTION taxonomie.find_cdref_es(int4);

CREATE OR REPLACE FUNCTION taxonomie.find_cdref_es(cdnom integer)
 RETURNS integer
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
--fonction permettant de renvoyer le cd_ref (de l'espèce si sous-espèce) d'un taxon à partir de son cd_nom

  DECLARE ref integer;
  BEGIN
	SELECT INTO ref 
		case when id_rang = 'ES' then cd_ref
			 when id_rang = 'SSES' then cd_sup
		end	
	 FROM taxonomie.taxref WHERE cd_nom = taxonomie.find_cdref(cdnom);
	return ref;
  END;
$function$
;
