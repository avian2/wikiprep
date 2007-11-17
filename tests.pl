use strict;

use FindBin;
use lib "$FindBin::Bin";

use images;

my ($t, $r);

$t = "Image:Blah1|short|longer|the longest anchor text";
$r = &images::parseImageParameters($t);
die($r) if ($r ne "the longest anchor text");

$t = "Image:Blah1|240x240px|anchor text";
$r = &images::parseImageParameters($t);
die($r) if ($r ne "anchor text");

$t = "Image:Blah1|100px|left|an";
$r = &images::parseImageParameters($t);
die($r) if ($r ne "an");

$t = "Image:Blah1|100PX|Left|An";
$r = &images::parseImageParameters($t);
die($r) if ($r ne "An");

$t = "Image:Blah1|100PX|Left|";
$r = &images::parseImageParameters($t);
die($r) if ($r ne "");

$t = "Image:Blah1|100PX|Left";
$r = &images::parseImageParameters($t);
die($r) if ($r ne "");

$t = "Image:Blah1";
$r = &images::parseImageParameters($t);
die($r) if ($r ne "");
