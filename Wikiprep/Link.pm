# vim:sw=2:tabstop=2:expandtab

package Wikiprep::Link;

use strict;
use warnings;

use Exporter 'import';
use Hash::Util qw( lock_hash );

use Wikiprep::Namespace qw( normalizeTitle isNamespaceOk isTitleOkForLocalPages resolveNamespaceAliases );
use Wikiprep::images qw( parseImageParameters );

require Wikiprep::Interwiki;
Wikiprep::Interwiki->import qw/ parseInterwiki /;

require Wikiprep::Templates;

use Log::Handler wikiprep => 'LOG';

our @EXPORT_OK = qw( %title2id %redir resolveLink parseRedirect extractWikiLinks );

# The following dictionaries are populated during prescan with page titles 
# and are read-only during transform.

# Mapping from normalized page title to page ID
our %title2id;

# Mapping from source page title to destination page title.
our %redir;

# These variables change during transform

# Mapping from normalized page title to page ID (for "local" page IDs added by Wikiprep)
my %localTitle2id;

# ID assigned to the next local page (always larger than the largest ID in the dump)
my $nextLocalID = 0;

# Page title and redirects prescan
# ===========================================================================================================

sub prescan {
    my ($refToTitle, $refToId, $mwpage) = @_;
    
    # During prescan set nextLocalID to be greater than any encountered Wikipedia page ID
    if ($$refToId >= $nextLocalID) {
      $nextLocalID = $$refToId + 1;
    }

    if (length($$refToTitle) == 0) {
      # This is a defense against pages whose title only contains UTF-8 chars that
      # are reduced to an empty string. Right now I can think of one such case -
      # <C2><A0> which represents the non-breaking space. In this particular case,
      # this page is a redirect to [[Non-nreaking space]], but having in the system
      # a redirect page with an empty title causes numerous problems, so we'll live
      # happier without it.
      LOG->debug("skipping page with empty title ($$refToId)");
      return;
    }

    if ( ! &isNamespaceOk($mwpage->namespace, \%Wikiprep::Config::okNamespacesForPrescanning) ) {
      return; # we're only interested in certain namespaces
    }
    
    # if we get here, then either the page belongs to the main namespace OR
    # it belongs to one of the namespaces we're interested in
    
    if ( exists($title2id{$$refToTitle}) ) {

      # A page could have been encountered before with a different spelling.
      # Examples: &nbsp; = <C2><A0> (nonbreakable space), &szlig; = <C3><9F> (German Eszett ligature)
      LOG->warning("title $$refToTitle already encountered before (ID $$refToId)");
      return;
    }

    my $redirect = &parseRedirect($mwpage);
    if (defined($redirect)) {
      &normalizeTitle(\$redirect);
      
      # again, same precaution here - see comments above
      return 1 if (length($redirect) == 0); 
      $redir{$$refToTitle} = $redirect;

      # nothing more to do for redirect pages
      return;
    }

    $title2id{$$refToTitle} = $$refToId;

    return 1;
}

sub prescanFinished {
  # Prevent modifications to hashes after prescan
	lock_hash( %title2id );
  lock_hash( %redir );

	my $numTitles = scalar( keys(%title2id) );
	LOG->notice("Loaded $numTitles titles");

  my $numRedirects = scalar( keys(%redir) );
  LOG->notice("Loaded $numRedirects redirects");
}

# Redirect page parsing
# ===========================================================================================================

# The correct form to create a redirect is #REDIRECT [[ link ]],
# and function 'Parse::MediaWikiDump::page->redirect' only supports this form.
# However, it seems that Wikipedia can also tolerate a variety of other forms, such as
# REDIRECT|REDIRECTS|REDIRECTED|REDIRECTION, then an optional ":", optional "to" or optional "=".
# Therefore, we use our own function to handle these cases as well.
# If the page is a redirect, the function returns the title of the target page;
# otherwise, it returns 'undef'.
sub parseRedirect($) {
  my ($mwpage) = @_;

  # quick check
  return if ( ${$mwpage->text} !~ /^#REDIRECT/i );

  if ( ${$mwpage->text} =~ m{^\#REDIRECT         # Redirect must start with "#REDIRECT"
                                                 #   (the backslash is needed before "#" here, because
                                                 #    "#" has special meaning with /x modifier)
                             (?:S|ED|ION)?       # The word may be in any of these forms,
                                                 #   i.e., REDIRECT|REDIRECTS|REDIRECTED|REDIRECTION
                             (?:\s*)             # optional whitespace
                             (?: :|\sTO|=)?      # optional colon, "TO" or "="
                                                 #   (in case of "TO", we expect a whitespace before it,
                                                 #    so that it's not glued to the preceding word)
                             (?:\s*)             # optional whitespace
                             \[\[([^\]]*)\]\]    # the link itself
                            }ix ) {              # matching is case-insensitive, hence /i
    my $target = $1;

    if ($target =~ /^(.*)#(?:.*)$/) {
      # The link contains an anchor. Anchors are not allowed in REDIRECT pages, and therefore
      # we adjust the link to point to the page as a whole (that's how Wikipedia works).
      $target = $1;
    }

    return $target;
  }

  # OK, it's probably either a malformed redirect link, or something else
  return;
}

