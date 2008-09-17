use Data::Dumper;
use Test::More tests => 93;
use encoding 'utf-8';
use Wikiprep::ctemplates;
use Wikiprep::templates; 
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
@cresult = &Wikiprep::ctemplates::splitOnTemplates($text);
@result = &Wikiprep::templates::splitOnTemplates($text);
is($cresult[0], "");
compare(\@result, \@cresult);

$text = "{{1}}";
@cresult = &Wikiprep::ctemplates::splitOnTemplates($text);
@result = &Wikiprep::templates::splitOnTemplates($text);
is($cresult[0], "");
is($cresult[1], "1");
is($cresult[2], "");
compare(\@result, \@cresult);

$text = "a{";
@cresult = &Wikiprep::ctemplates::splitOnTemplates($text);
@result = &Wikiprep::templates::splitOnTemplates($text);
is($cresult[0], "a{");
compare(\@result, \@cresult);

$text = "a{{";
@cresult = &Wikiprep::ctemplates::splitOnTemplates($text);
@result = &Wikiprep::templates::splitOnTemplates($text);
is($cresult[0], "a{{");
compare(\@result, \@cresult);

$text = "a{{b";
@cresult = &Wikiprep::ctemplates::splitOnTemplates($text);
@result = &Wikiprep::templates::splitOnTemplates($text);
is($cresult[0], "a{{b");
compare(\@result, \@cresult);

$text = "a{{b}";
@cresult = &Wikiprep::ctemplates::splitOnTemplates($text);
@result = &Wikiprep::templates::splitOnTemplates($text);
is($cresult[0], "a{{b}");
compare(\@result, \@cresult);

$text = "a{{b}}";
@cresult = &Wikiprep::ctemplates::splitOnTemplates($text);
@result = &Wikiprep::templates::splitOnTemplates($text);
is($cresult[0], "a");
is($cresult[1], "b");
compare(\@result, \@cresult);

$text = "a{{b}}{";
@cresult = &Wikiprep::ctemplates::splitOnTemplates($text);
@result = &Wikiprep::templates::splitOnTemplates($text);
is($cresult[0], "a");
is($cresult[1], "b");
is($cresult[2], "{");
compare(\@result, \@cresult);

$text = "a{{b}}{{";
@cresult = &Wikiprep::ctemplates::splitOnTemplates($text);
@result = &Wikiprep::templates::splitOnTemplates($text);
is($cresult[0], "a");
is($cresult[1], "b");
is($cresult[2], "{{");
compare(\@result, \@cresult);

$text = "a{{b}}{{c";
@cresult = &Wikiprep::ctemplates::splitOnTemplates($text);
@result = &Wikiprep::templates::splitOnTemplates($text);
is($cresult[0], "a");
is($cresult[1], "b");
is($cresult[2], "{{c");
compare(\@result, \@cresult);

$text = "a{{b}}{{c}";
@cresult = &Wikiprep::ctemplates::splitOnTemplates($text);
@result = &Wikiprep::templates::splitOnTemplates($text);
is($cresult[0], "a");
is($cresult[1], "b");
is($cresult[2], "{{c}");
compare(\@result, \@cresult);

$text = "a{{b}}{{c}}";
@cresult = &Wikiprep::ctemplates::splitOnTemplates($text);
@result = &Wikiprep::templates::splitOnTemplates($text);
is($cresult[0], "a");
is($cresult[1], "b");
is($cresult[2], "");
is($cresult[3], "c");
compare(\@result, \@cresult);

$text = "a{{b}}d{{c}}e";
@cresult = &Wikiprep::ctemplates::splitOnTemplates($text);
@result = &Wikiprep::templates::splitOnTemplates($text);
is($cresult[0], "a");
is($cresult[1], "b");
is($cresult[2], "d");
is($cresult[3], "c");
is($cresult[4], "e");
compare(\@result, \@cresult);

$text = "{{{b}}}";
@cresult = &Wikiprep::ctemplates::splitOnTemplates($text);
@result = &Wikiprep::templates::splitOnTemplates($text);
is($cresult[0], "");
is($cresult[1], "{b}");
compare(\@result, \@cresult);

$text = "{{ {{ }} }}";
@cresult = &Wikiprep::ctemplates::splitOnTemplates($text);
@result = &Wikiprep::templates::splitOnTemplates($text);
is($cresult[0], "");
is($cresult[1], " {{ }} ");
compare(\@result, \@cresult);

# WARNING WARNING WARNING This is where C and Perl implementation differ

$text = "{{ {{ }}";
@cresult = &Wikiprep::ctemplates::splitOnTemplates($text);
@result = &Wikiprep::templates::splitOnTemplates($text);
is($cresult[0], "{{ {{ }}");
#compare(\@result, \@cresult);

is($result[0], "{{ ");
is($result[1], " ");

$text = "{{ }} }}";
@cresult = &Wikiprep::ctemplates::splitOnTemplates($text);
@result = &Wikiprep::templates::splitOnTemplates($text);
is($cresult[0], "");
is($cresult[1], " ");
is($cresult[2], " }}");
compare(\@result, \@cresult);

$text = "Tomaž";
@cresult = &Wikiprep::ctemplates::splitOnTemplates($text);
@result = &Wikiprep::templates::splitOnTemplates($text);
is($cresult[0], "Tomaž");
compare(\@result, \@cresult);

is( encode("utf-8", $text), encode("utf-8", $cresult[0]));
is( encode("utf-8", $text), encode("utf-8", $result[0]));

$text = "Toma{{ž}}";
@cresult = &Wikiprep::ctemplates::splitOnTemplates($text);
@result = &Wikiprep::templates::splitOnTemplates($text);
is($cresult[0], "Toma");
is($cresult[1], "ž");
compare(\@result, \@cresult);

# ##################################################################################################

$text = "";
@cresult = &Wikiprep::ctemplates::splitTemplateInvocation($text);
@result = &Wikiprep::templates::splitTemplateInvocation($text);
is($cresult[0], undef);
compare(\@result, \@cresult);

$text = "|";
@cresult = &Wikiprep::ctemplates::splitTemplateInvocation($text);
@result = &Wikiprep::templates::splitTemplateInvocation($text);
is($cresult[0], "");
is($cresult[1], "");
compare(\@result, \@cresult);

$text = "{|";
@cresult = &Wikiprep::ctemplates::splitTemplateInvocation($text);
@result = &Wikiprep::templates::splitTemplateInvocation($text);
is($cresult[0], "{|");
compare(\@result, \@cresult);

$text = "}|";
@cresult = &Wikiprep::ctemplates::splitTemplateInvocation($text);
@result = &Wikiprep::templates::splitTemplateInvocation($text);
is($cresult[0], "}");
is($cresult[1], "");
compare(\@result, \@cresult);
