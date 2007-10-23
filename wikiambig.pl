###############################################################################
# vim:sw=2:tabstop=2:expandtab
#
# wikiambig.pl - Find disambiguation pages in Wikipedia XML dumps
# Copyright (C) 2007 Tomaz Solc
# Copyright (C) 2007 Evgeniy Gabril
# The author can be contacted by electronic mail at tomaz.solc@tablix.org
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA,
#    or see <http://www.gnu.org/licenses/> and
#    <http://www.fsf.org/licensing/licenses/info/GPLv2.html>
#
###############################################################################


use strict;
use warnings;

use File::Basename;
use Getopt::Long;
use Time::localtime;
use Parse::MediaWikiDump;

my $licenseFile = "COPYING";
my $version = "2.02";

if (@ARGV < 1) {
  &printUsage();
  exit 0;
}

my $file;

my $showLicense = 0;
my $showVersion = 0;

GetOptions('f=s' => \$file,
           'license' => \$showLicense,
           'version' => \$showVersion);

if ($showLicense) {
  if (-e $licenseFile) {
    print "See file $licenseFile for more details.\n"
  } else {
    print "Please see <http://www.gnu.org/licenses/> and <http://www.fsf.org/licensing/licenses/info/GPLv2.html>\n";
  }
  exit 0;
}
if ($showVersion) {
  print "Wikiprep version $version\n";
  exit 0;
}
if (!defined($file)) {
  &printUsage();
  exit 0;
}
if (! -e $file) {
  die "Input file '$file' cannot be opened for reading\n";
}


##### Global variables #####

my %namespaces;

my ($fileBasename, $filePath, $fileSuffix) = fileparse($file, ".xml");
my $disambigPagesFile = "$filePath/$fileBasename.disambig";

# Needed for benchmarking and ETA calculation
my $totalPageCount = 0;
my $totalByteCount = 0;

open(DISAMBIGF, "> $disambigPagesFile") or die "Cannot open $disambigPagesFile";

binmode(DISAMBIGF, ':utf8');

print DISAMBIGF  "# Line format: <Disambig page id>\n\n";

print "Counting pages...\n";

&loadNamespaces();
&prescan();

&transform();

close(DISAMBIGF);

##### Subroutines #####

sub normalizeTitle(\$) {
  my ($refToStr) = @_;

  # remove leading whitespace and underscores
  $$refToStr =~ s/^[\s_]+//;
  # remove trailing whitespace and underscores
  $$refToStr =~ s/[\s_]+$//;
  # replace sequences of whitespace and underscore chars with a single space
  $$refToStr =~ s/[\s_]+/ /g;

  if ($$refToStr =~ /^([^:]*):(\s*)(\S(?:.*))/) {
    my $prefix = $1;
    my $optionalWhitespace = $2;
    my $rest = $3;

    my $namespaceCandidate = $prefix;
    &normalizeNamespace(\$namespaceCandidate); # this must be done before the call to 'isKnownNamespace'
    if ( &isKnownNamespace(\$namespaceCandidate) ) {
      # If the prefix designates a known namespace, then it might follow by optional
      # whitespace that should be removed to get the canonical page name
      # (e.g., "Category:  Births" should become "Category:Births").
      $$refToStr = $namespaceCandidate . ":" . ucfirst($rest);
    } else {
      # No namespace, just capitalize first letter.
      # If the part before the colon is not a known namespace, then we must not remove the space
      # after the colon (if any), e.g., "3001: The_Final_Odyssey" != "3001:The_Final_Odyssey".
      # However, to get the canonical page name we must contract multiple spaces into one,
      # because "3001:   The_Final_Odyssey" != "3001: The_Final_Odyssey".
      $$refToStr = ucfirst($prefix) . ":" .
                   (length($optionalWhitespace) > 0 ? " " : "") . $rest;
    }
  } else {
    # no namespace, just capitalize first letter
    $$refToStr = ucfirst($$refToStr);
  }
}

sub normalizeNamespace(\$) {
  my ($refToStr) = @_;

  $$refToStr = ucfirst( lc($$refToStr) );
}

