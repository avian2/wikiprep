use Test::More tests => 11;
use Wikiprep::Namespace qw( addNamespace normalizeTitle );

addNamespace("", 0);
addNamespace("Template", 1);
addNamespace("File", 2);

my $a;

$a = "Sandbox"; &normalizeTitle(\$a);
is($a, "Sandbox");

$a = "sandBox"; &normalizeTitle(\$a);
is($a, "SandBox");

$a = ":Sandbox"; &normalizeTitle(\$a);
is($a, "Sandbox");

$a = ": Sandbox"; &normalizeTitle(\$a);
is($a, "Sandbox");

$a = "Sandbox"; &normalizeTitle(\$a, "Template");
is($a, "Template:Sandbox");

$a = "sandbox"; &normalizeTitle(\$a, "Template");
is($a, "Template:Sandbox");

$a = ":sandbox"; &normalizeTitle(\$a, "Template");
is($a, "Sandbox");

$a = "Template:Sandbox"; &normalizeTitle(\$a, "Template");
is($a, "Template:Sandbox");

$a = "A: Sandbox"; &normalizeTitle(\$a);
is($a, "A: Sandbox");

$a = "a: sandbox"; &normalizeTitle(\$a);
is($a, "A: sandbox");

$a = "A: Sandbox"; &normalizeTitle(\$a, "Template");
is($a, "Template:A: Sandbox");
