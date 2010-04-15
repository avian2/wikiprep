use Test::More tests => 17;
use Wikiprep::Namespace qw( loadNamespaces normalizeTitle );

loadNamespaces(undef, ["", "Template", "File"]);

my $a;

$a = "Sandbox"; &normalizeTitle(\$a);
is($a, "Sandbox");

$a = " Sandbox "; &normalizeTitle(\$a);
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

$a = "Template: A"; &normalizeTitle(\$a, "Template");
is($a, "Template:A");

$a = ":Template: A"; &normalizeTitle(\$a, "Template");
is($a, "Template: A");

$a = "Template: A"; &normalizeTitle(\$a);
is($a, "Template:A");

$a = ":Template: A"; &normalizeTitle(\$a);
is($a, "Template:A");

$a = "Kitedge.jpg\x{200e}"; &normalizeTitle(\$a);
is($a, "Kitedge.jpg");