# Checks if the prefix of the page name before the colon is actually one of the
# 16+2+2 namespaces defined in the XML file.
# Assumption: the argument was already normalized using 'normalizeNamespace'
sub isKnownNamespace(\$) {
  my ($refToStr) = @_;

  defined( $namespaces{$$refToStr} );  # return value
}

sub loadNamespaces() {
  # re-open the input XML file
  my $pages = Parse::MediaWikiDump::Pages->new($file);

  # load namespaces
  my $refNamespaces = $pages->namespaces;

  # namespace names are case-insensitive, so we force them
  # to canonical form to facilitate future comparisons
  my $ns;
  foreach $ns (@$refNamespaces) {
    my @namespaceData = @$ns;
    my $namespaceId   = $namespaceData[0];
    my $namespaceName = $namespaceData[1];
    &normalizeNamespace(\$namespaceName);
    $namespaces{$namespaceName} = $namespaceId;
  }
}

# Count pages
sub prescan() {
  # re-open the input XML file
  my $pages = Parse::MediaWikiDump::Pages->new($file);

  my $counter = 0;
  
  my $page;
  while (defined($page = $pages->page)) {
    my $id = $page->id;

    $counter++;

    $totalPageCount++;
    $totalByteCount+=length(${$page->text});

    if ($counter % 1000 == 0) {
      print "At page id=$id\n";
    }

  }

  print "Total $totalPageCount pages ($totalByteCount bytes)\n";
}

sub transform() {
  # re-open the input XML file
  my $pages = Parse::MediaWikiDump::Pages->new($file);

  my $processedPageCount = 0;
  my $processedByteCount = 0;

  my $startTime = time-1;

  my $page;
  while (defined($page = $pages->page)) {
    my $id = $page->id;

    $processedPageCount++;
    $processedByteCount+=length(${$page->text});

    my $title = $page->title;
    my $text = ${$page->text};

    if ( $text =~ /(\{\{
    			(?:
    				(disambiguation)|
	               		(disambig)|
                       		(dab)|
                       		(hndis)|
                       		(geodis)|
                       		(schooldis)|
                       		(hospitaldis)|
                       		(mathdab)
			)
		\}\})/ix ) {
      # print "BODY $id : $title : $1\n";
      &parseDisambig(\$id, \$text);
    } elsif ( $title =~ /\(disambiguation\)/ ) {
       # print "TITLE $id : $title : $1\n";
      &parseDisambig(\$id, \$text);
    }

    my $nowTime = time;

    my $bytesPerSecond = $processedByteCount/($nowTime-$startTime);
    my $percentDone = 100.0*$processedByteCount/$totalByteCount;
    my $secondsLeft = ($totalByteCount-$processedByteCount)/$bytesPerSecond;

    my $hoursLeft = $secondsLeft/3600;

    printf "At %.1f%% (%.0f bytes/s) ETA %.1f hours\n", $percentDone, $bytesPerSecond, $hoursLeft;
  }
}

