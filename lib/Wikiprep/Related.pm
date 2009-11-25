# vim:sw=2:tabstop=2:expandtab

package Wikiprep::Related;

use strict;
use warnings;

use Exporter 'import';

use Wikiprep::Config;
use Wikiprep::Link qw( extractWikiLinks );
use Wikiprep::utils qw( getLinkIds removeDuplicatesAndSelf );

use Log::Handler wikiprep => 'LOG';

our @EXPORT_OK = qw( identifyRelatedArticles );

# There are 3 kinds of related links that we look for:
# 1) Standalone (usually, at the beginning of the article or a section of it)
#    Ex: Main articles: ...
# 2) Inlined - text in parentheses inside the body of the article
#    Ex: medicine (see also: [[Health]])
# 3) Dedicated section
#    Ex: == See also ==
sub identifyRelatedArticles(\%) {
  my ($page) = @_;

  my $id = $page->{id};

  # We split the text into a set of lines. This also creates a copy of the original text -
  # this is important, since the function 'extractWikiLinks' modifies its argument,
  # so we'd better use it on a copy of the real article body.
  my @text = split("\n", $page->{text});
  my $line;

  my @relatedInternalLinks;

  # Standalone
  foreach $line (@text) {
    # We require that stanalone designators occur at the beginning of the line
    # (after at most a few characters, such as a whitespace or a colon),
    # and not just anywhere in the line. Otherwise, we would collect as related
    # those links that just happen to occur in the same line with an unrelated
    # string that represents a standalone designator.
    my $relatedRegex = $Wikiprep::Config::relatedWording_Standalone;
    if ($line =~ /^(?:.{0,5})($relatedRegex.*)$/) {
      my $str = $1; # We extract links from the rest of the line
      LOG->debug("Related(S): $id => $str");
      &extractWikiLinks(\$str, \@relatedInternalLinks);
    }
  }

  # Inlined (in parentheses)
  foreach $line (@text) {
    my $relatedRegex = $Wikiprep::Config::relatedWording_Inline;
    while ($line =~ /\((?:\s*)($relatedRegex.*?)\)/g) {
      my $str = $1;
      LOG->debug("Related(I): $id => $str");
      &extractWikiLinks(\$str, \@relatedInternalLinks);
    }
  }

  # Section
  # Sections can be at any level - "==", "===", "====" - it doesn't matter,
  # so it suffices to look for two consecutive "=" signs
  my $relatedSectionFound = 0;
  foreach $line (@text) {
    if ($relatedSectionFound) { # we're in the related section now
      if ($line =~ /==(?:.*?)==/) { # we just encountered the next section - exit the loop
        last;
      } else { # collect the links from the current line
        LOG->debug("Related(N): $id => $line");
        # 'extractWikiLinks' may modify its argument ('$line'), but it's OK
        # as we do not do any further processing to '$line' or '@text'
        &extractWikiLinks(\$line, \@relatedInternalLinks);
      }
    } else { # we haven't yet found the related section
      if ($line =~ /==(.*?)==/) { # found some section header - let's check it
        my $sectionHeader = $1;
        my $relatedRegex = $Wikiprep::Config::relatedWording_Section;
        if ($sectionHeader =~ /$relatedRegex/) {
          $relatedSectionFound = 1;
          next; # proceed to the next line
        } else {
          next; # unrelated section - just proceed to the next line
        }
      } else {
        next; # just proceed to the next line - nothing to do
      }
    }
  }

  $page->{relatedArticles} = [];

  &getLinkIds($page->{relatedArticles}, \@relatedInternalLinks);
  &removeDuplicatesAndSelf($page->{relatedArticles}, $page->{id});
}

1;
