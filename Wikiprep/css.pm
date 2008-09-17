# vim:sw=2:tabstop=2:expandtab

package Wikiprep::css;

use strict;
use Exporter 'import';
our @EXPORT_OK = qw( removeMetadata );

BEGIN {

my $cssClassesToRemove = "metadata|dablink|sisterproject";

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
