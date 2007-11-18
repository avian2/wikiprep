# vim:sw=2:tabstop=2:expandtab

use strict;

package images;

sub convertGalleryToLink(\$) {
  my ($refToText) = @_;

  # Galleries are delimited with <gallery> tags like this:
  #
  # <gallery>
  # Image:BaseChars.png|Screenshot of Galaksija showing its base character set
  # Image:GraphicChars.png|Screenshot of Galaksija showing its pseudo-graphics character set
  # </gallery>
  #
  # Each line inside tags contains contains an image link with the same basic syntax as normal image
  # links in [[ ... ]] markup.

  1 while ( $$refToText =~ s/<gallery>
                             ([^<]*)
                             <\/gallery>
                            /&convertOneGallery($1)/segx
          );
}

sub convertOneGallery($) {
  my ($galleryText) = @_;

  # Simply enclose each line that starts with Image: in [[ ... ]] and leave the links to be collected by
  # collectInternalLink()

  $galleryText =~ s/^\s*(Image:.*)\s*$/[[\1]]/mig;

  return $galleryText;
}

sub convertImagemapToLink(\$) {
  my ($refToText) = @_;

  # Imagemaps are similar to galleries, except that include extra markup which must be removed.
  #
  # <imagemap>
  # Image:Sudoku dot notation.png|300px
  # # comment
  # circle  320  315 165 [[w:1|1]]
  # circle  750  315 160 [[w:2|2]]
  # circle 1175  315 160 [[w:3|3]]
  # circle  320  750 160 [[w:4|4]]
  # circle  750  750 160 [[w:5|5]]
  # circle 1175  750 160 [[w:6|6]]
  # circle  320 1175 160 [[w:7|7]]
  # circle  750 1175 160 [[w:8|8]]
  # circle 1175 1175 160 [[w:9|9]]
  # default [[w:Number|Number]]
  # </imagemap>
  
  # One line inside tags contains contains an image link with the same basic syntax as normal image
  # links in [[ ... ]] markup.
  #
  # Other lines contain location specification and a link to some other page.

  1 while ( $$refToText =~ s/<imagemap>
                             ([^<]*)      
                             <\/imagemap>
                            /&convertOneImagemap($1)/segx
          );
}

sub convertOneImagemap($) {
  my ($imagemapText) = @_;

  # Convert image specification to a link
  $imagemapText =~ s/^\s*(Image:.*)\s*$/[[\1]]/mig;

  # Remove comments
  $imagemapText =~ s/^\s*#.*$//mig;

  # Remove location specifications
  $imagemapText =~ s/^.*(\[\[.*\]\])\s*$/\1/mig;

  return $imagemapText;
}

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
