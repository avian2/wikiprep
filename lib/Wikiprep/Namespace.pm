# vim:sw=2:tabstop=2:expandtab

package Wikiprep::Namespace;

use strict;

use Exporter 'import';
use Hash::Util qw( lock_hash );

our @EXPORT_OK = qw( normalizeTitle normalizeNamespace normalizeNamespaceTitle 
                     loadNamespaces isNamespaceOk isKnownNamespace %namespaces );

use Log::Handler wikiprep => 'LOG';

# List of known namespaces defined in the header of the XML file
our %namespaces;

# Title normalization
# ===========================================================================================================

sub normalizeNamespace(\$) {
  my ($refToStr) = @_;

  # Namespaces are always lowercase with capitalized first letter.
  $$refToStr = ucfirst( lc($$refToStr) );

  if( exists($Wikiprep::Config::namespaceAliases{$$refToStr}) ) {
    $$refToStr = $Wikiprep::Config::namespaceAliases{$$refToStr};
  }
}

# This is the function for normalizing titles - It transforms page titles into a form that is
# used throughout Wikiprep to uniquely identify pages, templates, categories, etc.
#
# It does not strip namespace declarations.
sub normalizeTitle {
  my ($refToStr, $defaultNamespace) = @_;

  my ($namespace, $title) = &normalizeNamespaceTitle($$refToStr, $defaultNamespace);
  $$refToStr = $namespace ? $namespace . ":" . $title : $title;
}

sub normalizeNamespaceTitle {
  my ($str, $defaultNamespace) = @_;
  
  # Link definitions may span over adjacent lines and therefore contain line breaks,
  # hence we use the /s modifier on matchings.

  # remove leading whitespace and underscores
  $str =~ s/^[ \f\n\r\t_]+//s;
  # remove trailing whitespace and underscores
  $str =~ s/[ \f\n\r\t_]+$//s;
  # replace sequences of whitespace and underscore chars with a single space
  $str =~ s/[ \f\n\r\t_]+/ /sg;

  # Silently strip LRM, RLM (see docs/title.txt in MediaWiki)
  $str =~ s/[\x{200e}\x{200f}]//g;

  # There are some special cases when the link may be preceded with a colon in the
  # main namespace.
  #
  # Known cases:
  # - Linking to a category (as opposed to actually assigning the current article
  #   to a category) is performed using special syntax [[:Category:...]]
  # - Linking to other languages, e.g., [[:fr:Wikipedia:Aide]]
  #   (without the leading colon, the link will go to the side menu
  # - Linking directly to the description page of an image, e.g., [[:Image:wiki.png]]
  #
  # In all such cases, we strip the leading colon.
  $str =~ s/^: *//s unless $defaultNamespace;
  
  # In other namespaces (e.g. Template), the leading colon forces the link to point
  # to the main namespace.

  if ($str =~ /^([^:]*): *(\S.*)/s) {
    my $namespaceCandidate = $1;
    my $rest = $2;

    # this must be done before the call to 'isKnownNamespace'
    &normalizeNamespace(\$namespaceCandidate); 
    if( &isKnownNamespace(\$namespaceCandidate) ) {
      # If the prefix designates a known namespace, then it might follow by optional
      # whitespace that should be removed to get the canonical page name
      # (e.g., "Category:  Births" should become "Category:Births").
      return $namespaceCandidate, ucfirst($rest);
    } else {
      # No namespace, just capitalize first letter.
      # If the part before the colon is not a known namespace, then we must not remove the space
      # after the colon (if any), e.g., "3001: The_Final_Odyssey" != "3001:The_Final_Odyssey".
      # However, to get the canonical page name we must contract multiple spaces into one,
      # because "3001:   The_Final_Odyssey" != "3001: The_Final_Odyssey".
      return $defaultNamespace, ucfirst($str);
    }
  } else {
    # no namespace, just capitalize first letter
    return $defaultNamespace, ucfirst($str);
  }
}

# Prescan
# ===========================================================================================================

# Load namespaces (during prescan)
sub loadNamespaces {
  my ($pages, $extraNamespaces) = @_;

  my %new_namespaces;

  # namespace names are case-insensitive, so we force them
  # to canonical form to facilitate future comparisons
  if( $pages ) {
    for my $ns ( @{$pages->namespaces} ) {

      my $id = $ns->[0];
      my $name = $ns->[1];

      &normalizeNamespace(\$name);
      $new_namespaces{$name} = $id;
    }
  }

  if( $extraNamespaces ) {
    for my $ns ( @$extraNamespaces ) {
      $new_namespaces{$ns} = "null"; # can't set undef here, because BerkeleyDB breaks on it.
    }
  }

  if( %namespaces ) {
    while( my ($name, $id) = each(%new_namespaces) ) {
      unless(exists($namespaces{$name})) {
        LOG->error("parts of the file have different namespace declarations ($name)");
      }
    }
  } else {
    %namespaces = %new_namespaces;
    lock_hash( %namespaces );
  }
}

# Namespace checking
# ===========================================================================================================

# Checks if the prefix of the page name before the colon is actually one of the
# 16+2+2 namespaces defined in the XML file.
# Assumption: the argument was already normalized using 'normalizeNamespace'
sub isKnownNamespace(\$) {
  my ($refToStr) = @_;

  return exists( $namespaces{$$refToStr} );  # return value
}

sub isNamespaceOk($\%) {
  my ($namespace, $refToNamespaceHash) = @_;

  my $result = 1;

  # main namespace is OK, so we only check pages that belong to other namespaces

  if ($namespace ne '') {
    my $namespace = $namespace;
    &normalizeNamespace(\$namespace);
    if ( &isKnownNamespace(\$namespace) ) {
      $result = exists( $$refToNamespaceHash{$namespace} );
    } else {
      # the prefix before ":" in the page title is not a known namespace,
      # therefore, the page belongs to the main namespace and is OK
    }
  }

  $result; # return value
}

1;
