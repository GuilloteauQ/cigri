<?php
include "../../../functions.inc";
define('SMARTY_DIR','../../../Smarty-2.5.0/libs/');
require(SMARTY_DIR.'Smarty.class.php'); // On charge SMARTY
$smarty = new Smarty;
$login = $REMOTE_USER;
$smarty->assign('login',$login );

$link = dbconnect();

$query = "
select  count(*) as total
from  jobs
where jobMJobsId = '$ID'
and jobState = 'Running'
";

list($reponse2,$nb) = sql_query($query);
$nb_total = $reponse2[0][total];

 // en fonction de ce nombre on peut donc avoir le nombre de pages pr�sentes
//	echo "<font color = \"FF0000\">";

$query = "  select  *
            from  jobs
            where jobMJobsId = '$ID'
            and jobState = 'Running'
         ";

list($reponse,$nb_ligne,$page_courante,$nb_jobs,$page_courante,$sensprim,$senssecond,$cleprimaire,$clesecondaire) = sortedQuery($query,$nb_jobs,$page_courante,$pge,$lim_inf,$valid,$page,$clic,$cleprimaire,$clesecondaire,$sensprim,$senssecond);

//echo"query_tab". $query_tab ;

//			echo "</br>les variables:";
//			echo "</br>bouton : ".$valid.$page.$clic;
//			echo "</br> : nb_jobs : ".$nb_jobs;
//			echo "</br> : page_courante : ".$page_courante;
//			echo "</br> :clesecondaire  : ".$clesecondaire;
//			echo "</br> : cleprimaire : ".$cleprimaire;
//			echo "</br> : sensprim : ".$sensprim;
//			echo "</br> :senssecond :  ".$senssecond;
//			echo "</br> :lim_inf :  ".$lim_inf;



$nb_page=  ceil($nb_total/$nb_jobs); //ceil pren l'arrondi superieur

$pages=array(); for ($i=1;$i<=$nb_page;$i++){array_push($pages,$i);}// on met les pages dans un tablo pour le derouler dans un checkbox


$smarty->assign('nb_total', $nb_total);

// on met les pages dans un tablo pour le derouler dans un checkbox
$smarty->assign('pages', $pages);
 // varaible contenant le nombre totale de page
$smarty->assign('nb_page', $nb_page);
// numero de la page courante
$smarty->assign('page_courante',$page_courante );
// nombre de jobs affich� sur la page
$smarty->assign('nb_jobs', $nb_jobs);
// donne l'ordre d'affichage actuel
$smarty->assign('cleprimaire', $cleprimaire);
$smarty->assign('clesecondaire',$clesecondaire );
$smarty->assign('sensprim', $sensprim);
$smarty->assign('senssecond', $senssecond);


for($i=0; $i <$nb_ligne;$i++){
    $reponse[$i][jobClusterName] = htmlentities($reponse[$i][jobClusterName]) ;
    $reponse[$i][jobTSub] = htmlentities($reponse[$i][jobTSub]) ;
    $reponse[$i][jobParam] = htmlentities($reponse[$i][jobParam]) ;
}

$smarty->assign('nb_ligne1', $nb_ligne);
$smarty->assign('reponse1', $reponse);

$smarty->assign('ID', $ID);

mysql_close($link);
$smarty->display('jobs_en_cours_details_parametres_en_cours.tpl');

?>
