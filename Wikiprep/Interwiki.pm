# vim:sw=2:tabstop=2:expandtab

package Wikiprep::Interwiki;

use strict;
use Exporter 'import';

our @EXPORT_OK = qw( parseInterwiki );

my $interwikiRegex;

{
  my $interwikiRegexS = join('|', @$Wikiprep::Config::interwikiList);
  $interwikiRegex = qr/^(?:$interwikiRegexS)/i;
}

sub parseInterwiki($)
{
	my ( $link ) = @_;

	my ( $wikiName, $title ) = split(/:/, $link, 2);
	if( defined( $title ) and length( $title ) > 0 and $wikiName =~ /$interwikiRegex/i ) {
		return $wikiName, $title;
	} else {
		return;
	}
}

1;
