use Test::Simple tests => 7;
use css;

my ($a);

$a = '<div class="dablink">Blah blah</div>';
&css::removeMetadata(\$a);

ok($a eq " ");

$a = '<div style="display: none;" class="dablink" id="head">Blah blah</div>';
&css::removeMetadata(\$a);

ok($a eq " ");

$a = '<div class="red dablink blue">Blah blah</div>';
&css::removeMetadata(\$a);

ok($a eq " ");

$a = '<div id="dablink">Blah blah</div>';
&css::removeMetadata(\$a);

ok($a eq '<div id="dablink">Blah blah</div>');

$a = 'dablink';
&css::removeMetadata(\$a);

ok($a eq 'dablink');

# These don't work currently

$a = '<div class="dablink"><table>Blah blah</table></div>';
&css::removeMetadata(\$a);

ok($a eq '<div class="dablink"><table>Blah blah</table></div>');

$a = '<table class="dablink">Blah blah</div>';
&css::removeMetadata(\$a);

ok($a eq '<table class="dablink">Blah blah</div>');

