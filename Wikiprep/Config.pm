# vim:sw=2:tabstop=2:expandtab

package Wikiprep::Config;

use strict;

use vars qw/ %namespaceAliases /;
use vars qw/ %okNamespacesForPrescanning %okNamespacesForTransforming %okNamespacesForInterwikiLinks /;
use vars qw/ $categoryNamespace $templateNamespace $imageNamespace /;

use vars qw/ $relatedWording_Standalone $relatedWording_Inline $relatedWording_Section /;

use vars qw/ $disambigTemplates $disambigTitle /;

use vars qw/ %numberToMonth %monthToNumDays /;

use vars qw/ $maxTemplateRecursionLevels $maxTableRecursionLevels %overrideTemplates /;

$maxTemplateRecursionLevels = 10;
$maxTableRecursionLevels = 5;

# We use a different (and faster) way of recursively including templates than MediaWiki. In most
# cases this produces satisfactory results, however certain templates break our parser by resolving
# to meta characters like {{ and |. These templates are used as hacks around escaping issues in 
# Mediawiki and mostly concern wiki table syntax. Since we ignore content in tables we can safely
# ignore these templates.
#
# See http://meta.wikimedia.org/wiki/Template:!
#
# %overrideTemplates = ('Template:!' => ' ', 'Template:!!' => ' ', 'Template:!-' => ' ',
#                       'Template:-!' => ' ');

%overrideTemplates = ();

my %numMonthToNumDays = ( 1  => 31, 2  => 29, 
                          3  => 31, 4  => 30, 
                          5  => 31, 6  => 30, 
                          7  => 31, 8  => 31, 
                          9  => 30, 10 => 31, 
                          11 => 30, 12 => 31 );

sub init {
	my $settingName = ucfirst( shift );
	my $moduleName = "Wikiprep/Config/$settingName.pm";

	require $moduleName;
	
	# Create a mapping from month name to the number of days in that month 
	# needed by normalizeDates()

	for my $num ( keys(%numMonthToNumDays) ) {
		$monthToNumDays{ $numberToMonth{$num} } = $numMonthToNumDays{$num};
	}
}

1;