sub parseDisambig(\$\$) {
	my ($refToId, $refToText) = @_;

	my @disambigLinks;

	my @lines = split(/\n/, $$refToText);
	my $line;

	for $line (@lines) {
		if ( $line =~ /^\s*(?:
					(\*\*)|
					(\#\#)|
					(\:\#)|
					(\:\*)|
					(\#)|
					(\*)
				)/ix ) {

			@disambigLinks=();

			&extractInternalLinks(\$line, \@disambigLinks);

			&markDisambig($refToId, \@disambigLinks);
		}
	}
}

sub extractInternalLinks(\$\@) {
  my ($refToText, $refToInternalLinksArray) = @_;

  # Link definitions may span over adjacent lines and therefore contain line breaks,
  # hence we use the /s modifier.
  # Occasionally, links are nested, e.g.,
  # [[Image:kanner_kl2.jpg|frame|right|Dr. [[Leo Kanner]] introduced the label ''early infantile autism'' in [[1943]].]]
  # In order to prevent incorrect parsing, e.g., "[[Image:kanner_kl2.jpg|frame|right|Dr. [[Leo Kanner]]",
  # we extract links in several iterations of the while loop, while the link definition requires that
  # each pair [[...]] does not contain any opening braces.

  1 while ( $$refToText =~ s/
                             \[\[
                                   ([^\[]*?)  # the link text can be any chars except an opening bracket,
                                              # this ensures we correctly parse nested links (see comments above)
                             \]\]
                            /&collectInternalLink($1, $refToInternalLinksArray)/segx
          );
}

sub collectInternalLink($$$\@\@) {
  my ($link, $refToInternalLinksArray) = @_;

  my $originalLink = $link;
  my $result = "";

  # strip leading whitespace, if any
  $link =~ s/^\s*//;

  # Link definitions may span over adjacent lines and therefore contain line breaks,
  # hence we use the /s modifier on most matchings.

  # There are some special cases when the link may be preceded with a colon.
  # Known cases:
  # - Linking to a category (as opposed to actually assigning the current article
  #   to a category) is performed using special syntax [[:Category:...]]
  # - Linking to other languages, e.g., [[:fr:Wikipedia:Aide]]
  #   (without the leading colon, the link will go to the side menu
  # - Linking directly to the description page of an image, e.g., [[:Image:wiki.png]]
  # In all such cases, we strip the leading colon.
  if ($link =~ /^
                   :        # colon at the beginnning of the link name
                   (.*)     # the rest of the link text
                $
               /sx) {
    # just strip this initial colon (as well as any whitespace preceding it)
    $link = $1;
  }

  # Alternative text may be available after the pipeline symbol.
  # If the pipeline symbol is only used for masking parts of
  # the link name for presentation, we still consider that the author of the page
  # deemed the resulting text important, hence we always set this variable when
  # the pipeline symbol is present.
  my $alternativeTextAvailable = 0;

  # Some links contain several pipeline symbols, e.g.,
  # [[Image:Zerzan.jpeg|thumb|right|[[John Zerzan]]]]
  # It seems that the extra pipeline symbols are parameters, so we just eliminate them.
  if ($link =~ /^(.*)\|([^|]*)$/s) { # first, extract the link up to the last pipeline symbol
    $link = $1;    # the part before the last pipeline
    $result = $2;  # the part after the last pipeline, this is usually an alternative text for this link

    $alternativeTextAvailable = 1; # pipeline found, see comment above

    # Now check if there are pipeline symbols remaining.
    # Note that this time we're looking for the shortest match,
    # to take the part of the text up to the first pipeline symbol.
    if ($link =~ /^([^|]*)\|(.*)$/s) {
      $link = $1;
      # $2 contains the parameters, which we don't really need
    }

  } else {
    # the link text does not contain the pipeline, so take it as-is
    $result = $link;
  }

  if ($link =~ /^(.*)\#(.*)$/s) {
    # The link contains an anchor, so adjust the link to point to the page as a whole.
    $link = $1;
    my $anchor = $2;
    # Check if the link points to an anchor on the current page, and if so - ignore it.
    if (length($link) == 0 && ! $alternativeTextAvailable) {
      # This is indeed a link pointing to an anchor on the current page.
      # The link is thus cleared, so that it will not be resolved and collected later.
      # For anchors to the same page, discard the leading '#' symbol, and take
      # the rest as the text - but only if no alternative text was provided for this link.
      $result = $anchor;
    }
  }

  &normalizeTitle(\$link);
  push(@$refToInternalLinksArray, $link);

  $result;  #return value
}

sub markDisambig(\$\@) {
	my ($refToDisambigId, $refToTitle) = @_;

	my $titles = join("\t", @$refToTitle); 

	print DISAMBIGF "$$refToDisambigId\t$titles\n";
}

sub printUsage()
{
  print "Wikiprep version $version, Copyright (C) 2007 Evgeniy Gabrilovich\n" .
        "Wikiprep comes with ABSOLUTELY NO WARRANTY; for details type '$0 -license'.\n" .
        "This is free software, and you are welcome to redistribute it\n" .
        "under certain conditions; type '$0 -license' for details.\n" .
        "Type '$0 -version' for version information.\n\n" .
        "Usage: $0 -f <XML file with page dump>\n" .
        "       e.g., $0 -f pages_articles.xml\n\n";
}
