use Test::Simple tests => 4;
use templates;

my $r;

$text = "{{{1}}}";

$paramHash = { '1' => 'a', '2' => 'b', '3' => 'c' };

&templates::templateParameterRecursion(\$text, $paramHash, 1);

ok($text eq "a");


$text = "Hello, {{#if:blah|true|}}} {{{1|{{#if:{{{2}}}|{{{2}}}|{{#if:{{{3}}}|some more}}}} }}}! {{#if:{{{3|\n}}}|{{blah}}|{{blah2}}}}";

&templates::templateParameterRecursion(\$text, $paramHash, 1);

ok($text eq "Hello, {{#if:blah|true|}}} a! {{#if:c|{{blah}}|{{blah2}}}}");


$paramHash = { '2' => 'b', '3' => 'c' };

$text = "Hello, {{#if:blah|true|}}} {{{1|{{#if:{{{2}}}|{{{2}}}|{{#if:{{{3}}}|some more}}}} }}}! {{#if:{{{3|\n}}}|{{blah}}|{{blah2}}}}";

&templates::templateParameterRecursion(\$text, $paramHash, 1);

ok($text eq "Hello, {{#if:blah|true|}}} {{#if:b|b|{{#if:c|some more}}}} ! {{#if:c|{{blah}}|{{blah2}}}}");


$text = ':\'\'Further information: [[{{{1|[[Example]]}}}]]{{#if: {{{3|}}}|,}}{{#if: {{{2{{{3|}}}|}}}|&amp;nbsp;and}}';

$paramHash = { '1' => 'Foo' };

&templates::templateParameterRecursion(\$text, $paramHash, 1);

ok($text eq ":''Further information: [[Foo]]{{#if: |,}}{{#if: |&amp;nbsp;and}}");
