use Data::Dumper;
use Test::More tests => 123;
use encoding 'utf-8';

package C;
require Wikiprep::Templates::C;

package PurePerl;
require Wikiprep::Templates::PurePerl;

package main;

use Encode;

sub compare {
	my $list1 = shift;
	my $list2 = shift;
	my $n;

	for($n = 0; $n <= $#$list1; $n ++) {
		is($list1->[$n], $list2->[$n]);
	}
}

my $text;
my @cresult;
my @result;

$text = "";
@cresult = &C::splitOnTemplates($text);
@result = &PurePerl::splitOnTemplates($text);
is($cresult[0], "");
compare(\@result, \@cresult);

$text = "{{1}}";
@cresult = &C::splitOnTemplates($text);
@result = &PurePerl::splitOnTemplates($text);
is($cresult[0], "");
is($cresult[1], "1");
is($cresult[2], "");
compare(\@result, \@cresult);

$text = "a{";
@cresult = &C::splitOnTemplates($text);
@result = &PurePerl::splitOnTemplates($text);
is($cresult[0], "a{");
compare(\@result, \@cresult);

$text = "a{{";
@cresult = &C::splitOnTemplates($text);
@result = &PurePerl::splitOnTemplates($text);
is($cresult[0], "a{{");
compare(\@result, \@cresult);

$text = "a{{b";
@cresult = &C::splitOnTemplates($text);
@result = &PurePerl::splitOnTemplates($text);
is($cresult[0], "a{{b");
compare(\@result, \@cresult);

$text = "a{{b}";
@cresult = &C::splitOnTemplates($text);
@result = &PurePerl::splitOnTemplates($text);
is($cresult[0], "a{{b}");
compare(\@result, \@cresult);

$text = "a{{b}}";
@cresult = &C::splitOnTemplates($text);
@result = &PurePerl::splitOnTemplates($text);
is($cresult[0], "a");
is($cresult[1], "b");
compare(\@result, \@cresult);

$text = "a{{b}}{";
@cresult = &C::splitOnTemplates($text);
@result = &PurePerl::splitOnTemplates($text);
is($cresult[0], "a");
is($cresult[1], "b");
is($cresult[2], "{");
compare(\@result, \@cresult);

$text = "a{{b}}{{";
@cresult = &C::splitOnTemplates($text);
@result = &PurePerl::splitOnTemplates($text);
is($cresult[0], "a");
is($cresult[1], "b");
is($cresult[2], "{{");
compare(\@result, \@cresult);

$text = "a{{b}}{{c";
@cresult = &C::splitOnTemplates($text);
@result = &PurePerl::splitOnTemplates($text);
is($cresult[0], "a");
is($cresult[1], "b");
is($cresult[2], "{{c");
compare(\@result, \@cresult);

$text = "a{{b}}{{c}";
@cresult = &C::splitOnTemplates($text);
@result = &PurePerl::splitOnTemplates($text);
is($cresult[0], "a");
is($cresult[1], "b");
is($cresult[2], "{{c}");
compare(\@result, \@cresult);

$text = "a{{b}}{{c}}";
@cresult = &C::splitOnTemplates($text);
@result = &PurePerl::splitOnTemplates($text);
is($cresult[0], "a");
is($cresult[1], "b");
is($cresult[2], "");
is($cresult[3], "c");
compare(\@result, \@cresult);

$text = "a{{b}}d{{c}}e";
@cresult = &C::splitOnTemplates($text);
@result = &PurePerl::splitOnTemplates($text);
is($cresult[0], "a");
is($cresult[1], "b");
is($cresult[2], "d");
is($cresult[3], "c");
is($cresult[4], "e");
compare(\@result, \@cresult);

$text = "{{{b}}}";
@cresult = &C::splitOnTemplates($text);
@result = &PurePerl::splitOnTemplates($text);
is($cresult[0], "");
is($cresult[1], "{b}");
compare(\@result, \@cresult);

$text = "{{ {{ }} }}";
@cresult = &C::splitOnTemplates($text);
@result = &PurePerl::splitOnTemplates($text);
is($cresult[0], "");
is($cresult[1], " {{ }} ");
compare(\@result, \@cresult);

