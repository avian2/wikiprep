# vim:sw=2:tabstop=2:expandtab

package Wikiprep::Disambig;

use strict;
use Exporter 'import';

require Wikiprep::Link;
Wikiprep::Link->import qw/ extractWikiLinks /;

our @EXPORT_OK = qw( isDisambiguation parseDisambig );

sub isDisambiguation($) {
  my ($page) = @_;

  my $result = 0;

  my $disambigTemplates = $Wikiprep::Config::disambigTemplates;
  my $disambigTitle = $Wikiprep::Config::disambigTitle;

  if ( ${$page->text} =~ /\{\{\s*$disambigTemplates\s*(?:\|.*)?\s*\}\}/ix ) {
    $result = 1;
  } elsif ( $page->title =~ /$disambigTitle/ix ) {
    $result = 1;
  }

  return $result;
}

sub parseDisambig(\%) {
	my ($page) = @_;

  $page->{disambigLinks} = [];

	for my $line ( split(/\n/, $page->{text}) ) {

		if ( $line =~ /^\s*(?:
					                (\*\*)|
					                (\#\#)|
                          (\:\#)|
                          (\:\*)|
                          (\#)|
                          (\*)
                        )/ix ) {

      my @disambigLinks;

      &extractWikiLinks(\$line, \@disambigLinks);

      push(@{$page->{disambigLinks}}, \@disambigLinks)
		}
	}
}

1;