# Internal link parsing
# ===========================================================================================================

# Maps a title into the id, and performs redirection if necessary.
# Assumption: the argument was already normalized using 'normalizeTitle'
sub resolveLink(\$) {
  my ($refToTitle) = @_;

  # safety precaution
  return if (length($$refToTitle) == 0);

  my $targetId; # result
  my $targetTitle = $$refToTitle;

  if ( exists($redir{$targetTitle}) ) { # this link is a redirect
    $targetTitle = $redir{$targetTitle};

    # check if this is a double redirect
    if ( exists($redir{$targetTitle}) ) {
      my $secondRedirect = $redir{$targetTitle};
      LOG->info("link '$$refToTitle' caused double redirection and was ignored: '" .
                      "$$refToTitle' -> '$targetTitle' -> '$secondRedirect'");
      $targetTitle = undef; # double redirects are not allowed and are ignored
    } else {
      LOG->debug("link '$$refToTitle' was redirected to '$targetTitle'");
    }
  }

  if ( defined($targetTitle) ) {
    if ( exists($title2id{$targetTitle}) ) {

      $targetId = $title2id{$targetTitle};

    } else {
      
      # Among links to uninteresting namespaces this also ignores links that point to articles in 
      # different language Wikipedias. We aren't interested in these links (yet), plus ignoring them 
    	# significantly reduces memory usage.

      if ( &isTitleOkForLocalPages(\$targetTitle) ) {

        if ( exists($localTitle2id{$targetTitle}) ) {
          $targetId = $localTitle2id{$targetTitle};
        } else {

          $targetId = $nextLocalID;
          $nextLocalID++;

          $localTitle2id{$targetTitle} = $targetId;

          $main::out->newLocalID( $targetId, $targetTitle );

          LOG->debug("link '$$refToTitle' cannot be matched to an known ID, assigning local ID");
        }
      } else {
        LOG->info("link '$$refToTitle' was ignored");
      }
    }
    return $targetId;
  } else {
    return;
  }
}

# Collects only links that do not point to a template (which besides normal and local pages
# also have an ID in %title2id hash).
sub resolvePageLink(\$) {
  my ($refToTitle) = @_;

  my $targetId = &resolveLink($refToTitle);
  if ( defined($targetId) ) {
    if ( exists($Wikiprep::Templates::templates{$targetId}) ) {
      LOG->info("ignoring link to a template '$$refToTitle'");
      return;
    }
  } else {
    # Some cases in this category that obviously won't be resolved to legal ids:
    # - Links to namespaces that we don't currently handle
    #   (other than those for which 'isNamespaceOK' returns true);
    #   media and sound files fall in this category
    # - Links to other languages, e.g., [[de:...]]
    # - Links to other Wiki projects, e.g., [[Wiktionary:...]]
    LOG->info("unknown link '$$refToTitle'");
  }

  return $targetId;
}

