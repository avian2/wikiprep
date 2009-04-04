# vim:sw=2:tabstop=2:expandtab

package Wikiprep::Link;

use strict;
use warnings;

use Exporter 'import';
use Hash::Util qw( lock_hash );

use threads;
use threads::shared;

use Wikiprep::Namespace qw( normalizeTitle isNamespaceOk isTitleOkForLocalPages );

use Log::Handler wikiprep => 'LOG';

our @EXPORT_OK = qw( %title2id %redir resolveLink resolvePageLink parseRedirect );

# The following dictionaries are populated during prescan with page titles 
# and are read-only during transform.

# Mapping from normalized page title to page ID
our %title2id :shared;

# Mapping from normalized page title to page ID (for "local" page IDs added by Wikiprep)
my %localTitle2id :shared;

# ID assigned to the next local page (always larger than the largest ID in the dump)
my $nextLocalID :shared = 0;

# Mapping from source page title to destination page title.
our %redir :shared;

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
      	# Assign a local ID otherwise and add the nonexistent page to %title2id hash
        $targetId = $nextLocalID;
        $nextLocalID++;

        $title2id{$targetTitle}=$targetId;

        $main::out->newLocalID( $targetId, $targetTitle );

        LOG->debug("link '$$refToTitle' cannot be matched to an known ID, assigning local ID");
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

  #use Data::Dumper;
  #print Dumper(\%main::templates);

  my $targetId = &resolveLink($refToTitle);
  if ( defined($targetId) ) {
    if ( exists($main::templates{$targetId}) ) {
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

1;
