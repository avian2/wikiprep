use Test::Simple tests => 12;
use Wikiprep::images qw( convertGalleryToLink convertImagemapToLink parseImageParameters );

my ($t, $r);
my @t;

@t = split(/\|/, "short|longer|the longest anchor text");
$r = &parseImageParameters(\@t);

ok($r eq "the longest anchor text");

@t = split(/\|/, "240x240px|anchor text");
$r = &parseImageParameters(\@t);

ok($r eq "anchor text");

@t = split(/\|/, "100px|left|an");
$r = &parseImageParameters(\@t);

ok($r eq "an");

@t = split(/\|/, "100PX|Left|An");
$r = &parseImageParameters(\@t);

ok($r eq "An");

@t = split(/\|/, "100PX|Left|");
$r = &parseImageParameters(\@t);

ok($r eq "");

@t = split(/\|/, "100PX|Left");
$r = &parseImageParameters(\@t);

ok($r eq "");

@t = split(/\|/, "");
$r = &parseImageParameters(\@t);
ok($r eq "");

@t = split(/\|/, "10px|");
$r = &parseImageParameters(\@t);
ok($r eq "");

@t = split(/\|/, "10px| ");
$r = &parseImageParameters(\@t);
ok($r eq " ");

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
&convertGalleryToLink(\$t);
ok($r eq $t);

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
&convertGalleryToLink(\$t);
ok($r eq $t);

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
&convertImagemapToLink(\$t);
ok($r eq $t);