my $internalLinkRegex = qr/
                             (\w*)            # words may be glued to the beginning of the link,
                                              # in which case they become part of the link
                                              # e.g., "ex-[[Giuseppe Mazzini|Mazzinian]] "
                             \[\[
                                   ([^\[]*?)  # the link text can be any chars except an opening bracket,
                                              # this ensures we correctly parse nested links 
                                              # (see comments above)
                             \]\]
                             (\w*)            # words may be glued to the end of the link,
                                              # in which case they become part of the link
                                              # e.g., "[[public transport]]ation"
                         /sx;

sub extractWikiLinks(\$\@$\@$) {
  my ($refToText, $refToAnchorTextArray, $refToInterwikiLinksArray) = @_;

  # For each internal link outgoing from the current article we create an entry in
  # the AnchorTextArray (a reference to an anonymous hash) that contains target id and anchor 
  # text associated with it.
  #
  # This way we can have more than one anchor text per link

  # Link definitions may span over adjacent lines and therefore contain line breaks,
  # hence we use the /s modifier.
  # Occasionally, links are nested, e.g.,
  # [[Image:kanner_kl2.jpg|frame|right|Dr. [[Leo Kanner]] introduced the label ''early infantile autism'' in [[1943]].]]
  # In order to prevent incorrect parsing, e.g., "[[Image:kanner_kl2.jpg|frame|right|Dr. [[Leo Kanner]]",
  # we extract links in several iterations of the while loop, while the link definition requires that
  # each pair [[...]] does not contain any opening braces.
  
  1 while ( $$refToText =~ s/$internalLinkRegex/&collectWikiLink($1, $2, $3, 
                                                                     $refToAnchorTextArray, 
                                                                     $refToInterwikiLinksArray,
                                                                     $-[0])/eg );
}

sub collectWikiLink($$$\@\@$) {
  my ($prefix, $link, $suffix, $refToAnchorTextArray, $refToInterwikiLinksArray,
      $linkLocation) = @_;

  my $originalLink = $link;
  my $result = "";

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

  # just strip this initial colon (as well as any whitespace preceding it)
  $link =~ s/^\s*:?//;
  
  # Bail out if empty link
  return "" unless $link;

  &resolveNamespaceAliases(\$link);

  # Alternative text may be available after the pipeline symbol.
  # If the pipeline symbol is only used for masking parts of
  # the link name for presentation, we still consider that the author of the page
  # deemed the resulting text important, hence we always set this variable when
  # the pipeline symbol is present.
  my $alternativeTextAvailable = 0;

  my $interwikiRecognized = 0;
  my $interwikiTitle;

  my $imageNamespace = $Wikiprep::Config::imageNamespace;
  my $isImageLink = ($link =~ /^$imageNamespace:/);

  # "-1" parameter permits empty trailing fields (important for pipeline masking)
  my @pipeFields = split(/\|/, $link, -1);

  # Text before the first "|" symbol contains link destination.
  $link = shift(@pipeFields);
  
  # Bail out if empty link
  return "" unless $link;

  # If the link contains a section reference, adjust the link to point to the page as a whole and
  # extract the section
  my $section;

  ( $link, $section ) = split(/#/, $link, 2);
  if ( defined($section) ) {

    # Check if the link points to a section on the current page, and if so - ignore it.
    if (length($link) == 0 && ! $alternativeTextAvailable) {
      # This is indeed a link pointing to an section on the current page.
      # The link is thus cleared, so that it will not be resolved and collected later.
      # For section links to the same page, discard the leading '#' symbol, and take
      # the rest as the text - but only if no alternative text was provided for this link.
      $result = $section;
    }
  }
  
  if ($isImageLink) {
    # Image links have to be parsed separately, because anchors can contain parameters (size, type, etc.)
    # which we exclude in a separate function.
    $result = &parseImageParameters(\@pipeFields);

    if( length($result) > 0 ) {
      $alternativeTextAvailable = 1;
    } 
  } else {
    # Check if this is an interwiki link.
    my $wikiName;
    ( $wikiName, $interwikiTitle ) = &parseInterwiki($link);
    
    if( defined( $wikiName ) ) {
      $wikiName = lc($wikiName);

      my $normalizedTitle = $interwikiTitle;
      &normalizeTitle(\$normalizedTitle);

      $interwikiRecognized = 1;

      if( defined( $refToInterwikiLinksArray ) ) {
        push( @$refToInterwikiLinksArray, { targetWiki => $wikiName, targetTitle => $normalizedTitle } );
      }
    }

    # Extract everything after the last pipeline symbol. Normal pages shouldn't have more than one
    # pipeline symbol, but remove extra pipes in case of broken or unknown new markup. Discard
    # all text before the last pipeline.
    $result = pop(@pipeFields);

    if( defined($result) ) {

      # pipeline found, see comment above
      $alternativeTextAvailable = 1; 

      if( length($result) == 0 ) {
        # Pipeline found, but no text follows.

        if( $interwikiRecognized ) {
          # For interwiki links, pipeline masking is performed simply by using the page title
          # instead of the complete link.
          $result = $interwikiTitle;
        } elsif ( not defined($section) ) {
          # If the "|" symbol is not followed by some text, then it masks the namespace
          # as well as any text in parentheses at the end of the link title.
          # However, pipeline masking is only invoked if the link does not contain a section 
          # reference, hence the additional condition in the 'if' statement.
          &performPipelineMasking(\$link, \$result);
        } else {
          # If the link contains an anchor, then masking is not invoked, and we take the entire link
          $result = $link;
        }
      }
    } else {
      # the link text does not contain the pipeline, so take it as-is
      $result = $link;
    }
  }

  # Now collect the link, or links if the original link is in the date format
  # and specifies both day and year. In the latter case, the function for date
  # normalization may also modify the link text ($result), and may collect more
  # than one link (one for the day, another one for the year).
  my $dateRecognized = 0;

  my $targetId;

  # Alternative text (specified after pipeline) blocks normalization of dates.
  # We also perform a quick check - if the link does not start with a digit,
  # then it surely does not contain a date
  if ( ( !$interwikiRecognized ) and ( !$alternativeTextAvailable ) and ( $link =~ /^\d/ ) ) {
    $dateRecognized = &normalizeDates(\$link, \$result, \$targetId, $refToAnchorTextArray, $linkLocation);
  }

  # If a date (either day or day + year) or interwiki link was recognized, then no further
  # processing is necessary
  if (! $dateRecognized and ! $interwikiRecognized ) {
    &normalizeTitle(\$link);

    $targetId = &resolvePageLink(\$link);

    # Wikipedia pages contain many links to other Wiki projects (especially Wikipedia in
    # other languages). While these links are not resolved to valid pages, we also want
    # to ignore their text. However, simply discarding the text of all links that cannot
    # be resolved would be overly aggressive, as authors frequently define phrases as links
    # to articles that don't yet exist, in the hope that they will be added later.
    # Therefore, we formulate the following conditions that must hold simultaneously
    # for discarding the text of a link:
    # 1) the link was not resolved to a valid id
    # 2) the link does not contain alternative text (if it did, then the text is probably
    #    important enough to be retained)
    # 3) the link contains a colon - this is a very simple heuristics for identifying links to
    #    other Wiki projects, other languages, or simply other namespaces within current Wikipedia.
    #    While this method is not fool-proof (there are regular pages in the main namespace
    #    that contain a colon in their title), we believe this is a reasonable tradeoff.
    if ( !defined($targetId) && ! $alternativeTextAvailable && $link =~ /:/ ) {
      $result = "";
      LOG->info("Discarding text for link '$originalLink'");
    } else {
      # finally, add the text originally attached to the left and/or to the right of the link
      # (if the link represents a date, then it has not text glued to it, so it's OK to only
      # use the prefix and suffix here)

      # But we only do this if it's not an image link. Anchor text for image links is used as
      # image caption.
      if ( ! $isImageLink ) {
        $result = $prefix . $result . $suffix;
      }
    }

    # We log anchor text only if it would be visible in the web browser. This means that for an
    # link to an ordinary page we log the anchor whether an alternative text was available or not
    # (in which case Wikipedia shows just the name of the page).
    #
    # Note that for a link to an image that has no alternative text, we log an empty string.
    # This is important because otherwise the linkLocation wouldn't get stored.

    my $postprocessedResult = $result;
    # anchor text doesn't need escaping of XML characters,
    # hence the second function parameter is 0
    &main::postprocessText(\$postprocessedResult, 0, 0);

    $targetId = undef unless $targetId;
    push(@$refToAnchorTextArray, { targetId     => $targetId, 
                                   anchorText   => $postprocessedResult, 
                                   linkLocation => $linkLocation } );
  }

  # Mark internal links with special magic words that are later converted to XML tags
  # in postprocessText()

  if ( defined($targetId) and length($result) > 0 ) {
    return ".pAriD=\"$targetId\".$result.pArenD."; 
  } else {
    return $result;
  }
}

sub performPipelineMasking(\$\$) {
  my ($refToLink, $refToResult) = @_;

  # First check for presence of a namespace
  if ($$refToLink =~ /^([^:]*):(.*)$/) {
    my $namespaceCandidate = $1;
    my $rest = $2;

    &normalizeNamespace(\$namespaceCandidate);
    if ( &isKnownNamespace(\$namespaceCandidate) ) {
      $$refToResult = $rest; # take the link text without the namespace
    } else {
      $$refToResult = $$refToLink; # otherwise, take the entire link text (for now)
    }
  } else {
    $$refToResult = $$refToLink; # otherwise, take the entire link text (for now)
  }

  # Now check if there are parentheses at the end of the link text
  # (we now operate on $$refToResult, because we might have stripped the leading
  # namespace in the previous test).
  if ($$refToResult =~ /^                  # the beginning of the string
                          (.*)             # the text up to the last pair of parentheses
                          \(               # opening parenthesis
                              (?:[^()]*)   #   the text in the parentheses
                          \)               # closing parenthesis
                          (?:\s*)          # optional trailing whitespace, just in case
                        $                  # end of string
                       /x) {
    $$refToResult = $1; # discard the text in parentheses at the end of the string
  }
}

# Dates can appear in several formats
# 1) [[July 20]], [[1969]]
# 2) [[20 July]] [[1969]]
# 3) [[1969]]-[[07-20]]
# 4) [[1969-07-20]]
# The first one is handled correctly without any special treatment,
# so we don't even check for it here.
# In (2) and (3), we only normalize the day, because it will be parsed separately from the year.
# This function is only invoked if the link has no alternative text available, therefore,
# we're free to override the result text.
sub normalizeDates(\$\$\$\@$) {
  my ($refToLink, $refToResultText, $refToTargetId, $refToAnchorTextArray, $linkLocation) = @_;

  my $dateRecognized = 0;

  if ($$refToLink =~ /^([0-9]{1,2})\s+([A-Za-z]+)$/) {
    my $day = $1;
    my $month = ucfirst(lc($2));

    if ( defined($Wikiprep::Config::monthToNumDays{$month}) &&
         1 <= $day && $day <= $Wikiprep::Config::monthToNumDays{$month} ) {
      $dateRecognized = 1;

      $$refToLink = "$month $day";
      $$refToResultText = "$month $day";

      my $targetId = &resolvePageLink($refToLink);

      $$refToTargetId = $targetId;
      push(@$refToAnchorTextArray, { targetId     => $targetId, 
                                     anchorText   => $$refToResultText,
                                     linkLocation => $linkLocation } );
    } else {
      # this doesn't look like a valid date, leave as-is
    }
  } elsif ($$refToLink =~ /^([0-9]{1,2})\-([0-9]{1,2})$/) {
    my $monthNum = int($1);
    my $day = $2;

    if ( defined($Wikiprep::Config::numberToMonth{$monthNum}) ) {
      my $month = $Wikiprep::Config::numberToMonth{$monthNum};
      if (1 <= $day && $day <= $Wikiprep::Config::monthToNumDays{$month}) {
        $dateRecognized = 1;

        $$refToLink = "$month $day";
        # we add a leading space, to separate the preceding year ("[[1969]]-" in the example")
        # from the day that we're creating
        $$refToResultText = " $month $day";

        my $targetId = &resolvePageLink($refToLink);
        $$refToTargetId = $targetId; 
        push(@$refToAnchorTextArray, { targetId     => $targetId, 
                                       anchorText   => $$refToResultText,
                                       linkLocation => $linkLocation } );
      } else {
        # this doesn't look like a valid date, leave as-is
      }
    } else {
      # this doesn't look like a valid date, leave as-is
    }
  } elsif ($$refToLink =~ /^([0-9]{3,4})\-([0-9]{1,2})\-([0-9]{1,2})$/) {
    my $year = $1;
    my $monthNum = int($2);
    my $day = $3;

    if ( defined($Wikiprep::Config::numberToMonth{$monthNum}) ) {
      my $month = $Wikiprep::Config::numberToMonth{$monthNum};
      if (1 <= $day && $day <= $Wikiprep::Config::monthToNumDays{$month}) {
        $dateRecognized = 1;

        $$refToLink = "$month $day";
        # the link text is combined from the day and the year
        $$refToResultText = "$month $day, $year";

        my $targetId;

        # collect the link for the day
        $targetId = &resolvePageLink($refToLink);
        $$refToTargetId = $targetId; 
        push(@$refToAnchorTextArray, { targetId     => $targetId, 
                                       anchorText   => $$refToLink,
                                       linkLocation => $linkLocation } );

        # collect the link for the year
        $targetId = &resolvePageLink(\$year);
        $$refToTargetId = $targetId; 
        push(@$refToAnchorTextArray, { targetId     => $targetId, 
                                       anchorText   => $year,
                                       linkLocation => $linkLocation } );
      } else {
        # this doesn't look like a valid date, leave as-is
      }
    } else {
      # this doesn't look like a valid date, leave as-is
    }
  }

  $dateRecognized;  # return value
}

1;
