<?php

include "../../functions.inc";
include ("../../jpgraph-1.12.2/src/jpgraph.php");
include ("../../jpgraph-1.12.2/src/jpgraph_bar.php");
include ("../../jpgraph-1.12.2/src/jpgraph_line.php");


$ydata = array(12,15,22,19,5);

$graph = new Graph(400,200);
$graph->img->SetMargin(40,80,40,40);
$graph->SetScale("textlin");
$graph->SetShadow();

$graph->title->Set('Graph exemple');

$line = new LinePlot($ydata);
$line->SetBarCenter();
$line->SetWeight(2);

//$bar = new BarPlot($ydata);
$bar2 = new BarPlot($ydata);
$bar2->SetFillColor("red");

//$gbar = new GroupbarPlot(array($bar,$bar2));

//$graph->Add($gbar);
$graph->Add($bar2);
$graph->Add($line);

// Output line
$graph->Stroke();

?>

