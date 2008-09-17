# vim:sw=2:tabstop=2:expandtab

package Wikiprep::utils;

use strict;
use Exporter 'import';
our @EXPORT_OK = qw( trimWhitespaceBothSides encodeXmlChars getLinkIds removeDuplicatesAndSelf );

use Wikiprep::logger qw( msg );

my %XmlEntities = ('&' => 'amp', '"' => 'quot', "'" => 'apos', '<' => 'lt', '>' => 'gt');

# See http://www.perlmonks.org/?node_id=2258 for performance comparisson
sub trimWhitespaceBothSides {
  $_ = shift;
  s/^\s+//;
  s/\s+$//;

  return $_;
}

sub encodeXmlChars(\$) {
  my ($refToStr) = @_;

  $$refToStr =~ s/([&"'<>])/&$XmlEntities{$1};/g;
}

sub getLinkIds(\@\@) {
  my ($refToLinkIds, $refToInternalLinks) = @_;

  for my $link (@$refToInternalLinks) {
    if( defined( $link->{targetId} ) ) {
      push(@$refToLinkIds, $link->{targetId});
    }
  }
}

# If specified, 'elementToRemove' contains an element that needs to be removed as well.
# For links, this ensures that a page does not link to itself. For categories, this
# ensures that a page is not categorized to itself. This parameter is obviously
# irrelevant for filtering URLs.
# 'elementToRemove' must be a numeric value (not string), since we're testing it with '==' (not 'eq')
sub removeDuplicatesAndSelf(\@$) {
  my ($refToArray, $elementToRemove) = @_;

  my %seen = ();
  my @uniq;

  my $item;
  foreach $item (@$refToArray) {
    if ( defined($elementToRemove) && ($item == $elementToRemove) ) {
      &msg("WARNING", "current page links or categorizes to itself - " . 
                              "link discarded ($elementToRemove)");
      next;
    }
    push(@uniq, $item) unless $seen{$item}++;
  }

  # overwrite the original array with the new one that does not contain duplicates
  @$refToArray = @uniq;
}

1