# WARNING WARNING WARNING This is where C and Perl implementation differ

$text = "{{ {{ }}";
@cresult = &C::splitOnTemplates($text);
@result = &PurePerl::splitOnTemplates($text);
is($cresult[0], "{{ {{ }}");
#compare(\@result, \@cresult);

is($result[0], "{{ ");
is($result[1], " ");

$text = "{{ }} }}";
@cresult = &C::splitOnTemplates($text);
@result = &PurePerl::splitOnTemplates($text);
is($cresult[0], "");
is($cresult[1], " ");
is($cresult[2], " }}");
compare(\@result, \@cresult);

$text = "Tomaž";
@cresult = &C::splitOnTemplates($text);
@result = &PurePerl::splitOnTemplates($text);
is($cresult[0], "Tomaž");
compare(\@result, \@cresult);

is( encode("utf-8", $text), encode("utf-8", $cresult[0]));
is( encode("utf-8", $text), encode("utf-8", $result[0]));

$text = "Toma{{ž}}";
@cresult = &C::splitOnTemplates($text);
@result = &PurePerl::splitOnTemplates($text);
is($cresult[0], "Toma");
is($cresult[1], "ž");
compare(\@result, \@cresult);

# ##################################################################################################

$text = "";
@cresult = &C::splitTemplateInvocation($text);
@result = &PurePerl::splitTemplateInvocation($text);
is($cresult[0], undef);
compare(\@result, \@cresult);

$text = "|";
@cresult = &C::splitTemplateInvocation($text);
@result = &PurePerl::splitTemplateInvocation($text);
is($cresult[0], "");
is($cresult[1], "");
compare(\@result, \@cresult);

$text = "{|";
@cresult = &C::splitTemplateInvocation($text);
@result = &PurePerl::splitTemplateInvocation($text);
is($cresult[0], "{|");
compare(\@result, \@cresult);

$text = "}|";
@cresult = &C::splitTemplateInvocation($text);
@result = &PurePerl::splitTemplateInvocation($text);
is($cresult[0], "}");
is($cresult[1], "");
compare(\@result, \@cresult);

$text = " \t\n";
@cresult = &C::splitTemplateInvocation($text);
@result = &PurePerl::splitTemplateInvocation($text);
is($cresult[0], "");
compare(\@result, \@cresult);

$text = "  |  a  ||   |  b  |  ";
@cresult = &C::splitTemplateInvocation($text);
@result = &PurePerl::splitTemplateInvocation($text);
is($cresult[0], "");
is($cresult[1], "a");
is($cresult[2], "");
is($cresult[3], "");
is($cresult[4], "b");
is($cresult[5], "");
compare(\@result, \@cresult);

$text = "|";
@cresult = &C::splitTemplateInvocation($text);
@result = &PurePerl::splitTemplateInvocation($text);
is($cresult[0], "");
is($cresult[1], "");
compare(\@result, \@cresult);

# ##################################################################################################

my %params;

%params = ();
is( &C::substituteParameter       ("", \%params), "");
is( &PurePerl::substituteParameter("", \%params), "");

%params = ();
is( &C::substituteParameter       ("a", \%params), "");
is( &PurePerl::substituteParameter("a", \%params), "");

%params = ();
is( &C::substituteParameter	  ("a|", \%params), "");
is( &PurePerl::substituteParameter("a|", \%params), "");

%params = ();
is( &C::substituteParameter       ("|", \%params), "");
is( &PurePerl::substituteParameter("|", \%params), "");

%params = ();
is( &C::substituteParameter       ("a|a", \%params), "a");
is( &PurePerl::substituteParameter("a|a", \%params), "a");

%params = ( a => 'b' );
is( &C::substituteParameter       ("a|a", \%params), "b");
is( &PurePerl::substituteParameter("a|a", \%params), "b");

%params = ( a => 'b' );
is( &C::substituteParameter       (" a|a", \%params), "a");
is( &PurePerl::substituteParameter(" a|a", \%params), "a");
