# vim:sw=2:tabstop=2:expandtab

use strict;

package images;

# Parse image parameters from a link to an image like this:
# [[Image:Wikipedesketch1.png|frame|right|Here is a really cool caption]]

# Note that the anchor text can be on any location, not just after the last |. This means we have to
# check all image parameters and select the one that looks the most like anchor text.
sub parseImageParameters($) {
  my ($imageParameters) = @_;

  my @imageParameters;

  # Store parameters delimited by | into an array.
  while ( $imageParameters =~ s/\|([^|]*)$// ) {
    push @imageParameters, $1;
  }

  my @candidateAnchors;

  for my $parameter (@imageParameters) {
    # A list of valid parameters can be found here:
    # http://en.wikipedia.org/wiki/Wikipedia:Image_markup

    # Ignore size specifications like "250x250px" or "250px"
    if ( $parameter =~ /^\s*[0-9x]+px\s*$/i) {
      next;
    }

    # Location and type specifications
    if ( $parameter =~ /^\s*(?:left|right|center|none|thumb|thumbnail|frame)\s*$/i) {
      next;
    }

    push @candidateAnchors, $parameter;
  }

  if($#candidateAnchors >= 0) {
    # In case image has more than one valid anchor, use the longer one.
    my @sortedCandidateAnchors = sort { length($b) <=> length($a) } @candidateAnchors;
  
    return $sortedCandidateAnchors[0];
  } else {
    return "";
  }
}

1
