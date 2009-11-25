# vim:sw=2:tabstop=2:expandtab

package Wikiprep::Link;

use strict;
use warnings;

use Exporter 'import';
use Hash::Util qw( lock_hash );

use Wikiprep::Namespace qw( normalizeTitle normalizeNamespaceTitle isNamespaceOk );
use Wikiprep::images qw( parseImageParameters );

require Wikiprep::Templates;

use Log::Handler wikiprep => 'LOG';

our @EXPORT_OK = qw( %title2id %redir resolveLink parseRedirect extractWikiLinks );

# The following dictionaries are populated during prescan with page titles 
# and are read-only during transform.

# Mapping from normalized page title to page ID
our %title2id;

# Mapping from source page title to destination page title.
our %redir;

# Page title and redirects prescan
# ===========================================================================================================

sub prescan {
    my ($refToTitle, $refToId, $mwpage) = @_;
    
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
      LOG->warning("title $$refToTitle (ID $$refToId) already encountered before (ID $title2id{$$refToTitle})");
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

  return unless defined ${$mwpage->text};

  # quick check
  return if ( ${$mwpage->text} !~ /^#REDIRECT/i );

  if ( ${$mwpage->text} =~ m{^\#REDIRECT         # Redirect must start with "#REDIRECT"
                                                 #   (the backslash is needed before "#" here, because
                                                 #    "#" has special meaning with /x modifier)
                             (?:S|ED|ION)?       # The word may be in any of these forms,
                                                 #   i.e., REDIRECT|REDIRECTS|REDIRECTED|REDIRECTION
                             \s*                 # optional whitespace
                             (?: :|\sTO|=)?      # optional colon, "TO" or "="
                                                 #   (in case of "TO", we expect a whitespace before it,
                                                 #    so that it's not glued to the preceding word)
                             \s*                 # optional whitespace
                             \[\[([^\]]*)\]\]    # the link itself
                            }ix ) {              # matching is case-insensitive, hence /i
    my $target = $1;

    if ($target =~ /^(.*)#.*$/) {
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

  my $targetTitle = $$refToTitle;

  if ( exists($redir{$targetTitle}) ) { 
    # this link is a redirect
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

  return unless defined($targetTitle);

  if ( exists($title2id{$targetTitle}) ) {
    return $title2id{$targetTitle};
  } else {
    LOG->info("link '$$refToTitle' cannot be matched to an known ID");
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
    
    #LOG->info("unknown link '$$refToTitle'");
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

sub extractWikiLinks {
  my ($refToText, $refToAnchorTextArray, $refToInterwikiArray, $refToCategoryArray) = @_;

  my $collectWikiLink = sub {
    my $prefix = $1;
    my $link = $2;
    my $suffix = $3;

    return $prefix . $suffix unless $link;

    my $linkLocation = $-[0];

    # First check if this is a link to a date. Date links are normalized first, so this
    # function returns a string, that contains the normalized link (e.g. "[[July 4]]).
    
    # Since we replace links in a loop in extractWikiLinks(), these will get picked up on
    # later iterations.
    if( $link =~ /^\s*\d/ and my $dates = &normalizeDates(\$link) ) {
      return $prefix . $dates . $suffix;
    }

    # Split link text into fields delimited by pipe characters. "-1" parameter to split permits
    # empty trailing fields (important for pipeline masking)
    my ($firstField, @pipeFields) = split(/\|/, $link, -1);

    # Nested link before the first | is illegal.
    if( $firstField =~ /\.pAriD=~/ ) {
      return $prefix . $link . $suffix;
    }

    # The fields before the first pipe character is the link destination.
    my ($linkNamespace, $linkTitleSection) = &normalizeNamespaceTitle($firstField);

    return $prefix . $suffix unless $linkTitleSection;

    # The link can contain a section reference after the hash character. If the part of the link 
    # before the hash is empty, it points to a section on the current page. 
    my ($linkTitle, $linkSection) = split(/\s*#/, $linkTitleSection, 2);

    my $linkNamespaceTitle = $linkNamespace ? "$linkNamespace:$linkTitle" : $linkTitle;

    # Target page of the link.
    my $targetId = &resolvePageLink(\$linkNamespaceTitle);

    # If this is a link to category namespace, remove the link completely and 
    if( $linkNamespace and $linkNamespace eq $Wikiprep::Config::categoryNamespace ) {
      if( $targetId ) {
        push(@{$refToCategoryArray}, $targetId) if $refToCategoryArray;
      } else {
        LOG->info("unknown category '$linkTitle'");
      }
      return $prefix . $suffix;
    }

    # Determine the anchor text. This is the blue underlined text that is seen in the browser 
    # in place of the [[...]] link.
    my $anchor;
    my $noAltText;
    my $noGlue;
    
    if( $linkNamespace and $linkNamespace eq $Wikiprep::Config::imageNamespace ) {
      # Image links must be parsed separately, since they can contain multiple pipe delimited
      # fields that set thumbnail size and style in addition to the anchor string (in this case
      # the anchor string is the short caption that appears below the thumbnail).
      $anchor = &parseImageParameters(\@pipeFields);
      $noGlue = 1;
    } else {
      $anchor = pop(@pipeFields);
      if( not defined $anchor ) {
        # the link text does not contain the pipeline, so take it as-is
        $anchor = $link;
        $noAltText = 1;
      } elsif( $anchor eq "" and not $linkSection ) {
        # If the "|" symbol is not followed by some text, then it masks everything before the
        # first colon as well as any text in parentheses at the end of the link title.
        # However, pipeline masking is only invoked if the link does not contain a section 
        # reference, hence the additional condition in the 'if' statement.
        $anchor = $firstField;
        $anchor =~ s/^\s*[^:]*:\s*//s;
        $anchor =~ s/\s*\([^()]*\)\s*$//s;
      }
      $anchor = $prefix . $anchor . $suffix;
    }


    # We log anchor text only if it would be visible in the web browser. This means that for an
    # link to an ordinary page we log the anchor whether an alternative text was available or not
    # (in which case Wikipedia shows just the name of the page).
    
    # Note that for a link to an image that has no alternative text, we log an empty string.
    # This is important because otherwise the linkLocation wouldn't get stored.

    my %anchorStruct = ( anchorText   => $anchor,
                         linkLocation => $linkLocation );

    # anchor text doesn't need escaping of XML characters,
    # hence the second function parameter is undefined
    &main::postprocessText(\$anchorStruct{anchorText});

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
    if( not $targetId ) {
      if( $linkNamespace and exists( $Wikiprep::Config::okNamespacesForInterwikiLinks{$linkNamespace} ) ) {

        if( $refToInterwikiArray ) {
          push(@$refToInterwikiArray, [ $linkNamespace, $linkTitle ]);

          $anchorStruct{targetNamespace} = $linkNamespace;
          $anchorStruct{targetTitle} = $linkTitle;

          $targetId = "!$#$refToInterwikiArray";
        } else {
          $anchor = "";
        }
      } elsif( $noAltText && $link =~ /:/ ) {
        $anchor = "";
        LOG->info("Discarding text for link '", $link, "'");
      }
    } else {
      $anchorStruct{targetId} = $targetId;
    }

    push(@$refToAnchorTextArray, \%anchorStruct);

    # Mark internal links with special magic words that are later converted to XML tags
    # in postprocessText()

    my $retval;
    if( defined($targetId) ) {
      $retval = ".pAriD=~" . $targetId . "~." . $anchor . ".pArenD."; 
    } else {
      $retval = $anchor;
    }

    # In case we didn't add prefix and suffix to the anchor, add them here so 
    # they don't get lost.
    if( $noGlue ) {
      return $prefix . $retval . $suffix;
    } else {
      return $retval;
    }
  };

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
  
  1 while ( $$refToText =~ s/$internalLinkRegex/$collectWikiLink->()/eg );
}

# Dates can appear in several formats
# 1) [[July 20]], [[1969]]
# 2) [[20 July]] [[1969]]
# 3) [[1969]]-[[07-20]]
# 4) [[1969-07-20]]
#
# The first one is handled correctly without any special treatment,
# so we don't even check for it here.
#
# In (2) and (3), we only normalize the day, because it will be parsed separately from the year.
sub normalizeDates {
  my ($refToLink) = @_;

  if( $$refToLink =~ /^\s*([0-9]{1,2})\s+([A-Za-z]+)\s*$/) {
    my $day = $1;
    my $month = ucfirst(lc($2));

    if( exists($Wikiprep::Config::monthToNumDays{$month}) &&
         1 <= $day && $day <= $Wikiprep::Config::monthToNumDays{$month} ) {

      return "[[$month $day]]"
    }
  } elsif( $$refToLink =~ /^\s*([0-9]{1,2})\-([0-9]{1,2})\s*$/) {
    my $monthNum = int($1);
    my $day = $2;

    if( exists($Wikiprep::Config::numberToMonth{$monthNum}) ) {
      my $month = $Wikiprep::Config::numberToMonth{$monthNum};
      if (1 <= $day && $day <= $Wikiprep::Config::monthToNumDays{$month}) {
        return "[[$month $day]]";
      }
    } 
  } elsif( $$refToLink =~ /^\s*([0-9]{3,4})\-([0-9]{1,2})\-([0-9]{1,2})\s*$/) {
    my $year = $1;
    my $monthNum = int($2);
    my $day = $3;

    if( exists($Wikiprep::Config::numberToMonth{$monthNum}) ) {
      my $month = $Wikiprep::Config::numberToMonth{$monthNum};
      if (1 <= $day && $day <= $Wikiprep::Config::monthToNumDays{$month}) {

        return "[[$month $day]], [[$year]]"
      }
    }
  }
}

1;
