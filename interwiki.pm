# vim:sw=2:tabstop=2:expandtab

use strict;
use File::Path;

package interwiki;

# Interwiki links are links to another wiki (e. g. from Wikipedia article to a MemoryAlpha article)
# that appear as internal links in the browser. Syntax is similar to MediaWiki namespaces: 
# for example [[MemoryAlpha:Test]] or [[MemoryAlpha:Category:Test]].

# See http://meta.wikimedia.org/wiki/Interwiki_map for a comprehensive list of possible destinations. 

# Only a few largest wikis are enabled here for performance reasons

BEGIN {

my $interwikiList = [
		"Wookieepedia",
		"MemoryAlpha",
		"WoWWiki",
		"MarvelDatabase",
		"DCDatabase",
          ];

sub prepare(\$) {
  my ($refToInterwikiDir) = @_;

  File::Path::rmtree($$refToInterwikiDir, 0, 0);
  mkdir($$refToInterwikiDir);

  for my $wiki ( @$interwikiList ) {
	  $wiki = lc( $wiki );
	  open( INTERF, ">$$refToInterwikiDir/$wiki" );
    print( INTERF "# Line format: <Source page id>  <Target page title>\n\n\n" );
	  close( INTERF );
  }
}

my $interwikiRegexS = join('|', @$interwikiList);
my $interwikiRegex = qr/^(?:$interwikiRegexS)/i;

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

}

1
