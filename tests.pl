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

$t = "Image:Blah1|10px|";
$r = &images::parseImageParameters($t);
die($r) if ($r ne "");

$t = "Image:Blah1|10px| ";
$r = &images::parseImageParameters($t);
die($r) if ($r ne " ");

$t = <<END
Some text
<gallery>
Image:BaseChars.png|Screenshot of Galaksija showing its base character set
Image:GraphicChars.png|Screenshot of Galaksija showing its pseudo-graphics character set
</gallery>
Some text here
END
;
$r = <<END
Some text
[[Image:BaseChars.png|Screenshot of Galaksija showing its base character set]]
[[Image:GraphicChars.png|Screenshot of Galaksija showing its pseudo-graphics character set]]
Some text here
END
;
&images::convertGalleryToLink(\$t);
die($t) if ($t ne $r);

$t = <<END
Some text
<gallery>

invalid
Image:BaseChars.png|Screenshot of Galaksija showing its base character set [[link]]
Image:GraphicChars.png|Screenshot of Galaksija showing its pseudo-graphics character set
</gallery>
Some text here
END
;
$r = <<END
Some text


invalid
[[Image:BaseChars.png|Screenshot of Galaksija showing its base character set [[link]]]]
[[Image:GraphicChars.png|Screenshot of Galaksija showing its pseudo-graphics character set]]
Some text here
END
;
&images::convertGalleryToLink(\$t);
die($t) if ($t ne $r);

$t = <<END
<imagemap>
Image:Sudoku dot notation.png|300px
# comment
circle  320  315 165 [[w:1|1]]
circle  750  315 160 [[w:2|2]]
circle 1175  315 160 [[w:3|3]]
circle  320  750 160 [[w:4|4]]
circle  750  750 160 [[w:5|5]]
circle 1175  750 160 [[w:6|6]]
circle  320 1175 160 [[w:7|7]]
circle  750 1175 160 [[w:8|8]]
circle 1175 1175 160 [[w:9|9]]
default [[w:Number|Number]]
</imagemap>
END
;

$r = <<END
[[Image:Sudoku dot notation.png|300px]]
[[w:1|1]]
[[w:2|2]]
[[w:3|3]]
[[w:4|4]]
[[w:5|5]]
[[w:6|6]]
[[w:7|7]]
[[w:8|8]]
[[w:9|9]]
[[w:Number|Number]]
END
;
&images::convertImagemapToLink(\$t);
die($t) if ($t ne $r);

use nowiki;

print "Generated unique strings:\n";
print "  ", &nowiki::randomString(), "\n";
print "  ", &nowiki::randomString(), "\n";
print "  ", &nowiki::randomString(), "\n";
print "  ", &nowiki::randomString(), "\n";


$t = <<END
hello<nowiki>, world!</nowiki>
END
;
$r = $t;

my %tok;
&nowiki::extractTags("(<nowiki>.*?</nowiki>)", \$t, \%tok);
&nowiki::replaceTags(\$t, \%tok);

$t = <<END
hello<nowiki>, 
world!</nowiki> nice day
<nowiki>[[not a link]]</nowiki>
\x7fUNIQ1234567812345678
END
;
$r = $t;

%tok = {};

&nowiki::extractTags("(<nowiki>.*?</nowiki>)", \$t, \%tok);
die unless ($t =~ /nice day/);
&nowiki::replaceTags(\$t, \%tok);

die($t) if ($t ne $r);
