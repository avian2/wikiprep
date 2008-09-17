use Test::More tests => 18;
use Wikiprep::templates qw( templateParameterRecursion splitOnTemplates parseTemplateInvocation );

my $r;

$text = "{{{1}}}";

$paramHash = { '1' => 'a', '2' => 'b', '3' => 'c' };

&templateParameterRecursion(\$text, $paramHash, 1);

ok($text eq "a");


$text = "Hello, {{#if:blah|true|}}} {{{1|{{#if:{{{2}}}|{{{2}}}|{{#if:{{{3}}}|some more}}}} }}}! {{#if:{{{3|\n}}}|{{blah}}|{{blah2}}}}";

&templateParameterRecursion(\$text, $paramHash, 1);

ok($text eq "Hello, {{#if:blah|true|}}} a! {{#if:c|{{blah}}|{{blah2}}}}");


$paramHash = { '2' => 'b', '3' => 'c' };

$text = "Hello, {{#if:blah|true|}}} {{{1|{{#if:{{{2}}}|{{{2}}}|{{#if:{{{3}}}|some more}}}} }}}! {{#if:{{{3|\n}}}|{{blah}}|{{blah2}}}}";

&templateParameterRecursion(\$text, $paramHash, 1);

ok($text eq "Hello, {{#if:blah|true|}}} {{#if:b|b|{{#if:c|some more}}}} ! {{#if:c|{{blah}}|{{blah2}}}}");


$text = ':\'\'Further information: [[{{{1|[[Example]]}}}]]{{#if: {{{3|}}}|,}}{{#if: {{{2{{{3|}}}|}}}|&amp;nbsp;and}}';

$paramHash = { '1' => 'Foo' };

&templateParameterRecursion(\$text, $paramHash, 1);

ok($text eq ":''Further information: [[Foo]]{{#if: |,}}{{#if: |&amp;nbsp;and}}");

# parseTemplateInvocation

$text = "simple|a|b=c";
$name = '';
%paramHash = ();

&parseTemplateInvocation(\$text, \$name, \%paramHash);
is($name, "simple");
is($paramHash{'=1='}, "a");
is($paramHash{'=2='}, "b=c");
is($paramHash{'1'}, "a");
is($paramHash{'b'}, "c");

$text = "complex|[[link|anchor]]|{{nested|{{template|p}}\n|blah}}|bare_param";
$name = '';
%paramHash = ();

&parseTemplateInvocation(\$text, \$name, \%paramHash);
is($name, "complex");
is($paramHash{'=1='}, "[[link|anchor]]");
is($paramHash{'=2='}, "{{nested|{{template|p}}\n|blah}}");
is($paramHash{'=3='}, "bare_param");
is($paramHash{'1'}, "[[link|anchor]]");
is($paramHash{'2'}, "{{nested|{{template|p}}\n|blah}}");
is($paramHash{'3'}, "bare_param");

$text = "Infobox_University\n|name          = Uppsala University\n|native_name   = Uppsala universitet\n|latin_name    = Universitas Regia Upsaliensis'', also ''Academia Regia Upsaliensis\n|image_name    = Uppsala University seal.png\n|motto         = Gratiae veritas naturae ([[Latin]])\n|mottoeng      = Truth through God's mercy and nature\n|established   = 1477\n|type          = [[Public university|public]]\n|city          = {{Flagicon|Sweden}} [[Uppsala]]\n|country       = [[Sweden]]\n|endowment = 4,319 million [[SEK]] per year ''(2007)'' &lt;/br&gt; (ca. 460 million [[Euro|EUR]] or 715 million [[US dollars|USD]])&lt;ref&gt;[http://info.uu.se/uadm/dokument.nsf/enhet/B56328B60271A22CC1256F400047D809/\$file/AR07.pdf Årsredovisning 2007&quot;&lt;/ref&gt;\n|enrollment    = 30,450&lt;ref&gt;Högskoleverket: [http://www.hsv.se/download/18.5b73fe55111705b51fd80004587/0733R.pdf Universitet &amp; Högskolor. Högskoleverkets årsrapport 2007] ISSN 1400-948X&lt;/ref&gt;\n|undergrad     = \n|postgrad      =\n|doctoral      = 2,400\n|staff         = 6,000 &lt;/br&gt; (3,800 teaching)\n|head_label    = [[Rector magnificus]] and [[Vice Chancellor]]\n|head          = Prof. [[Anders Hallberg]]\n|campus        =\n|colours       = {{color box|#990000}} {{color box|#FFFFFF}} [[Maroon (color)|maroon]], [[White (color)|white]]\n|mascot        =\n|affiliations  = [[Coimbra Group]]&lt;br\&gt; [[European University Association|EUA]]\n|free_label    =\n|free          =\n|website       = http://www.uu.se/\n";
$name = '';
%paramHash = ();

&parseTemplateInvocation(\$text, \$name, \%paramHash);
is($name, "Infobox_University\n");

# There is an unmatched [ in there that breaks template parsing.
#is($paramHash{'website'}, 'http://www.uu.se');
is($paramHash{'website'}, undef);
