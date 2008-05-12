# vim:sw=2:tabstop=2:expandtab

use strict;

package css;

BEGIN {

my $cssClassesToRemove = "metadata|dablink";

my $cssClassesRegex = qr/
		<div\s[^<>]*class="(?:[^"]*\s)?(?:$cssClassesToRemove)(?:\s[^"]*)?"[^<>]*>
			[^<>]*
		<\/div>
		/ix;


sub removeMetadata(\$) {
  my ($refToText) = @_;

  $$refToText =~ s/$cssClassesRegex/ /sg;
}

}

1
