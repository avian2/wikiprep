use Test::More tests => 20;
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

# parseTemplateInvocation

$text = "simple|a|b=c";
$name = '';
%paramHash = ();

&templates::parseTemplateInvocation(\$text, \$name, \%paramHash);
is($name, "simple");
is($paramHash{'=1='}, "a");
is($paramHash{'=2='}, "b=c");
is($paramHash{'1'}, "a");
is($paramHash{'b'}, "c");

$text = "complex|[[link|anchor]]|{{nested|{{template|p}}\n|blah}}|bare_param";
$name = '';
%paramHash = ();

&templates::parseTemplateInvocation(\$text, \$name, \%paramHash);
is($name, "complex");
is($paramHash{'=1='}, "[[link|anchor]]");
is($paramHash{'=2='}, "{{nested|{{template|p}}\n|blah}}");
is($paramHash{'=3='}, "bare_param");
is($paramHash{'1'}, "[[link|anchor]]");
is($paramHash{'2'}, "{{nested|{{template|p}}\n|blah}}");
is($paramHash{'3'}, "bare_param");

# splitTemplateInclude

$text = 'text{{template}}text';
is(join(':', &templates::splitTemplateInclude(\$text)), 
   "text:{{template}}:text");

$text = 'text{{template|{{1}}|{{2|{{3}}}}}}text';
is(join(':', &templates::splitTemplateInclude(\$text)), 
   "text:{{template|{{1}}|{{2|{{3}}}}}}:text");

$text = 'text{{template|{{1}}|{{2|{{3}}}}}}';
is(join(':', &templates::splitTemplateInclude(\$text)), 
   "text:{{template|{{1}}|{{2|{{3}}}}}}");

$text = 'text{{template|{{1}}|{{2|{{3}}}}}';
is(join(':', &templates::splitTemplateInclude(\$text)), 
   "text{{template|{{1}}|{{2|{{3}}}}}");
